if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Nameplates_CastState.lua
--
--  Non-target opacity, the hover effect, the kick watcher, cast notifications
--  and the aura CVars.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs, type = pairs, type
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
local UnitAffectingCombat = UnitAffectingCombat
local C_NamePlate = C_NamePlate
local NamePlateConstants, Enum = NamePlateConstants, Enum

local defaultSet, GetHealthBarWidth = Inner.defaults, Inner.GetHealthBarWidth
local ApplyOverlayGeometry, OverlayBgAlpha = Inner.ApplyOverlayGeometry, Inner.OverlayBgAlpha
local GetActiveKickSpell = Inner.GetActiveKickSpell

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val) p = val end

-------------------------------------------------------------------------------
--  Non-Target Opacity: while the player has a target, every skinned plate that is not the
--  target, focus or player fades to nonTargetAlpha (0-100). 100 = OFF: every hook below
--  reduces to one numeric compare. Out-of-range alpha composes into the same root multiplier.
--  Alpha rides the plate ROOT (our own frame, parented to the Blizzard nameplate), so
--  Blizzard's own occlusion fade still multiplies in.
-------------------------------------------------------------------------------
mod._ntAlpha = 1 -- cached 0..1 from the profile; 1 = inert
mod._ntKeepFocus = true -- cached "Keep Focus Full Opacity" (default on)
mod._oorAlpha = 1 -- cached out-of-range alpha; 1 = inert
-- Out of Combat Opacity: plates of mobs not in combat fade to outOfCombatAlpha (0-100).
-- 100 = OFF. Target and kept focus are exempt.
mod._oocAlpha = 1
-- Full Opacity While Casting: a casting plate skips the Non-Target fade (Out of Combat and
-- out-of-range still apply). Important-only gates it on the cast's possibly SECRET important flag.
mod._ntCastFull = false
mod._ntCastImportantOnly = false

-- Applies the correct root alpha to ONE plate. Value-guarded via _ntCurAlpha so redundant
-- SetAlpha calls are skipped and pooled frames reset cheaply (nil = never faded).
function mod.NT_Apply(backing)
    local unitToken = backing.unit
    if not unitToken then return end
    local a = 1
    local nt = mod._ntAlpha
    if
        nt < 1
        and UnitExists("target")
        and not UnitIsUnit(unitToken, "target")
        and not (mod._ntKeepFocus and UnitIsUnit(unitToken, "focus"))
        and not UnitIsUnit(unitToken, "player")
    then
        a = nt
    end
    -- Out of Combat and out-of-range fades, which casting never lifts.
    local rest = backing._oorCurAlpha or 1
    local ooc = mod._oocAlpha
    if
        ooc < 1
        and not UnitAffectingCombat(unitToken)
        and not UnitIsUnit(unitToken, "target")
        and not (mod._ntKeepFocus and UnitIsUnit(unitToken, "focus"))
    then
        rest = rest * ooc
    end
    if a < 1 and mod._ntCastFull and mod._castingPlates[backing] then
        if mod._ntCastImportantOnly then
            -- The flag may be SECRET, so the write is change-checked on its numeric
            -- inputs; NotifyCastStarted drops them when a new cast brings a new flag.
            local lo = a * rest
            if backing._ntCurAlpha ~= -1 or backing._ntBoolHi ~= rest or backing._ntBoolLo ~= lo then
                local imp = backing._castImportant
                if type(imp) == "nil" then imp = false end
                -- Never a plain number: the next numeric apply always writes.
                backing._ntCurAlpha = -1
                backing._ntBoolHi, backing._ntBoolLo = rest, lo
                -- A SECRET flag makes the plate root's alpha secret for the session: never
                -- compare its GetAlpha() or a child's GetEffectiveAlpha().
                backing:SetAlphaFromBoolean(imp, rest, lo)
            end
            return
        end
        a = 1
    end
    a = a * rest
    if (backing._ntCurAlpha or 1) ~= a then
        backing._ntCurAlpha = a
        backing:SetAlpha(a)
    end
