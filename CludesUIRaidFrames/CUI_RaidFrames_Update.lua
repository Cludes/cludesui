if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Update.lua
--
--  The ping marker, the role, leader and combat icons, UpdateButton, dispel
--  detection, the ready check, the unit map and UpdateAllButtons.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local type = type
local tostring = tostring
local select = select
local UnitHealth = UnitHealth
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsConnected = UnitIsConnected
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitIsUnit = UnitIsUnit
local GetReadyCheckStatus = GetReadyCheckStatus
local C_IncomingSummon = C_IncomingSummon
local GetRaidTargetIndex = GetRaidTargetIndex
local C_Timer = C_Timer
local issecretvalue = issecretvalue
local CreateFrame = CreateFrame

local AbbreviateNumbers, allButtons = Inner.AbbreviateNumbers, Inner.allButtons
local ApplyRoleIcon, ERF, GetFFD, PixelSnap = Inner.ApplyRoleIcon, Inner.ERF, Inner.GetFFD, Inner.PixelSnap
local RAID_MARKER_TEXCOORDS = Inner.RAID_MARKER_TEXCOORDS
local SUMMON_STATUS_ACCEPTED = Inner.SUMMON_STATUS_ACCEPTED
local SUMMON_STATUS_DECLINED = Inner.SUMMON_STATUS_DECLINED
local SUMMON_STATUS_PENDING, unitToButton = Inner.SUMMON_STATUS_PENDING, Inner.unitToButton
local unitTrackers, GetHealthColor = Inner.unitTrackers, Inner.GetHealthColor
local GetPowerColor, GetSafeHealthPercent = Inner.GetPowerColor, Inner.GetSafeHealthPercent
local GetTopNameBarColor, ResolveDisplayName = Inner.GetTopNameBarColor, Inner.ResolveDisplayName
local UpdateAbsorb = Inner.UpdateAbsorb

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
local inCombat = false
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val) inCombat = val end

-------------------------------------------------------------------------------
--  Unit ping marker (parity with the default raid frames): when a group member
--  is pinged, the marker Blizzard draws on its compact frame appears on that
--  member's button here.
--
--  There is no direct channel: the pin events (UNIT_PING_PIN_ADDED / _REMOVED)
--  are restricted (addon RegisterEvent = forbidden, like the combat log) and
--  their only consumer template is forbidden to instantiate from addon code.
--  What IS reachable: the ping icon frame Blizzard already built on each of
--  its own compact frames is an ordinary object, and the raid module keeps
--  those frames alive -- the container is parked off-screen but the manager
--  still runs every roster layout through it (SetUpFrame fires per compact
--  frame per roster event). Blizzard's handler resolves the pinned GUID to a
--  frame and applies the showPingsOnRaidFrames CVar gate before it calls
--  ShowPing / ClearPing on that icon, so a secure post-hook on those two
--  methods hands us the texture kit and the owning compact frame's unit
--  token; the token maps to our button(s) and the same atlases go on our own
--  overlay. Hooks are installed per icon from a CompactUnitFrame_SetUpFrame
--  post-hook (once per icon object; nameplate compact frames are skipped for
--  good). Parity is total: same trigger, same CVar, same art (an ability
--  ping's kit has no frame art and lights nothing, see ns._PingKitArt). Zero
--  work between pings; overlays are built on first use.
--
--  Blizzard's own icon never clears when the pinged person moves to another
--  compact frame before the pin expires (the removed edge no longer matches
--  that frame), so a mirror needs two belts: our unit hook hides the overlay
--  on an occupant change, and a shown overlay expires on its own after the
--  longest a pin can live.
-------------------------------------------------------------------------------
mod._pingHooked = setmetatable({}, { __mode = "k" }) -- Blizzard icon -> true (hooked) / false (never)
mod._pingLitBtn = setmetatable({}, { __mode = "k" }) -- Blizzard icon -> our button it lit
mod._pingLitXf = setmetatable({}, { __mode = "k" }) -- Blizzard icon -> Extra Frames duplicate it lit
mod.PING_EXPIRE = 20

-- Position + size from the (party/extra-aware) settings: the same 9-point
-- anchor set as the raid marker, and the size as a factor of Blizzard's native
-- 30 so both atlases keep their proportions. Re-run by every reload path that
-- re-anchors the other indicators.
mod._RFAnchorPing = function(skinData)
    local popFrame = skinData.pingFrame
    if not popFrame then return end
    local cfg = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile
    local size = PixelSnap(cfg.pingMarkerSize or 30)
    popFrame:SetSize(size, size)
    popFrame._factor = size / 30
    local owner = mod.RF_AnchorHost(skinData.health, cfg)
    local place = cfg.pingMarkerPosition or "center"
    local ox = cfg.pingMarkerOffsetX or 0
    local oy = cfg.pingMarkerOffsetY or 0
    popFrame:ClearAllPoints()
    if place == "topleft" then
        popFrame:SetPoint("TOPLEFT", owner, "TOPLEFT", 2 + ox, -2 + oy)
    elseif place == "top" then
        popFrame:SetPoint("TOP", owner, "TOP", ox, -2 + oy)
    elseif place == "topright" then
        popFrame:SetPoint("TOPRIGHT", owner, "TOPRIGHT", -2 + ox, -2 + oy)
    elseif place == "left" then
        popFrame:SetPoint("LEFT", owner, "LEFT", 2 + ox, oy)
    elseif place == "right" then
        popFrame:SetPoint("RIGHT", owner, "RIGHT", -2 + ox, oy)
    elseif place == "bottomleft" then
        popFrame:SetPoint("BOTTOMLEFT", owner, "BOTTOMLEFT", 2 + ox, 2 + oy)
    elseif place == "bottom" then
        popFrame:SetPoint("BOTTOM", owner, "BOTTOM", ox, 2 + oy)
    elseif place == "bottomright" then
        popFrame:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -2 + ox, 2 + oy)
    else
        popFrame:SetPoint("CENTER", owner, "CENTER", ox, oy)
    end
end

mod._RFPingOverlay = function(btnFrame, skinData)
    local popFrame = skinData.pingFrame
    if popFrame then return popFrame end
    popFrame = CreateFrame("Frame", nil, btnFrame)
    popFrame:SetFrameLevel(btnFrame:GetFrameLevel() + mod.LVL_MARKER + 1)
    popFrame:EnableMouse(false)
    popFrame.bg = popFrame:CreateTexture(nil, "BACKGROUND")
    popFrame.bg:SetPoint("CENTER")
    popFrame.icon = popFrame:CreateTexture(nil, "ARTWORK")
    popFrame.icon:SetPoint("CENTER")
    popFrame:Hide()
    skinData.pingFrame = popFrame
    mod._RFAnchorPing(skinData)
    return popFrame
end

mod._RFPingHide = function(btnFrame)
    if not btnFrame then return end
    local skinData = GetFFD(btnFrame)
    if skinData.pingFrame then skinData.pingFrame:Hide() end
end

-- Frame art per texture kit, read once: both atlases with their native sizes,
-- or false when the kit has no frame art. Ability pings carry such kits
-- ("Available" / "Unavailable"): Blizzard's SetAtlas fails on them and its icon
-- keeps the art it last had, so they light nothing here. Sizes always come
-- from the atlas info, never from a texture's current size (a failed SetAtlas
-- leaves that size as it was).
mod._pingKitArt = {}
mod._PingKitArt = function(kit)
    local art = mod._pingKitArt[kit]
    if art == nil then
        local backdrop, iconTex = "Ping_Frame_BG_" .. kit, "Ping_Frame_" .. kit
        local bgInfo, iconInfo = C_Texture.GetAtlasInfo(backdrop), C_Texture.GetAtlasInfo(iconTex)
        art = bgInfo
                and iconInfo
                and {
                    bg = backdrop,
                    bgW = bgInfo.width,
                    bgH = bgInfo.height,
                    icon = iconTex,
                    iconW = iconInfo.width,
                    iconH = iconInfo.height,
                }
            or false
        mod._pingKitArt[kit] = art
    end
    return art