end

function mod.NT_ApplyAll()
    for _, backing in pairs(mod.plates) do
        mod.NT_Apply(backing)
    end
end

-- Re-derives the cached opacity from the profile and reapplies every plate (un-fades at
-- slider=100). Called from the options slider, OnInitialize, and RefreshAllSettings.
function mod.NT_RefreshSetting()
    local val = tonumber(p and p.nonTargetAlpha) or 100
    if val < 0 then
        val = 0
    elseif val > 100 then
        val = 100
    end
    mod._ntAlpha = val / 100
    mod._ntKeepFocus = not (p and p.nonTargetKeepFocus == false)
    mod._ntCastFull = (p and p.nonTargetCastFull) == true
    mod._ntCastImportantOnly = (p and p.nonTargetCastImportantOnly) == true
    local wasOn = mod._oocAlpha < 1
    val = tonumber(p and p.outOfCombatAlpha) or 100
    if val < 0 then
        val = 0
    elseif val > 100 then
        val = 100
    end
    mod._oocAlpha = val / 100
    local enabled = mod._oocAlpha < 1
    if enabled ~= wasOn then
        for _, backing in pairs(mod.plates) do
            if not enabled then
                backing:UnregisterEvent("UNIT_FLAGS")
            elseif backing.unit then
                backing:RegisterUnitEvent("UNIT_FLAGS", backing.unit)
            end
        end
    end
    mod.NT_ApplyAll()
end

function mod.HideHoverEffect(backing)
    if not backing then return end
    if backing.highlight then backing.highlight:Hide() end
    if backing.hoverClipFill then backing.hoverClipFill:Hide() end
    if backing.hoverClipBg then backing.hoverClipBg:Hide() end
    backing._ovHoverShown = nil
end

function mod.ShowHoverEffect(backing)
    if not backing or not backing.health then return end
    -- Highlight channel gate (the Hover Effect dropdown's Highlight box): off
    -- = both the flat wash and the Hover Texture overlay stay hidden; the
    -- extra channels render independently via ns.ApplyHoverExtras.
    if not mod.GetHoverGlowHighlight() then
        mod.HideHoverEffect(backing)
        return
    end
    local db2 = p or defaultSet
    local hoverTex = db2.hoverOverlayTexture or defaultSet.hoverOverlayTexture
    local hc = db2.hoverColor or defaultSet.hoverColor
    local ha = db2.hoverAlpha or defaultSet.hoverAlpha
    if hoverTex ~= "none" then
        if mod._hoverOverlayTexName ~= hoverTex then
            mod._hoverOverlayTexName = hoverTex
            mod._hoverOverlayTexPath = mod.ResolveOverlayTexPath(hoverTex)
        end
        local texPath = mod._hoverOverlayTexPath
        local bgAlpha = OverlayBgAlpha(db2.hoverOverlayFullBgAlpha, ha)
        mod.EnsureHoverOverlay(backing)
        if
            not backing._ovHoverShown
            or backing._ovHoverTex ~= texPath
            or backing._ovHoverAlpha ~= ha
            or backing._ovHoverBgAlpha ~= bgAlpha
            or backing._ovHoverR ~= hc.r
            or backing._ovHoverG ~= hc.g
            or backing._ovHoverB ~= hc.b
        then
            backing._ovHoverShown = true
            backing._ovHoverTex, backing._ovHoverAlpha = texPath, ha
            backing._ovHoverBgAlpha = bgAlpha
            backing._ovHoverR, backing._ovHoverG, backing._ovHoverB = hc.r, hc.g, hc.b
            ApplyOverlayGeometry(
                backing.hoverOverlayFill,
                backing.hoverOverlayBg,
                backing.health,
                mod.OVERLAY_STRIPE_KEYS[hoverTex] == true
            )
            backing.hoverOverlayFill:SetTexture(texPath)
            backing.hoverOverlayFill:SetAlpha(ha)
            backing.hoverOverlayFill:SetVertexColor(hc.r, hc.g, hc.b)
            backing.hoverOverlayBg:SetTexture(texPath)
            backing.hoverOverlayBg:SetAlpha(bgAlpha)
            backing.hoverOverlayBg:SetVertexColor(hc.r, hc.g, hc.b)
        end
        if backing.highlight then backing.highlight:Hide() end
        backing.hoverClipFill:Show()
        backing.hoverClipBg:Show()
        return
    end
    if backing.hoverClipFill then backing.hoverClipFill:Hide() end
    if backing.hoverClipBg then backing.hoverClipBg:Hide() end
    backing._ovHoverShown = nil
    if backing.highlight then
        backing.highlight:SetColorTexture(hc.r, hc.g, hc.b, ha)
        backing.highlight:Show()
    end
end

-- Recolor the mouseover highlight on every live plate (enemy + friendly).
function mod.RefreshHoverEffect()
    local color = (p and p.hoverColor) or defaultSet.hoverColor
    local a = (p and p.hoverAlpha) or defaultSet.hoverAlpha
    for _, backing in pairs(mod.plates) do
        if backing.highlight then backing.highlight:SetColorTexture(color.r, color.g, color.b, a) end
        if backing == mod._currentMouseoverPlate then
            mod.ShowHoverEffect(backing)
            mod.ApplyHoverExtras(backing)
        else
            mod.HideHoverEffect(backing)
            mod.ClearHoverExtras(backing)
        end
    end
    for _, backing in pairs(mod.friendlyPlates or {}) do
        if backing.highlight then backing.highlight:SetColorTexture(color.r, color.g, color.b, a) end
        if backing == mod._currentMouseoverPlate then
            mod.ShowHoverEffect(backing)
            mod.ApplyHoverExtras(backing)
        else
            mod.HideHoverEffect(backing)
            mod.ClearHoverExtras(backing)
        end
    end
end

local kickWatcher = CreateFrame("Frame")
kickWatcher:Hide()
local activeCastCount = 0
-- PERF: set of plates currently casting, so kick/color updates iterate only the
-- 1-3 casting plates instead of all 20+ in the scene. On ns (200-local pressure).
mod._castingPlates = {}
-- SPELL_UPDATE_COOLDOWN and SPELL_UPDATE_USABLE (the only events this frame
-- holds) usually arrive together, and again for every spell the GCD touches:
-- each only shows the frame, and its next OnUpdate makes ONE pass for them all.
kickWatcher:SetScript("OnEvent", function(self) self:Show() end)
kickWatcher:SetScript("OnUpdate", function(self)
    self:Hide()
    -- No per-event cast-info re-reads or geometry: cast identity (protection/channel
    -- flags) is cached by UpdateKickTick at setup and by INTERRUPTIBLE handlers on
    -- mid-cast flips, so cooldown events only refresh marker value + alpha. A hidden tick
    -- means re-setup from cache (kick learned mid-cast, late CD info, toggle on).
    for backing in pairs(mod._castingPlates) do
        if backing.isCasting and backing.unit and type(backing._kickProtected) ~= "nil" then
            backing:ApplyCastColor(backing._kickProtected)
            if not backing.kickPositioner:IsShown() then
                backing:UpdateKickTick(
                    backing._kickProtected,
                    backing._kickIsChannel,
                    backing._kickIsEmpowered
                )
            else
                backing:RefreshKickTick()
            end
        end
    end
end)
local _castColorTicker
local function NotifyCastStarted(backing)
    if backing then
        mod._castingPlates[backing] = true
        if mod._ntCastFull and mod._ntAlpha < 1 then
            backing._ntBoolHi = nil
            mod.NT_Apply(backing)
        end
        -- Arm the 10Hz cast-timer ticker (engine-slept between fires; self-stops at cast end)
        -- and paint ONCE synchronously, or the ticker's first fire alone leaves text blank 0.1s.
        if backing.cast and backing.cast._timerTicker then
            if backing.cast._timerTick then backing.cast._timerTick(true) end
            backing.cast._timerTicker.Start()
        end
    end
    activeCastCount = activeCastCount + 1
    if activeCastCount == 1 then
        kickWatcher:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:RegisterEvent("SPELL_UPDATE_USABLE")
        if GetActiveKickSpell() and not _castColorTicker then
            _castColorTicker = C_Timer.NewTicker(0.2, function()
                for pl in pairs(mod._castingPlates) do
                    -- type() is the safe existence check: _kickProtected holds a possibly-SECRET
                    -- boolean, and == nil would evaluate it
                    if pl.isCasting and pl.unit and type(pl._kickProtected) ~= "nil" then
                        pl:ApplyCastColor(pl._kickProtected)
                    end
                end
            end)
        end
    end
end
local function NotifyCastEnded(backing)
    if backing then
        mod._castingPlates[backing] = nil
        if mod._ntCastFull and mod._ntAlpha < 1 then mod.NT_Apply(backing) end
    end
    activeCastCount = activeCastCount - 1
    if activeCastCount <= 0 then
        activeCastCount = 0
        wipe(mod._castingPlates)
        kickWatcher:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        kickWatcher:UnregisterEvent("SPELL_UPDATE_USABLE")
        kickWatcher:Hide()
        if _castColorTicker then
            _castColorTicker:Cancel()
            _castColorTicker = nil
        end
    end
end

-- PERF: cached target/focus plate refs, so a target/focus change updates only
-- the old + new plate instead of iterating all. On ns (200-local pressure).
mod._cachedTargetPlate = nil
mod._cachedFocusPlate = nil

-- Value (1/0) of the class-colour CVar for the friendly player names Blizzard draws.
-- Name-only mode follows Class Colored Health Bar (its White / Class swatches). In
-- full-plate mode Blizzard draws only the protected instance plates, and Class
-- Colored Names turns it on as well so those names match ours.
function mod.FriendlyNameClassCVar(saved)
    local enabled = saved.classColorFriendly ~= false
        or (saved.friendlyNameOnly == false and saved.friendlyNameClassColor == true)
    return enabled and 1 or 0
end

local function SetupAuraCVars()
    if NamePlateConstants and Enum then
        local npcCVar = NamePlateConstants.ENEMY_NPC_AURA_DISPLAY_CVAR
        local npcEnum = Enum.NamePlateEnemyNpcAuraDisplay
        if npcCVar and npcEnum then
            if npcEnum.Debuffs then
                CUI.SetCVarBitfield(npcCVar, npcEnum.Debuffs, true, "CludesUINameplates")
            end
            if npcEnum.CrowdControl then
                CUI.SetCVarBitfield(npcCVar, npcEnum.CrowdControl, true, "CludesUINameplates")
            end
        end
        local plyCVar = NamePlateConstants.ENEMY_PLAYER_AURA_DISPLAY_CVAR
        local plyEnum = Enum.NamePlateEnemyPlayerAuraDisplay
        if plyCVar and plyEnum then
            if plyEnum.Debuffs then
                CUI.SetCVarBitfield(plyCVar, plyEnum.Debuffs, true, "CludesUINameplates")
            end
            if plyEnum.LossOfControl then
                CUI.SetCVarBitfield(plyCVar, plyEnum.LossOfControl, true, "CludesUINameplates")
            end
        end
    end
    do
        local saved = p or defaultSet
        local nameOnly = (saved.friendlyNameOnly ~= false)
        local showPlayers = (saved.showFriendlyPlayers ~= false)
        local showNPCs = (saved.showFriendlyNPCs == true)
        -- Friendly player CVars are written ONLY while CUI manages friendly player nameplates;
        -- with "Show CludesUI Friendly Player Nameplates" off we relinquish them entirely to
        -- Blizzard's own settings. Friendly NPC and enemy pet CVars are always managed.
        if showPlayers then
            CUI.SetCVar(
                "nameplateShowOnlyNameForFriendlyPlayerUnits",
                nameOnly and 1 or 0,
                "CludesUINameplates"
            )
            CUI.SetCVar("UnitNameFriendlyPlayerName", 1, "CludesUINameplates")
            -- Visibility is NOT re-asserted: nameplateShowFriends/nameplateShowFriendlyPlayers
            -- persist across sessions, so forcing them each login would re-show plates the user
            -- deliberately hid. The one-time seed below covers a first install only.
            if CludesUIDB and not CludesUIDB.friendlyPlateVisSeeded then
                CludesUIDB.friendlyPlateVisSeeded = true
                -- Fresh install only: an existing install is stamped WITHOUT forcing, so a
                -- user who already hid friendly plates keeps that.
                if CUI._firstInstallPending and mod.ForceFriendlyPlayerCVarsOn then
                    mod.ForceFriendlyPlayerCVarsOn()
                end
            end
        end
        CUI.SetCVar("nameplateShowFriendlyNPCs", showNPCs and 1 or 0, "CludesUINameplates")
        CUI.SetCVar("nameplateShowFriendlyNpcs", showNPCs and 1 or 0, "CludesUINameplates")
        CUI.SetCVar(
            "nameplateShowEnemyPets",
            (saved.showEnemyPets == true) and 1 or 0,
            "CludesUINameplates"
        )
        if showPlayers then
            CUI.SetCVar(
                "ShowClassColorInFriendlyNameplate",
                (saved.classColorFriendly ~= false) and 1 or 0,
                "CludesUINameplates"
            )
        end
        CUI.SetCVar("ShowClassColorInNameplate", 1, "CludesUINameplates")
        CUI.SetCVar("nameplateSize", 3, "CludesUINameplates")
        CUI.SetCVar("nameplateShowAll", 1, "CludesUINameplates")
        CUI.SetCVar("nameplateMinScale", 1, "CludesUINameplates")
        CUI.SetCVar("nameplateOverlapH", 1, "CludesUINameplates")
        -- nameplateOverlapV is deliberately left alone: it's the user's own vertical-spacing
        -- cvar (Blizzard default 1.10). Our "Stacked Nameplate Spacing" slider layers extra
        -- spacing on top via the stacking-bounds frame.
        CUI.SetCVar("nameplateMaxAlpha", 1, "CludesUINameplates")
        CUI.SetCVar("nameplateMaxAlphaDistance", 40, "CludesUINameplates")
        CUI.SetCVar("nameplateMinAlpha", 0.6, "CludesUINameplates")
        CUI.SetCVar("nameplateMinAlphaDistance", -100000, "CludesUINameplates")
        CUI.SetCVar("nameplateMaxDistance", 60, "CludesUINameplates")
        CUI.SetCVar("nameplateMaxScale", 1, "CludesUINameplates")
        -- Neutralize Blizzard's selected-target scaling: the CUI plate is a child of the base
        -- nameplate, so Blizzard's scaling shows through our own SetScale (min/max pinned to 1
        -- for the same reason). Pinned to 1, "Scale Target Nameplate" is the sole authority.
        CUI.SetCVar("nameplateSelectedScale", 1, "CludesUINameplates")
        CUI.SetCVar("nameplateTargetBehindMaxDistance", 30, "CludesUINameplates")
        CUI.SetCVar("clampTargetNameplateToScreen", 1, "CludesUINameplates")
        if showPlayers then
            CUI.SetCVar(
                "nameplateUseClassColorForFriendlyPlayerUnitNames",
                mod.FriendlyNameClassCVar(saved),
                "CludesUINameplates"
            )
        end
    end
    -- Hide realm names on friendly nameplates inside instances
    if NamePlateFriendlyFrameOptions and TextureLoadingGroupMixin then
        if NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName then
            local wrapper = { textures = NamePlateFriendlyFrameOptions }
            NamePlateFriendlyFrameOptions.updateNameUsesGetUnitName = 0
            TextureLoadingGroupMixin.RemoveTexture(wrapper, "updateNameUsesGetUnitName")
        end
    end
    -- Apply stacking state via the Midnight bitfield CVar.
    mod.RefreshStackingMotion()
    local function ApplyNamePlateClickArea()
        if InCombatLockdown() then return end
        local saved = p or defaultSet
        local sx = (saved.hitboxScaleX or 100) / 100
        if C_NamePlate and C_NamePlate.SetNamePlateSize then
            C_NamePlate.SetNamePlateSize(GetHealthBarWidth() * sx, mod.NP_HitboxHeight(saved))
        end
        if
            C_NamePlateManager
            and C_NamePlateManager.SetNamePlateHitTestInsets
            and Enum
            and Enum.NamePlateType
        then
            C_NamePlateManager.SetNamePlateHitTestInsets(
                Enum.NamePlateType.Enemy,
                -10000,
                -10000,
                -10000,
                -10000
            )
            C_NamePlateManager.SetNamePlateHitTestInsets(
                Enum.NamePlateType.Friendly,
                -10000,
                -10000,
                -10000,
                -10000
            )
        end
    end
    ApplyNamePlateClickArea()
    -- Prevent Blizzard resetting nameplate sizes on display changes (jitter).
    if NamePlateDriverFrame then
        NamePlateDriverFrame:UnregisterEvent("DISPLAY_SIZE_CHANGED")
        NamePlateDriverFrame:UnregisterEvent("CVAR_UPDATE")
        hooksecurefunc(NamePlateDriverFrame, "UpdateNamePlateOptions", ApplyNamePlateClickArea)
        -- Suppress Blizzard class resource bar setup on our nameplates
        if NamePlateDriverFrame.SetupClassNameplateBars then
            hooksecurefunc(NamePlateDriverFrame, "SetupClassNameplateBars", function(self)
                if self.classNamePlatePowerBar then
                    self.classNamePlatePowerBar:Hide()
                    self.classNamePlatePowerBar:UnregisterAllEvents()
                end
                if self.classNamePlateMechanicFrame then
                    self.classNamePlateMechanicFrame:Hide()
                    self.classNamePlateMechanicFrame:UnregisterAllEvents()
                end
                if self.classNamePlateAlternatePowerBar then
                    self.classNamePlateAlternatePowerBar:Hide()
                    self.classNamePlateAlternatePowerBar:UnregisterAllEvents()
                end
            end)
        end
        -- Suppress the Blizzard UnitFrame before our NAME_PLATE_UNIT_ADDED fires
        -- so its initial layout pass never affects nameplate bounds. Any other
        -- unit gets back what an earlier enemy parked on this pooled UnitFrame.
        hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, addedUnit)
            if not addedUnit or addedUnit == "preview" then return end
            local np = C_NamePlate.GetNamePlateForUnit(addedUnit)
            if not np then return end
            mod.NP_HideBehindCameraIcon(np.UnitFrame)
            if UnitCanAttack("player", addedUnit) then
                mod.HideBlizzardFrame(np, addedUnit)
            else
                mod.NP_ReclaimBlizzardFrame(np.UnitFrame)
            end
        end)
    end
    mod.ApplyNamePlateClickArea = ApplyNamePlateClickArea
end

Inner.NotifyCastEnded, Inner.NotifyCastStarted = NotifyCastEnded, NotifyCastStarted
Inner.SetupAuraCVars = SetupAuraCVars
Inner.broken = false