end

-- Both atlases at their native size times the configured factor (each keeps
-- its own proportions).
mod._RFPingLight = function(btnFrame, kit)
    local art = mod._PingKitArt(kit)
    if not art then return end
    local skinData = GetFFD(btnFrame)
    local cfg = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile
    if cfg.showPingMarker == false then return end
    local popFrame = mod._RFPingOverlay(btnFrame, skinData)
    local factor = popFrame._factor or 1
    popFrame.bg:SetAtlas(art.bg)
    popFrame.bg:SetSize(art.bgW * factor, art.bgH * factor)
    popFrame.icon:SetAtlas(art.icon)
    popFrame.icon:SetSize(art.iconW * factor, art.iconH * factor)
    popFrame:Show()
    -- Expiry belt: a pin has a finite engine lifetime; if its removed edge can
    -- no longer reach this button (see header), the overlay still goes away.
    local stamp = (skinData._pingStamp or 0) + 1
    skinData._pingStamp = stamp
    C_Timer.After(mod.PING_EXPIRE, function()
        if skinData._pingStamp == stamp and skinData.pingFrame then skinData.pingFrame:Hide() end
    end)
end

mod._OnCufShowPing = function(iconTex, kit)
    if issecretvalue(kit) or type(kit) ~= "string" then return end
    local ownerFrame = iconTex:GetParent()
    local unitToken = ownerFrame and ownerFrame.unit
    if type(unitToken) ~= "string" then return end
    local button = unitToButton[unitToken] or mod._partyUnitToButton[unitToken]
    local xf = mod._xfUnitToButton[unitToken]
    -- The icon re-lit for a different occupant: release what it lit before.
    local prevB, prevX = mod._pingLitBtn[iconTex], mod._pingLitXf[iconTex]
    if prevB and prevB ~= button then mod._RFPingHide(prevB) end
    if prevX and prevX ~= xf then mod._RFPingHide(prevX) end
    if button then mod._RFPingLight(button, kit) end
    if xf then mod._RFPingLight(xf, kit) end
    mod._pingLitBtn[iconTex], mod._pingLitXf[iconTex] = button, xf
end

mod._OnCufClearPing = function(iconTex)
    local b, posX = mod._pingLitBtn[iconTex], mod._pingLitXf[iconTex]
    if not b and not posX then return end
    mod._pingLitBtn[iconTex], mod._pingLitXf[iconTex] = nil, nil
    mod._RFPingHide(b)
    mod._RFPingHide(posX)
end

mod._HookCufPingIcon = function(cuf)
    local iconTex = cuf and cuf.pingIconFrame
    if not iconTex then return end
    local state = mod._pingHooked[iconTex]
    if state ~= nil then return end
    -- Nameplate compact frames carry the same child; never ours to mirror.
    local okN, name = pcall(cuf.GetName, cuf)
    if okN and type(name) == "string" and name:find("^NamePlate") then
        mod._pingHooked[iconTex] = false
        return
    end
    local okF, forbidden = pcall(iconTex.IsForbidden, iconTex)
    if not okF or forbidden then
        mod._pingHooked[iconTex] = false
        return
    end
    mod._pingHooked[iconTex] = true
    hooksecurefunc(iconTex, "ShowPing", mod._OnCufShowPing)
    hooksecurefunc(iconTex, "ClearPing", mod._OnCufClearPing)
end

if type(CompactUnitFrame_SetUpFrame) == "function" then
    hooksecurefunc("CompactUnitFrame_SetUpFrame", mod._HookCufPingIcon)
end

-------------------------------------------------------------------------------
--  Role icon show/hide decision. Shared by UpdateButton and the lightweight
--  ns._UpdateRoleIcons combat-transition updater (lockstep). Honors the "Hide In
--  Combat" cog (hidden in combat, restored on PLAYER_REGEN_ENABLED).
-------------------------------------------------------------------------------
-- A SECRET role (a unit whose identity the client hides) cannot be read here,
-- so Blizzard's secret-safe painter (UnitFrameUtil, 12.1.5+) sets a texture of
-- ours from a map in the frame's own icon style. Roles the settings hide, and
-- the vehicle state, map to no texture, so it shows what the plain path would.
-- Before 12.1.5 (and with Role Text on) a secret role stays hidden, as before.
local secretRoleMaps = {} -- style -> toggle bits -> texture map
local function SecretRoleMap(style, cfg)
    local styleMap = mod.ROLE_ICON_STYLES[style]
    if not styleMap then return nil end
    local bits = (cfg.showRoleForTank and 1 or 0)
        + (cfg.showRoleForHealer and 2 or 0)
        + (cfg.showRoleForDPS and 4 or 0)
    local byStyle = secretRoleMaps[style]
    if not byStyle then
        byStyle = {}
        secretRoleMaps[style] = byStyle
    end
    local map = byStyle[bits]
    if not map then
        map = {
            TANK = cfg.showRoleForTank and styleMap.TANK or "",
            HEALER = cfg.showRoleForHealer and styleMap.HEALER or "",
            DAMAGER = cfg.showRoleForDPS and styleMap.DAMAGER or "",
            VEHICLE = "",
        }
        byStyle[bits] = map
    end
    return map
end

local function PaintSecretRole(skinData, unitToken, style, cfg)
    local paint = UnitFrameUtil and UnitFrameUtil.UpdateUnitFrameRoleIcon
    local map = paint and not cfg.roleText and SecretRoleMap(style, cfg)
    local texture = skinData.roleIconSecret
    if not map then
        if texture then texture:Hide() end
        return
    end
    if not texture then
        local iconTex = skinData.roleIcon
        local layer, sub = iconTex:GetDrawLayer()
        texture = iconTex:GetParent():CreateTexture(nil, layer, nil, sub)
        texture:SetAllPoints(iconTex)
        skinData.roleIconSecret = texture
        skinData.roleSecretProxy =
            { roleIcon = texture, optionTable = { displayRoleIcon = true, displayRaidRoleIcon = false } }
    end
    local proxy = skinData.roleSecretProxy
    proxy.unit = unitToken
    proxy.optionTable.textureMap = map
    pcall(paint, proxy)
end

local function UpdateRoleIconShown(skinData, cfg, unitToken)
    local roleIcon = skinData.roleIcon
    if not roleIcon then return end
    if roleIcon._roleText then roleIcon._roleText:Hide() end
    local secretTex = skinData.roleIconSecret
    local style = cfg.roleIconStyle or "modern"
    if style == "none" and not cfg.roleText then
        roleIcon:Hide()
        if secretTex then secretTex:Hide() end
        return
    end
    if cfg.roleIconHideInCombat and inCombat then
        roleIcon:Hide()
        if secretTex then secretTex:Hide() end
        return
    end
    local role, roleSecret = CludesUI.UnitEffectiveRole(unitToken)
    if roleSecret then
        roleIcon:Hide()
        PaintSecretRole(skinData, unitToken, style, cfg)
    elseif role then
        if secretTex then secretTex:Hide() end
        local showForRole = (role == "TANK" and cfg.showRoleForTank)
            or (role == "HEALER" and cfg.showRoleForHealer)
            or (role == "DAMAGER" and cfg.showRoleForDPS)
        if showForRole and (cfg.roleText or ApplyRoleIcon(roleIcon, role, style)) then
            roleIcon:Show()
            if cfg.roleText then mod.ApplyRoleText(roleIcon, role, cfg) end
        else
            roleIcon:Hide()
        end
    else
        roleIcon:Hide()
        if secretTex then secretTex:Hide() end
    end
end

-- Attach Role Icons: the name only makes room on frames whose icon shows (a secret
-- role's Blizzard-painted icon counts as shown).
mod._UpdateRoleIcon = function(skinData, cfg, unitToken)
    if not skinData.roleIcon then return end
    UpdateRoleIconShown(skinData, cfg, unitToken)
    local tnb = skinData.topNameBar
    if not (cfg.roleIconOnNameBar and tnb and skinData.topNameBarText) then return end
    local sec = skinData.roleIconSecret
    local secShown = sec and sec:IsShown()
    local has = skinData.roleIcon:IsShown() or issecretvalue(secShown) or secShown or false
    if tnb._cuiRoleIcon ~= has then
        tnb._cuiRoleIcon = has
        mod.RF_PlaceTopNameText(skinData.topNameBarText, tnb, cfg)
    end
end

-------------------------------------------------------------------------------
--  Leader/assistant icon show/hide decision. Shared by UpdateButton and the
--  lightweight ns._UpdateLeaderIcons combat-transition updater (lockstep). Honors
--  the "Show In Combat" cog (default on; off = hidden in combat).
-------------------------------------------------------------------------------
mod._UpdateLeaderIcon = function(skinData, cfg, unitToken)
    local leaderIcon = skinData.leaderIcon
    if not leaderIcon then return end
    if not cfg.showLeaderIcon then
        leaderIcon:Hide()
        return
    end
    if cfg.showLeaderIconInCombat == false and inCombat then
        leaderIcon:Hide()
        return
    end
    local isLeader = UnitIsGroupLeader(unitToken)
    local isAssist = UnitIsGroupAssistant(unitToken)
    if not issecretvalue(isLeader) and isLeader then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    elseif not issecretvalue(isAssist) and isAssist then
        leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-AssistantIcon")
        leaderIcon:SetTexCoord(0, 1, 0, 1)
        leaderIcon:Show()
    else
        leaderIcon:Hide()
    end
end

-------------------------------------------------------------------------------
--  Combat icon show/hide decision: members currently affecting combat (M+ skip
--  awareness). Driven by UpdateButton and the lightweight ns._UpdateCombatIcons
--  updater (UNIT_FLAGS / regen). Texture Show/Hide is combat-legal. On ns (cap).
-------------------------------------------------------------------------------
mod._UpdateCombatIcon = function(skinData, cfg, unitToken)
    local iconTex = skinData.combatIcon
    if not iconTex then return end
    if not cfg.showCombatIndicator then
        iconTex:Hide()
        return
    end
    local c = UnitAffectingCombat(unitToken)
    if issecretvalue(c) or not c then
        iconTex:Hide()
        return
    end

    local CludesUI = mod.CludesUI
    local style = cfg.combatIndicatorStyle or "standard"
    local MEDIA = mod._COMBAT_MEDIA
    if style:find("^combat%d") then
        iconTex:SetTexture(MEDIA .. style .. ".tga")
        iconTex:SetTexCoord(0, 1, 0, 1)
        if iconTex.SetDesaturated then iconTex:SetDesaturated(false) end
        iconTex:SetVertexColor(1, 1, 1, 1)
    else
        local classToken = skinData.classToken
        if not classToken then
            local _, classTok = UnitClass(unitToken)
            classToken = classTok
        end
        if classToken and issecretvalue(classToken) then classToken = nil end
        if style == "class" then
            iconTex:SetTexture(MEDIA .. "combat-indicator-class-custom.png")
            local coords = classToken and mod._COMBAT_CLASS_COORDS[classToken]
            if coords then
                iconTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            else
                iconTex:SetTexCoord(0, 1, 0, 1)
            end
        else
            iconTex:SetTexture(MEDIA .. "combat-indicator-custom.png")
            iconTex:SetTexCoord(0, 1, 0, 1)
        end
        local colorMode = cfg.combatIndicatorColor or "custom"
        if colorMode == "classcolor" then
            local cc = (classToken and CludesUI.GetClassColor(classToken)) or { r = 1, g = 1, b = 1 }
            iconTex:SetVertexColor(cc.r, cc.g, cc.b, 1)
        else
            local cc = cfg.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
            iconTex:SetVertexColor(cc.r, cc.g, cc.b, 1)
        end
    end
    iconTex:Show()
end

-------------------------------------------------------------------------------
--  Update all visual elements for a single button
-------------------------------------------------------------------------------
local function UpdateButton(btnFrame)
    local CludesUI = mod.CludesUI -- upvalue read, not a global read (see the taint note at the top of CludesUIRaidFrames.lua)
    local unitToken = btnFrame:GetAttribute("unit")
    if not unitToken or not UnitExists(unitToken) then
        btnFrame:SetAlpha(0)
        local pd = GetFFD(btnFrame)
        if pd.pt and pd.pt._3dOn then mod.RF_PtModelAlpha(pd, 0) end
        return
    end

    local skinData = GetFFD(btnFrame)
    -- Login gap guard: events registered in the loading-screen window can
    -- dispatch before the deferred styling pass builds this button's visual
    -- body; the pass ends with a full repaint, so skipping here loses nothing.
    if not skinData.styled then return end
    if not skinData.styled then return end

    local cfg = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile
    -- Restore alpha respecting BM frame alpha + range alpha. nil rangeAlpha = managed by the
    -- secret-safe SetAlphaFromBoolean path; overriding it flashes full alpha until the next
    -- range ticker run (0.2s).
    if skinData.rangeAlpha then
        local baseA = btnFrame._bmSavedAlpha or 1
        btnFrame:SetAlpha(baseA * skinData.rangeAlpha)
        if skinData.pt and skinData.pt._3dOn then
            mod.RF_PtModelAlpha(skinData, baseA * skinData.rangeAlpha)
        end
    end

    -- Health: percent-based, secret-value safe; smooth interpolation optional.
    local smooth = cfg.smoothBars
        and Enum
        and Enum.StatusBarInterpolation
        and Enum.StatusBarInterpolation.ExponentialEaseOut

    local health = skinData.health
    -- Offline/dead units keep the gray tint _ApplyHealthBg owns. That tint is
    -- state-stamped there (applied on the transition, not on every call), so a
    -- full paint must never lay a class color over it -- the same split as
    -- Blizzard's UpdateHealthColor, which grays those units itself.
    local connected = UnitIsConnected(unitToken)
    local deadOrGhost = UnitIsDeadOrGhost(unitToken)
    if health then
        -- Inverted Fill (the bar's _cuiInv stamp) paints missing health for every
        -- unit, so the current-health area the Health Bar Color tints and the dispel
        -- wash cover (ns.RF_AnchorCurHealth) is the unit's own, last-known while
        -- offline. A corpse paints a full missing bar, the empty current-health area
        -- of a normal bar at 0%; _ApplyHealthBg hides that fill over the Dead colour.
        local pct
        if health._cuiInv then
            pct = deadOrGhost and 100 or GetSafeHealthPercent(unitToken, true)
        else
            pct = GetSafeHealthPercent(unitToken)
        end
        health:SetMinMaxValues(0, 100)
        if smooth then
            health:SetValue(pct, smooth)
        else
            health:SetValue(pct)
        end

        if connected and not deadOrGhost then
            local red, green, blue = GetHealthColor(unitToken, cfg)
            local fillTex = health:GetStatusBarTexture()
            if cfg.healthColorMode == "dark" then
                health:SetStatusBarColor(red, green, blue, 1)
                -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
                if fillTex then fillTex:SetAlpha(select(4, CludesUI.GetDarkModeFill())) end
            else
                if fillTex then fillTex:SetAlpha(1) end
                health:SetStatusBarColor(red, green, blue, (cfg.healthBarOpacity or 100) / 100)
            end
        end
    end

    -- Background (+ dead/offline status tint). Centralized in ns._ApplyHealthBg so the lightweight UNIT_HEALTH path stays in lockstep.
    mod._ApplyHealthBg(skinData, health, cfg, unitToken, connected, deadOrGhost)

    -- Power (filtered by role + hide if unit has no power)
    mod._PaintPower(btnFrame, skinData, cfg, unitToken)

    -- Absorb (full paint: re-read the reduced-max percent too)
    skinData._rmhPct = nil
    UpdateAbsorb(btnFrame, unitToken)

    mod._PaintButtonTail(btnFrame, skinData, cfg, unitToken)
end

-- Power bar layout + value: role-gated show/hide, health-height reflow, then the
-- value/color push. Split out of UpdateButton so the roster-state refresh
-- (ns._RefreshRosterState) can re-evaluate the role gate without a full paint.
mod._PaintPower = function(btnFrame, skinData, cfg, unitToken)
    local power = skinData.power
    if power then
        local role = mod._ResolvePowerRole(unitToken)
        local showForRole = (role == "HEALER" and cfg.powerShowForHealer)
            or (role == "TANK" and cfg.powerShowForTank)
            or (role == "DAMAGER" and cfg.powerShowForDPS)
            or (role == "NONE" and cfg.powerShowForDPS)
        local pType = UnitPowerType(unitToken) or 0
        -- maxPower can be a secret number in group context; NEVER compare it in Lua. Treat the unit as powerless only on a CLEAN zero max.
        local pmx = UnitPowerMax(unitToken, pType)
        local cleanNoPower = (not issecretvalue(pmx)) and (not pmx or pmx == 0)
        local hidePower = not showForRole or cleanNoPower

        -- The Top Name Bar always reserves height from the top (anchor set by LayoutTopNameBar);
        -- subtract it so this per-unit power show/hide never expands health back over the bar.
        local tnbH = (cfg.topNameBarEnabled and PixelSnap(cfg.topNameBarHeight or 20)) or 0
        -- Extra Frames duplicates carry a per-group size offset (Extra Height), so the BUTTON is
        -- authoritative -- the shared setting would shrink health and leave a gap every update.
        local frameH = skinData._isExtra and btnFrame:GetHeight() or (cfg.frameHeight or 46)

        -- Party Frames kit: the mana bar is part of the stock frame and always
        -- shows (an empty track reads as no mana); the kit owns the bar rects.
        if skinData.kit then
            skinData._appliedHidePower = false
            hidePower = false
        end

        -- power:Show()/Hide() and the two SetHeight branches below reflow every decoration
        -- anchored to health (RF_AnchorHost anchors to the live health frame, not a stable
        -- ref). Applying that transition on every call lets an in-combat identity/roster event
        -- (role resync race, a GROUP_ROSTER_UPDATE storm at pull start) pop the whole button's
        -- content stack mid-fight. Only run the transition when hidePower actually changes, and
        -- defer it to combat end if combat is up; flushed from PLAYER_REGEN_ENABLED alongside
        -- the existing _rosterDirtyInCombat/_sizeTierDirtyInCombat deferrals. nil (fresh occupant,
        -- see the OnAttributeChanged reset) applies immediately so a first paint never inherits
        -- a stale layout -- EXCEPT when the health bar is already protected in combat: aura
        -- containers born in the secure environment anchor to it, and a mid-pull header
        -- reassignment (new occupant on a built button) would then write SetHeight under lockdown
        -- and be blocked. A first paint after a mid-combat reload has nothing anchored yet, so
        -- IsProtected is false there and it still applies.
        if skinData._appliedHidePower ~= hidePower then
            if
                inCombat
                and (skinData._appliedHidePower ~= nil or (skinData.health and skinData.health:IsProtected()))
            then
                skinData._powerDirtyInCombat = true
                mod._powerDirtyInCombat = true
            else
                skinData._appliedHidePower = hidePower
                if hidePower then
                    power:Hide()
                    if skinData.powerBorderFrame and skinData.powerBorderFrame._powerArtKey then
                        mod.RF_ClearPowerBorderArt(skinData.powerBorderFrame)
                    end
                    if skinData.powerBorderFrame then skinData.powerBorderFrame:Hide() end
                    mod.RF_TextPowerHide(skinData)
                    -- Expand health bar to full frame height (minus the Top Name Bar)
                    if skinData.health then skinData.health:SetHeight(PixelSnap(frameH - tnbH)) end
                else
                    -- Restore health bar height with power bar space (and Top Name Bar)
                    local powerH = PixelSnap(cfg.powerHeight or 4)
                    if skinData.health then
                        skinData.health:SetHeight(
                            PixelSnap(frameH - mod.RF_HealthPowerInset(cfg, powerH) - tnbH)
                        )
                    end
                end
            end
        end

        -- Value/color refresh for the power bar in its last APPLIED shown state (not the
        -- freshly computed one), so a deferred transition keeps rendering the old state
        -- instead of updating a bar whose show/hide hasn't actually changed yet.
        if skinData._appliedHidePower == false then
            -- Smooth interpolation only animates correctly on a bar already shown last frame; on a
            -- fresh hidden->shown transition (profile swap replacing the fill texture) it leaves
            -- the fill at 0. Snap plainly on first show, smooth only after that.
            local wasShown = power:IsShown()
            power:Show()
            if skinData.UpdatePowerBorder then skinData.UpdatePowerBorder() end
            -- Power Texts: shown ahead of the edge below, which colours them.
            mod.RF_TextPowerShow(skinData, cfg)
            local smoothPower = wasShown
                and cfg.smoothPowerBars
                and Enum
                and Enum.StatusBarInterpolation
                and Enum.StatusBarInterpolation.ExponentialEaseOut
            -- Percent-based, secret-safe (mirrors health). UnitPower/UnitPowerMax can be secret in
            -- group context and cannot feed SetMinMaxValues; UnitPowerPercent evaluates the secret
            -- C-side against ScaleTo100 and returns a clean 0-100.
            -- Type + color + bounds (+ power-colored bg) through the shared edge,
            -- which stamps d._pwType for the per-tick value path; forced so a
            -- settings-driven full paint always re-tints.
            mod._RFPowerTypeEdge(skinData, unitToken, true)
            local ppct = UnitPowerPercent(unitToken, pType, true, CurveConstants.ScaleTo100)
            if smoothPower then
                power:SetValue(ppct, smoothPower)
            else
                power:SetValue(ppct)
            end
            -- Power Text rides the same value (RF_TextPowerShow cleared the dead/offline
            -- stamp, so the next health tick re-checks a possibly new occupant).
            if skinData._pwtOn then mod.RF_TextPower(skinData, unitToken, ppct, pType, true) end
        end
    end
end

-- Roster-derived state only, for a button whose OCCUPANT did not change across a
-- roster event: leader/assist flag, assigned role (icon + role-gated power layout).
-- Everything else on the button is driven by its own unit events and was current
-- before the roster event, so the full paint (name resolution, absorb, texts,
-- marker, threat) is skipped.
mod._RefreshRosterState = function(btnFrame, skinData, s, unitToken)
    if not skinData.styled then return end
    mod._UpdateRoleIcon(skinData, s, unitToken)
    mod._UpdateLeaderIcon(skinData, s, unitToken)
    mod._PaintPower(btnFrame, skinData, s, unitToken)
    -- Custom texts showing [group]: the raid group can change with the occupant staying.
    local tp = skinData._txP
    if tp and tp.reads then mod.RF_TextRepaintCustom(skinData, unitToken, "roster") end
end

-- One button's share of the coalesced roster pass (both roster timers). A paint
-- stamped at or after the cycle's arm time came from the assignment hook (the
-- occupant changed) or a full pass inside the cycle: nothing left to do. A stable
-- occupant (same guid as the hook's last full paint) gets the roster-state refresh.
-- Anything else -- no painted occupant on record, secret guid -- takes the full
-- paint, exactly the old pass.
mod._RosterPassPaint = function(btnFrame, unitToken)
    local skinData = GetFFD(btnFrame)
    local armAt = mod._rosterArmAt
    if armAt and skinData._fpAt and skinData._fpAt >= armAt and skinData._fpUnit == unitToken then return end
    local unitGuid = skinData._lastGuid and UnitGUID(unitToken)
    if
        unitGuid
        and not issecretvalue(unitGuid)
        and skinData._lastGuid == unitGuid
        and skinData._lastUnit == unitToken
    then
        local s = skinData._isParty and mod._scaledPartyProxy
            or (skinData._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        mod._RefreshRosterState(btnFrame, skinData, s, unitToken)
    else
        UpdateButton(btnFrame)
    end
end

-- Second half of the full paint (after power + absorb).
mod._PaintButtonTail = function(btnFrame, skinData, cfg, unitToken)
    local CludesUI = mod.CludesUI -- upvalue read, not a global read (see the taint note at the top of CludesUIRaidFrames.lua)

    -- The texts (name, level, Health, Heal Absorb and Custom Text; Power Text is the
    -- power paint's). Health, Power and Heal Absorb Text blank while dead or offline (the
    -- status text shows DEAD/OFFLINE); Custom stays, its tags name the status.
    mod.RF_TextFull(skinData, cfg, unitToken)

    -- Top Name Bar text (unit name + class/custom color); size/anchor/visibility are LayoutTopNameBar's.
    -- It keeps the level in front of the name as the name does.
    if skinData.topNameBarText and cfg.topNameBarEnabled then
        local lvlAttach = mod.RF_TextNameAttach(cfg)
        if lvlAttach then
            mod._RFNameWithLevel(
                skinData.topNameBarText,
                ResolveDisplayName(unitToken, false, cfg),
                unitToken,
                lvlAttach
            )
        else
            skinData.topNameBarText:SetText(ResolveDisplayName(unitToken, false, cfg))
        end
        local tr, tg, tb = GetTopNameBarColor(unitToken, cfg)
        skinData.topNameBarText:SetTextColor(tr, tg, tb)
    end

    -- Status text (DEAD / OFFLINE / AFK). The SAME stamped painter as the
    -- UNIT_HEALTH path: the stamp records what is on screen, so a full paint
    -- that shows DEAD on a freshly assigned corpse leaves a stamp the later
    -- resurrect tick can see as a transition.
    mod._PaintStatusText(skinData, cfg, unitToken, UnitIsConnected(unitToken), UnitIsDeadOrGhost(unitToken))

    -- Role icon
    mod._UpdateRoleIcon(skinData, cfg, unitToken)

    -- Leader/assistant icon (honors the "Show In Combat" cog)
    mod._UpdateLeaderIcon(skinData, cfg, unitToken)

    -- Combat icon (members currently in combat)
    mod._UpdateCombatIcon(skinData, cfg, unitToken)

    -- Raid marker
    if skinData.raidMarker then
        if cfg.showRaidMarker then
            local position = GetRaidTargetIndex(unitToken)
            if position then
                if issecretvalue(position) then
                    -- Secret-safe path: use SetSpriteSheetCell for secret marker index
                    skinData.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    if skinData.raidMarker.SetSpriteSheetCell then
                        pcall(
                            skinData.raidMarker.SetSpriteSheetCell,
                            skinData.raidMarker,
                            position,
                            4,
                            4,
                            64,
                            64
                        )
                    end
                    skinData.raidMarker:Show()
                elseif RAID_MARKER_TEXCOORDS[position] then
                    local tc = RAID_MARKER_TEXCOORDS[position]
                    skinData.raidMarker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                    skinData.raidMarker:Show()
                else
                    skinData.raidMarker:Hide()
                end
            else
                skinData.raidMarker:Hide()
            end
        else
            skinData.raidMarker:Hide()
        end
    end

    -- Target state: recolor the single border ONLY on a real target transition (hover takes
    -- priority in ApplyBorderColor), keeping recolor + level work off the per-update hot path.
    -- Both operands are clean booleans, so the compare never touches a secret value.
    do
        local isTarget = UnitIsUnit(unitToken, "target")
        local newTarget = (not issecretvalue(isTarget) and isTarget) and true or false
        if newTarget ~= skinData._isTarget then
            skinData._isTarget = newTarget
            if skinData.ApplyBorderColor then skinData.ApplyBorderColor() end
        end
    end

    -- Threat highlight (aggro): the inner border (size 0 = off) or the Color Custom Borders recolor
    mod.RF_PaintThreat(skinData, cfg, unitToken)
end

-- UNIT_LEVEL: only the name and level texts repaint (and the Top Name Bar while it
-- shows the level); a button whose view shows no level is left alone.
mod._RFRepaintLevel = function(btnFrame)
    local unitToken = btnFrame:GetAttribute("unit")
    if not unitToken or not UnitExists(unitToken) then return end
    local skinData = GetFFD(btnFrame)
    local p = skinData._txP
    if not (skinData.styled and p and p.wantLevel) then return end
    mod.RF_TextNames(skinData, unitToken)
    local cfg = skinData._txS
    if p.nameAttach and skinData.topNameBarText and cfg.topNameBarEnabled then
        mod._RFNameWithLevel(
            skinData.topNameBarText,
            ResolveDisplayName(unitToken, false, cfg),
            unitToken,
            p.nameAttach
        )
    end
end

-------------------------------------------------------------------------------
--  Dispel detection (secret-value safe). Handles border, overlay
--  (fill/full/gradient), and type icon.
-------------------------------------------------------------------------------

-- "By Me" dispel selection: UpdateDispelBorder queries auras with the
-- "HARMFUL|RAID_PLAYER_DISPELLABLE" filter directly, so the engine returns only
-- player-dispellable auras. Never branch on a (possibly secret) auraInstanceID:
-- negating IsAuraFilteredOutByInstanceID on it is nondeterministic for secret
-- boss debuffs (intermittent highlight).

-- Scratch color reused for dispel overlays (avoids a per-call table alloc).
mod._dispelScratch = mod._dispelScratch or {}
mod._dispelScratchDark = mod._dispelScratchDark or {}

-- Build the dispel-type -> color curves from the user's custom colors.
-- GetAuraDispelTypeColor evaluates the curve against an aura's (secret) dispel type internally, so
-- we never read the secret dispelName/dispelType. Indices are the engine dispel-type enum: 1 Magic,
-- 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed (0 = none). Rebuilt every ReloadFrames.
function mod._RebuildDispelCurves()
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve) then return end
    local function build(profile, mult, alphaMult)
        local color = C_CurveUtil.CreateColorCurve()
        color:SetType(Enum.LuaCurveType.Step)
        local function add(position, key, dr, dg, saved)
            local colour = profile and profile[key]
            -- Per-type alpha rides the curve too (0 = type opted out of the dispel border/overlay). Never darkened by mult.
            color:AddPoint(
                position,
                CreateColor(
                    (colour and colour.r or dr) * mult,
                    (colour and colour.g or dg) * mult,
                    (colour and colour.b or saved) * mult,
                    ((colour and colour.a) or 1) * (alphaMult or 1)
                )
            )
        end
        add(0, "dispelColorMagic", 0.349, 0.475, 1.0) -- none: harmless default
        add(1, "dispelColorMagic", 0.349, 0.475, 1.0)
        add(2, "dispelColorCurse", 0.636, 0.0, 0.64)
        add(3, "dispelColorDisease", 0.671, 0.384, 0.098)
        add(4, "dispelColorPoison", 0.0, 0.706, 0.286)
        add(9, "dispelColorBleed", 0.75, 0.15, 0.15)
        add(11, "dispelColorBleed", 0.75, 0.15, 0.15)
        return color
    end
    -- Bright (full) curves + parallel 50%-darkened curves for the clock border's already-elapsed
    -- arc. Darkening applies to the user's CLEAN colors at build time, never a secret per-frame one.
    mod._dispelCurve = build(mod._scaledProfile, 1)
    mod._dispelCurveParty = build(mod._scaledPartyProxy, 1)
    mod._dispelCurveDark = build(mod._scaledProfile, 0.5)
    mod._dispelCurveDarkParty = build(mod._scaledPartyProxy, 0.5)
    -- Overlay curves: per-type alpha premultiplied by the overlay opacity HERE, on plain saved
    -- numbers. The evaluated per-frame alpha is SECRET and arithmetic on it is a hard error --
    -- it may only ever flow straight into setters.
    local rOp = ((mod._scaledProfile and mod._scaledProfile.dispelOverlayOpacity) or 100) / 100
    local pOp = ((mod._scaledPartyProxy and mod._scaledPartyProxy.dispelOverlayOpacity) or 100) / 100
    mod._dispelCurveOL = build(mod._scaledProfile, 1, rOp)
    mod._dispelCurveOLParty = build(mod._scaledPartyProxy, 1, pOp)
end

-------------------------------------------------------------------------------
--  Ready check handling
-------------------------------------------------------------------------------
local readyCheckActive = false
Inner.readyCheckActiveSetters[#Inner.readyCheckActiveSetters + 1] = function(val) readyCheckActive = val end

-- Incoming-rez indicator state. UnitHasIncomingResurrection covers only the CAST
-- window: it drops to false the moment the cast lands, while the target still has
-- the accept dialog up. ns._rezPend carries the unit across that edge: true while
-- a cast has been seen, then a GetTime() expiry latched when the flag falls on a
-- still-dead unit (the offer window). Cleared on accept (alive read), a fresh
-- cast, roster shifts (unit tokens move), or the 60s offer expiry. A cancelled
-- cast latches too -- the completion and cancel edges are indistinguishable
-- without a combat log; the alive-clear and expiry bound the miss.
mod._rezPend = {}

-- Shared predicate for the rez icon and the DEAD-text suppression at all paint
-- sites. Writes the casting mark itself so a cast already in flight at paint
-- time (login, roster reassignment) still latches when its completion edge fires.
-- PURE otherwise: it must NEVER clear the latch -- many painters call it (status
-- text, Extra Frames duplicates, full passes) and whichever read first would
-- consume the entry before the icon's own repaint, stranding the icon shown.
-- Clearing belongs to the owners: the INCOMING edges, the UNIT_HEALTH alive
-- edge, the expiry timer, and the roster wipe -- each repaints what it clears.
mod._RFRezShown = function(unitToken)
    if UnitHasIncomingResurrection(unitToken) then
        mod._rezPend[unitToken] = true
        return true
    end
    local exp = mod._rezPend[unitToken]
    if type(exp) ~= "number" then return false end
    if GetTime() >= exp or not UnitIsDeadOrGhost(unitToken) then return false end
    return true
end

-- d.readyCheck is shared by the ready-check, incoming-summon and incoming-rez indicators (rez only
-- on dead units). Priority: active ready check > pending summon > incoming rez.
local function UpdateReadyCheck(btnFrame, unitToken)
    local skinData = GetFFD(btnFrame)
    local texture = skinData.readyCheck
    if not texture then return end

    -- Party/extra-aware settings source, same as every other indicator updater.
    -- AnchorReadyCheck already resolves LIVE this way, so a raw db.profile read
    -- here re-sized the shared texture back to the RAID value on every paint.
    local cfg = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile

    local sz = PixelSnap(cfg.readyCheckSize or 20)
    texture:SetSize(sz, sz)

    -- Ready check (priority)
    if cfg.showReadyCheck and readyCheckActive then
        local status = GetReadyCheckStatus(unitToken)
        if status == "ready" then
            texture:SetAtlas("UI-LFG-ReadyMark-Raid")
            texture:Show()
            return
        elseif status == "notready" then
            texture:SetAtlas("UI-LFG-DeclineMark-Raid")
            texture:Show()
            return
        elseif status == "waiting" then
            texture:SetAtlas("UI-LFG-PendingMark-Raid")
            texture:Show()
            return
        end
    end

    -- Incoming summon
    if cfg.showSummonPending and unitToken and C_IncomingSummon.HasIncomingSummon(unitToken) then
        local sStatus = C_IncomingSummon.IncomingSummonStatus(unitToken)
        if sStatus == SUMMON_STATUS_PENDING then
            texture:SetAtlas("RaidFrame-Icon-SummonPending")
            texture:Show()
            return
        elseif sStatus == SUMMON_STATUS_ACCEPTED then
            texture:SetAtlas("RaidFrame-Icon-SummonAccepted")
            texture:Show()
            return
        elseif sStatus == SUMMON_STATUS_DECLINED then
            texture:SetAtlas("RaidFrame-Icon-SummonDeclined")
            texture:Show()
            return
        end
    end

    -- Incoming resurrection (cast in flight, or the latched unaccepted-offer window
    -- -- see ns._RFRezShown). Lowest priority; shows a body is already being picked up.
    if cfg.showIncomingRez and unitToken and mod._RFRezShown(unitToken) then
        texture:SetAtlas("RaidFrame-Icon-Rez")
        texture:Show()
        return
    end

    texture:Hide()
end

-------------------------------------------------------------------------------
--  Unit-to-button mapping
-------------------------------------------------------------------------------
local function RebuildUnitMap()
    wipe(unitToButton)
    for _, button in ipairs(allButtons) do
        if button:IsVisible() then
            local u = button:GetAttribute("unit")
            if u then
                local skinData = GetFFD(button)
                -- Extra Frames duplicates stay out of the routing map (one button per unit; the
                -- real frame owns the slot). Everything else here applies to them.
                if not skinData._isExtra then unitToButton[u] = button end
                -- Cache class token for power border (avoids UnitClass in hot path)
                local _, classToken = UnitClass(u)
                skinData.classToken = classToken
                -- Repair a container binding the OnAttributeChanged hook dropped because
                -- UnitExists(u) was false at the moment the header assigned it (roster still
                -- streaming in on a zone/group transition). Nothing else re-drives this once
                -- the header stops re-asserting the same token, so aura containers can stay
                -- bound to a stale unit indefinitely.
                if skinData.rfcUnit ~= u and UnitExists(u) and mod.RFC_OnUnitAssigned then
                    mod.RFC_OnUnitAssigned(button, skinData, u)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Full update for all visible buttons
-------------------------------------------------------------------------------
-- Full-pass paint stamp. The login/zone window runs several IDENTICAL full passes in one frame
-- (assignment paints, the OnEnable reload pass, the visibility rebuild + follow-up). Each full-pass
-- paint stamps the button with (frame time, unit, paint gen); a later identical-body pass in the
-- same frame skips stamped buttons -- same frame + unit + gen reads the same state, so the skipped
-- repaint is provably the same pixels. Targeted event repaints (health, aura singles) neither check
-- nor set the stamp. The gen breaks the window whenever paint INPUTS change mid-frame: settings
-- writes (_BumpAbsorbGen), profile swaps (_CURF_RefreshAll) and cross-module pushes (UpdateAllFrames).
mod._paintGen = 0
local function UpdateAllButtons()
    local nowTime, gen = GetTime(), mod._paintGen
    for _, button in ipairs(allButtons) do
        local u = button:GetAttribute("unit")
        if u and button:IsVisible() then
            local skinData = GetFFD(button)
            if not (skinData._fpAt == nowTime and skinData._fpUnit == u and skinData._fpGen == gen) then
                skinData._fpAt = nowTime
                skinData._fpUnit = u
                skinData._fpGen = gen
                UpdateButton(button)
                UpdateReadyCheck(button, u)
            end
        end
    end
end

-- Full per-button refresh for a freshly (re)assigned unit; mirrors the per-button work in
-- UpdateAllButtons. On ns so the OnAttributeChanged("unit") watch in StyleButton (created before
-- these locals exist) can repaint the instant the secure header assigns a unit.
mod._RefreshAssignedButton = function(btnFrame, unitToken)
    local skinData = GetFFD(btnFrame)
    if not skinData.styled then return end -- not built yet; init paint handles it
    -- Same stamp as UpdateAllButtons (identical body): the assignment paint and a same-frame full pass collapse to one paint.
    local nowTime = GetTime()
    if skinData._fpAt == nowTime and skinData._fpUnit == unitToken and skinData._fpGen == mod._paintGen then
        return
    end
    skinData._fpAt = nowTime
    skinData._fpUnit = unitToken
    skinData._fpGen = mod._paintGen
    UpdateButton(btnFrame)
    UpdateReadyCheck(btnFrame, unitToken)
end

function ERF:UpdateAllFrames()
    -- Cross-module pushes (Dark Mode master, accent) change paint inputs outside the RF options
    -- funnel: break the same-frame paint-stamp window.
    mod._paintGen = (mod._paintGen or 0) + 1
    -- Textured Background layers first (a Dark Mode Fill edit can cross 100 with no
    -- reload): the repaints below paint them.
    mod.RF_TexBgRecheck()
    UpdateAllButtons()
    -- Party and Boss frames are NOT in `allButtons` (Extra frames ARE, see XF.EnsureBuilt), so
    -- repaint their health too, or Dark Mode / color pushes (ApplyColorsToOUF) miss those frame
    -- types. _UpdateButtonHealth is lightweight, combat-safe and self-guarding.
    if mod._UpdateButtonHealth then
        if mod._partyUnitToButton then
            for u, button in pairs(mod._partyUnitToButton) do
                mod._UpdateButtonHealth(button)
                -- Power Text's accent/power colour moves with these pushes too (raid and extra
                -- buttons take it from the full paint above): one field read while it is off.
                local pd = GetFFD(button)
                if pd._pwtOn then mod.RF_TextPowerColor(pd, u, mod._scaledPartyProxy, GetPowerColor(u)) end
            end
        end
        if mod._xfUnitToButton then
            for _, button in pairs(mod._xfUnitToButton) do
                mod._UpdateButtonHealth(button)
            end
        end
    end
    -- Boss and pet frames paint through their own painter (names and their colours included).
    local FB = mod._FB
    for _, button in ipairs(FB.buttons) do
        if button:IsVisible() then FB.Update(button) end
    end
    mod._PF_RefreshVisible()
    -- Party target frames: their fill and background read the Dark Mode and class palettes too.
    mod._PT_RepaintVisible()
end

-- A Number Format change repaints every text. Party buttons take only a health
-- paint above, so they get the full one here for their absorb texts.
mod.CludesUI.RegisterNumberFormatCallback(function()
    ERF:UpdateAllFrames()
    if mod._partyPvActive then return end
    for _, btn in ipairs(mod._partyAllButtons) do
        if btn:GetAttribute("unit") and btn:IsVisible() then UpdateButton(btn) end
    end
end)

-- Lightweight: only toggle raid markers on each button (for RAID_TARGET_UPDATE)
mod._UpdateRaidMarkers = function()
    local function updateMarker(unitToken, button)
        local skinData = GetFFD(button)
        local cfg = skinData._isParty and mod._scaledPartyProxy
            or (skinData._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        if not cfg.showRaidMarker then
            if skinData.raidMarker then skinData.raidMarker:Hide() end
            return
        end
        if skinData.raidMarker then
            local position = GetRaidTargetIndex(unitToken)
            if position then
                if issecretvalue(position) then
                    skinData.raidMarker:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                    if skinData.raidMarker.SetSpriteSheetCell then
                        pcall(
                            skinData.raidMarker.SetSpriteSheetCell,
                            skinData.raidMarker,
                            position,
                            4,
                            4,
                            64,
                            64
                        )
                    end
                    skinData.raidMarker:Show()
                elseif RAID_MARKER_TEXCOORDS[position] then
                    local tc = RAID_MARKER_TEXCOORDS[position]
                    skinData.raidMarker:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
                    skinData.raidMarker:Show()
                else
                    skinData.raidMarker:Hide()
                end
            else
                skinData.raidMarker:Hide()
            end
        end
    end
    for unitToken, button in pairs(unitToButton) do
        updateMarker(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        updateMarker(unitToken, button)
    end
    for unitToken, button in pairs(mod._xfUnitToButton) do
        updateMarker(unitToken, button)
    end
end

-- Lightweight: only toggle target border on each button (for PLAYER_TARGET_CHANGED)
mod._UpdateTargetBorders = function()
    local function updateTarget(unitToken, button)
        local skinData = GetFFD(button)
        local isTarget = UnitIsUnit(unitToken, "target")
        skinData._isTarget = (not issecretvalue(isTarget) and isTarget) and true or false
        if skinData.ApplyBorderColor then skinData.ApplyBorderColor() end
    end
    for unitToken, button in pairs(unitToButton) do
        updateTarget(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        updateTarget(unitToken, button)
    end
    for unitToken, button in pairs(mod._xfUnitToButton) do
        updateTarget(unitToken, button)
    end
end

-- Lightweight: role icons only. Driven by combat transitions so the "Hide In Combat" cog
-- suppresses/restores without a full repaint. Texture Show/Hide is combat-legal.
mod._UpdateRoleIcons = function()
    local function updateRole(unitToken, button)
        local skinData = GetFFD(button)
        if not skinData.roleIcon then return end
        local s = skinData._isParty and mod._scaledPartyProxy
            or (skinData._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        mod._UpdateRoleIcon(skinData, s, unitToken)
    end
    for unitToken, button in pairs(unitToButton) do
        updateRole(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        updateRole(unitToken, button)
    end
    for unitToken, button in pairs(mod._xfUnitToButton) do
        updateRole(unitToken, button)
    end
end

-- Lightweight: refresh leader/assistant icons only (combat transitions; "Show
-- In Combat" cog) without a full repaint. Texture Show/Hide is combat-legal.
mod._UpdateLeaderIcons = function()
    local function updateLeader(unitToken, button)
        local skinData = GetFFD(button)
        if not skinData.leaderIcon then return end
        local s = skinData._isParty and mod._scaledPartyProxy
            or (skinData._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        mod._UpdateLeaderIcon(skinData, s, unitToken)
    end
    for unitToken, button in pairs(unitToButton) do
        updateLeader(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        updateLeader(unitToken, button)
    end
    for unitToken, button in pairs(mod._xfUnitToButton) do
        updateLeader(unitToken, button)
    end
end

-- Lightweight: refresh combat icons only (UNIT_FLAGS flips + combat
-- transitions). Texture Show/Hide is combat-legal, safe from PLAYER_REGEN_DISABLED.
mod._UpdateCombatIcons = function()
    local function updateCombat(unitToken, button)
        local skinData = GetFFD(button)
        if not skinData.combatIcon then return end
        local s = skinData._isParty and mod._scaledPartyProxy
            or (skinData._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        mod._UpdateCombatIcon(skinData, s, unitToken)
    end
    for unitToken, button in pairs(unitToButton) do
        updateCombat(unitToken, button)
    end
    for unitToken, button in pairs(mod._partyUnitToButton) do
        updateCombat(unitToken, button)
    end
    for unitToken, button in pairs(mod._xfUnitToButton) do
        updateCombat(unitToken, button)
    end
end

-- Single-unit combat icon refresh for UNIT_FLAGS routing (raid + party).
mod._UpdateCombatIconFor = function(unitToken, button)
    local skinData = GetFFD(button)
    if not skinData.combatIcon then return end
    local s = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile
    mod._UpdateCombatIcon(skinData, s, unitToken)
end

-- True when the combat icon is enabled anywhere (raid or effective party); skips all combat-icon work while off.
mod._CombatIconEnabled = function()
    if not (saved and saved.profile) then return false end
    if saved.profile.showCombatIndicator then return true end
    if mod._partyProxy.showCombatIndicator then return true end
    return false
end

-- Register UNIT_FLAGS on the per-unit trackers ONLY while the combat icon is enabled (raid key;
-- party effective key): off = no tracker listens, zero event code for a disabled feature. Event
-- (un)registration is combat-legal. Extra Frames trackers gate separately in XF_Apply. Called
-- from ReloadFrames and once after the trackers are built.
mod.UpdateCombatEventRegistration = function()
    if not (saved and saved.profile) then return end
    local raidWant = saved.profile.showCombatIndicator and true or false
    local partyWant = mod._partyProxy.showCombatIndicator and true or false
    for unitToken, tracker in pairs(unitTrackers) do
        local wanted
        if unitToken == "player" then
            wanted = raidWant or partyWant
        elseif unitToken:find("^party%d") then
            wanted = partyWant
        else
            wanted = raidWant
        end
        if wanted then
            tracker:RegisterUnitEvent("UNIT_FLAGS", unitToken)
        else
            tracker:UnregisterEvent("UNIT_FLAGS")
        end
    end
end

-- Lightweight health-only update for UNIT_HEALTH / UNIT_MAXHEALTH. Skips power/name/role/leader/marker/target/threat -- each has its own event path.
-- Status text (DEAD / OFFLINE / AFK), the ONE painter for both the full paint and
-- the UNIT_HEALTH path. State + color stamped: text/color/visibility re-apply
-- only on a real transition (0 hidden, 1 offline, 2 dead, 3 AFK); the stamp is
-- the on-screen state, so it stays valid across occupants and across the two
-- paths. The rez check runs only for dead units: a live unit can never carry an
-- incoming resurrection (the offer latch also requires dead), so the C probe is
-- skipped for the alive majority -- the same shape as Blizzard's
-- CompactUnitFrame, which never probes rez from its UNIT_HEALTH path.
mod._PaintStatusText = function(skinData, cfg, unitToken, connected, deadOrGhost)
    local statusText = skinData.statusText
    if not statusText then return end
    local stc = cfg.statusTextColor or { r = 1, g = 1, b = 1 }
    local st
    if cfg.statusTextPosition == "none" then
        st = 0
    elseif deadOrGhost and cfg.showIncomingRez and mod._RFRezShown(unitToken) then
        -- Being resurrected: hide the status text so the incoming-rez icon isn't covered.
        st = 0
    elseif not connected then
        st = 1
    elseif deadOrGhost then
        st = 2
    else
        local afk
        if cfg.statusShowAFK and UnitIsAFK then
            afk = UnitIsAFK(unitToken)
            if issecretvalue(afk) then afk = nil end
        end
        st = afk and 3 or 0
    end
    if skinData._stSt ~= st or skinData._stR ~= stc.r or skinData._stG ~= stc.g or skinData._stB ~= stc.b then
        skinData._stSt, skinData._stR, skinData._stG, skinData._stB = st, stc.r, stc.g, stc.b
        if st == 0 then
            statusText:Hide()
        else
            local L = mod.CludesUI.L
            statusText:SetText(st == 1 and L("OFFLINE") or st == 2 and L("DEAD") or L("AFK"))
            statusText:SetTextColor(stc.r, stc.g, stc.b)
            statusText:Show()
        end
    end
end

mod._UpdateButtonHealth = function(btnFrame, unitToken)
    -- Dispatchers pass the event's unit token (a unit that just fired an event
    -- exists -- no probe); rare callers omit it and pay the existence check.
    if not unitToken then
        unitToken = btnFrame:GetAttribute("unit")
        if not unitToken or not UnitExists(unitToken) then return end
    end
    local skinData = GetFFD(btnFrame)
    if not skinData.styled then return end
    local cfg = skinData._isParty and mod._scaledPartyProxy
        or (skinData._isExtra and mod._scaledExtraProxy)
        or mod._scaledProfile

    local health = skinData.health
    local pct = GetSafeHealthPercent(unitToken)
    local connected = UnitIsConnected(unitToken)
    local deadOrGhost = UnitIsDeadOrGhost(unitToken)

    -- Health bar
    if health then
        -- The bar is always a percent bar; its range never changes after the
        -- first application.
        if not skinData._hb100 then
            skinData._hb100 = true
            health:SetMinMaxValues(0, 100)
        end
        local smooth = cfg.smoothBars
            and Enum
            and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
        -- Missing health under Inverted Fill, every unit (see UpdateButton).
        local barPct = pct
        if health._cuiInv then barPct = deadOrGhost and 100 or GetSafeHealthPercent(unitToken, true) end
        if smooth then
            health:SetValue(barPct, smooth)
        else
            health:SetValue(barPct)
        end
        -- Fill color: dead/offline ticks skip this entirely (_ApplyHealthBg
        -- owns the gray tint and clears the stamp on the transition). The
        -- curve modes recolor with health, so they apply every tick; static
        -- modes stamp the applied color and re-run only on a real change
        -- (every static-mode component is a plain value by construction).
        if connected and not deadOrGhost then
            local mode = cfg.healthColorMode
            local red, green, blue
            if mode == nil or mode == "class" then
                -- Class color is identity, not health: resolve the class token
                -- once per occupant and reuse it per tick. Cleared on unit
                -- assignment, UNIT_NAME_UPDATE and UNIT_CONNECTION -- the edges
                -- Blizzard's CompactUnitFrame recolors on -- so it can never
                -- outlive the person behind the token. A secret token (identity
                -- restricted) is never cached: fail open to the per-tick read
                -- and the neutral gray, exactly as before.
                local tok = skinData._clsTok
                if not tok then
                    local _, classTok = UnitClass(unitToken)
                    if classTok and not issecretvalue(classTok) then
                        tok = classTok
                        skinData._clsTok = classTok
                    end
                end
                local cc = tok and mod.CludesUI.GetClassColor(tok)
                if cc then
                    red, green, blue = cc.r, cc.g, cc.b
                else
                    red, green, blue = 0.5, 0.5, 0.5
                end
            else
                red, green, blue = GetHealthColor(unitToken, cfg)
            end
            if mode == "classic" or mode == "customDynamic" or mode == "classReactive" then
                local fillTex = health:GetStatusBarTexture()
                if fillTex then fillTex:SetAlpha(1) end
                health:SetStatusBarColor(red, green, blue, (cfg.healthBarOpacity or 100) / 100)
            else
                local a = (mode == "dark") and 1 or (cfg.healthBarOpacity or 100) / 100
                if
                    skinData._hcR ~= red
                    or skinData._hcG ~= green
                    or skinData._hcB ~= blue
                    or skinData._hcA ~= a
                    or skinData._hcM ~= mode
                then
                    skinData._hcR, skinData._hcG, skinData._hcB, skinData._hcA, skinData._hcM =
                        red, green, blue, a, mode
                    local fillTex = health:GetStatusBarTexture()
                    if mode == "dark" then
                        health:SetStatusBarColor(red, green, blue, 1)
                        -- 4th return of GetDarkModeFill() is the Dark Mode Fill Opacity.
                        if fillTex then fillTex:SetAlpha(select(4, CludesUI.GetDarkModeFill())) end
                    else
                        if fillTex then fillTex:SetAlpha(1) end
                        health:SetStatusBarColor(red, green, blue, a)
                    end
                end
            end
        end
    end

    -- The texts: Health and Heal Absorb Text, Power Text's dead/offline edge (death
    -- and resurrection need not move a power value) and the Custom texts reading health.
    -- One field read while the button's texts have none of them.
    local tp = skinData._txP
    if tp and tp.tick then mod.RF_TextHealth(skinData, unitToken, pct, deadOrGhost or not connected) end

    -- Status text (dead/ghost state changes with health)
    mod._PaintStatusText(skinData, cfg, unitToken, connected, deadOrGhost)

    -- Background + dead/offline tint. This path owns death/resurrect transitions
    -- arriving via UNIT_HEALTH, so it runs per tick (state-stamped inside).
    mod._ApplyHealthBg(skinData, health, cfg, unitToken, connected, deadOrGhost)

    -- Debuff Manager dead-corpse swap rides the same ownership: one field read
    -- for every button without a qualifying config.
    if skinData.dmDeadSwap then mod.DM_DeadEdge(skinData, unitToken) end
end

-- Two-step max-health landing (max first, value after): one next-frame re-read
-- settles torn numbers; the flag collapses a raid-wide change to one pass per
-- button (canonical story: UF engine RESETTLE_EVENTS). Flag lives in FFD --
-- header children never carry insecure keys.
mod._ResettleButtonHealth = function(btnFrame)
    local skinData = GetFFD(btnFrame)
    if skinData.hpResettle then return end
    skinData.hpResettle = true
    C_Timer.After(0, function()
        skinData.hpResettle = nil
        if btnFrame:IsVisible() then mod._UpdateButtonHealth(btnFrame) end
    end)
end

Inner.RebuildUnitMap, Inner.UpdateAllButtons = RebuildUnitMap, UpdateAllButtons
Inner.UpdateButton, Inner.UpdateReadyCheck = UpdateButton, UpdateReadyCheck
Inner.broken = false
