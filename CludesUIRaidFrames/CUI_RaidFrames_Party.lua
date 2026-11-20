if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Party.lua
--
--  The party container, the party header, the party settings proxy and the
--  indicator auto-resize.
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
local ipairs = ipairs
local wipe = wipe
local type = type
local UnitClass = UnitClass
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local CreateFrame = CreateFrame

local GetFFD, PixelSnap, UpdateButton = Inner.GetFFD, Inner.PixelSnap, Inner.UpdateButton
local UpdateReadyCheck = Inner.UpdateReadyCheck

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(v)
    saved = v
end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(v)
    containerFrame = v
end

-------------------------------------------------------------------------------
--  Unlock mode registration
-------------------------------------------------------------------------------
-- Party container frame (placeholder for unlock mode positioning)
mod._partyContainerFrame = CreateFrame("Frame", nil, UIParent)
mod._partyContainerFrame:SetSize(125, 308)
-- File-scope creation: ns._ResolveFrameStrata is not defined yet here. The
-- saved strata lands via OnEnable's ApplyFrameStrata call every login.
mod._partyContainerFrame:SetFrameStrata("LOW")
mod._partyContainerFrame:Hide()

-------------------------------------------------------------------------------
--  Party frames: real SecureGroupHeader (5 buttons, reuses all raid rendering)
--  Minimal infrastructure -- StyleButton, UpdateButton, etc.
--  are the same functions used by raid buttons. Party buttons just get
--  party-specific sizing via ReloadPartyFrames.
-------------------------------------------------------------------------------
mod._partyAllButtons = {}
mod._partyUnitToButton = {}
mod._partyHeader = nil
mod._partyFramesVisible = false

-------------------------------------------------------------------------------
--  Party settings proxy
--  Per-section sync: partySyncSections[sectionKey] = true (synced) or false
--  (custom). Party buttons read "party_<key>" only for keys whose section
--  is unsynced. Falls through to raid value otherwise.
--  ALL tables/functions stored on ns.
-------------------------------------------------------------------------------
mod._PARTY_KEY_SECTION = {}

mod._PARTY_SECTION_ORDER = {
    "healthBar",
    "absorbs",
    "powerBar",
    "textDisplay",
    "indicators",
    "dispels",
    "topNameBar",
    "rangeTooltip",
}
mod._PARTY_SECTION_LABELS = {
    healthBar = "Health Bar",
    absorbs = "Absorbs",
    powerBar = "Power Bar",
    textDisplay = "Text Display",
    indicators = "Indicators",
    dispels = "Dispels",
    topNameBar = "Top Name Bar",
    rangeTooltip = "Range & Tooltip",
}

do
    local map = {
        healthBar = {
            "healthBarTexture",
            "healthBarOpacity",
            "healthColorMode",
            "customFillColor",
            "dynamicColor100",
            "dynamicColor50",
            "dynamicColor0",
            "customBgColor",
            "bgClassColored",
            "bgDarkness",
            "smoothBars",
            "healPrediction",
            "healPredOpacity",
            "healPredColor",
            "healthVerticalFill",
            "healthInvertFill",
            "textureBg",
            -- Drawn as "Threat Borders" (and its cog) on the Health Bar row, so they file here.
            "threatBorderSize",
            "threatCustomBorder",
        },
        absorbs = {
            "absorbStyle",
            "absorbOpacity",
            "absorbColor",
            "absorbEdgeMode",
            "showOvershield",
            "overshieldMode",
            "absorbGlowLine",
            "absorbBarEnabled",
            "absorbBarPosition",
            "absorbBarHeight",
            "absorbBarColor",
            "absorbBarGrowDir",
            "healAbsorbBarPosition",
            "healAbsorbBarHeight",
            "healAbsorbBarColor",
            "healAbsorbBarGrowDir",
            "healAbsorbStyle",
            "healAbsorbOpacity",
            "healAbsorbColor",
            "healAbsorbEdgeMode",
            "healAbsorbBgOpacity",
            "maxHealthStyle",
            "maxHealthOpacity",
            "maxHealthColor",
            "maxHealthBgOpacity",
        },
        powerBar = {
            "showPowerBar",
            "powerHeight",
            "powerBgDarkness",
            "powerBgColor",
            "powerBgPowerColored",
            "powerBorderStyle",
            "powerBorderMatchFrame",
            "powerBorderMatchColor",
            "powerBorderSize",
            "powerBorderColor",
            "powerBorderAlpha",
            "powerShowForHealer",
            "powerShowForTank",
            "powerShowForDPS",
            "smoothPowerBars",
            "powerUniformAnchors",
            "extendHealthBehindPower",
        },
        textDisplay = {
            "nameSize",
            "nameMaxLength",
            "nameFormat",
            "nameColorMode",
            "nameCustomColor",
            "namePosition",
            "nameOffsetX",
            "nameOffsetY",
            "levelTextSize",
            "levelTextPosition",
            "levelTextOffsetX",
            "levelTextOffsetY",
            "healthTextMode",
            "healthTextColorMode",
            "healthTextCustomColor",
            "healthTextSize",
            "healthTextPosition",
            "healthTextOffsetX",
            "healthTextOffsetY",
            "healAbsorbTextMode",
            "healAbsorbTextColorMode",
            "healAbsorbTextCustomColor",
            "healAbsorbTextSize",
            "healAbsorbTextPosition",
            "healAbsorbTextOffsetX",
            "healAbsorbTextOffsetY",
            "powerTextMode",
            "powerTextColorMode",
            "powerTextCustomColor",
            "powerTextSize",
            "powerTextPosition",
            "powerTextOffsetX",
            "powerTextOffsetY",
            "nameTextAboveIcons",
            -- Plus the second Health Text and the Custom texts (ns.RF_TEXT_NEW_KEYS).
        },
        indicators = {
            "roleIconStyle",
            "roleIconSize",
            "roleIconPosition",
            "roleIconOffsetX",
            "roleIconOffsetY",
            "roleIconHideInCombat",
            "roleIconOnNameBar",
            "roleNameBarPosition",
            "roleNameBarOffsetX",
            "roleNameBarOffsetY",
            "roleIconBehindBorder",
            "roleText",
            "roleTextTankColor",
            "roleTextHealerColor",
            "roleTextDPSColor",
            "showRoleForTank",
            "showRoleForHealer",
            "showRoleForDPS",
            "showRaidMarker",
            "raidMarkerSize",
            "raidMarkerPosition",
            "raidMarkerOffsetX",
            "raidMarkerOffsetY",
            "showPingMarker",
            "pingMarkerSize",
            "pingMarkerPosition",
            "pingMarkerOffsetX",
            "pingMarkerOffsetY",
            "showMissingBuffs",
            "missingBuffsSize",
            "missingBuffsPosition",
            "missingBuffsOffsetX",
            "missingBuffsOffsetY",
            "missingBuffsFort",
            "missingBuffsMark",
            "missingBuffsIntellect",
            "missingBuffsSpirit",
            "missingBuffsThorns",
            "missingBuffsSalvation",
            "missingBuffsBlessing",
            "missingBuffsThornsTank",
            "missingBuffsBlessingTank",
            "missingBuffsBlessingHealer",
            "missingBuffsBlessingDPS",
            "missingBuffsBlessingExTank",
            "missingBuffsBlessingExHealer",
            "missingBuffsBlessingExDPS",
            "missingBuffsGlowType",
            "missingBuffsGlowColorMode",
            "missingBuffsGlowR",
            "missingBuffsGlowG",
            "missingBuffsGlowB",
            "missingBuffsGlowLines",
            "missingBuffsGlowThickness",
            "missingBuffsGlowSpeed",
            "missingBuffsGlowBackground",
            "missingBuffsGlowBackgroundR",
            "missingBuffsGlowBackgroundG",
            "missingBuffsGlowBackgroundB",
            "showReadyCheck",
            "showSummonPending",
            "showIncomingRez",
            "readyCheckSize",
            "readyCheckPosition",
            "readyCheckOffsetX",
            "readyCheckOffsetY",
            "statusTextPosition",
            "statusTextOffsetX",
            "statusTextOffsetY",
            "statusTextSize",
            "statusTextColor",
            "statusShowAFK",
            "showLeaderIcon",
            "showLeaderIconInCombat",
            "leaderIconPosition",
            "leaderIconSize",
            "leaderIconOffsetX",
            "leaderIconOffsetY",
            "showCombatIndicator",
            "combatIndicatorStyle",
            "combatIndicatorColor",
            "combatIndicatorCustomColor",
            "combatIndicatorSize",
            "combatIndicatorPosition",
            "combatIndicatorOffsetX",
            "combatIndicatorOffsetY",
            "borderSize",
            "borderColor",
            "borderAlpha",
            "borderTexture",
            "borderBehind",
            "borderTextureOffset",
            "borderTextureOffsetY",
            "borderTextureShiftX",
            "borderTextureShiftY",
            "cornerRadius",
            "cornerMask",
            "hoverBorderEnabled",
            "hoverBorderSize",
            "hoverBorderColor",
            "hoverBorderAlpha",
            "targetBorderEnabled",
            "targetBorderSize",
            "targetBorderColor",
            "targetBorderAlpha",
            -- Exact-size companions (see ns._PARTY_PX_SIBLING): same section as their siblings.
            "borderSizePx",
            "hoverBorderSizePx",
            "targetBorderSizePx",
        },
        -- Must list every key the DISPELS section of the options page draws:
        -- the party tab's blocking overlay is sized from that section's y-range,
        -- so a control there is editable whenever "dispels" is unsynced. A key
        -- filed under another section (or missing) is still editable but writes
        -- the shared raid value.
        dispels = {
            "dispelBorderSize",
            "dispelOverlay",
            "dispelOverlayOpacity",
            "dispelShowAll",
            "showDispelIcons",
            "dispelIconPosition",
            "dispelIconOffsetX",
            "dispelIconOffsetY",
            "dispelIconSize",
            "dispelColorMagic",
            "dispelColorCurse",
            "dispelColorDisease",
            "dispelColorPoison",
            "dispelColorBleed",
            "dispelIconBorderSize",
            "dispelOverlayPosition",
            "dispelCustomBorder",
            "dispelClockBorder",
            "dispelClockExtraBorder",
            "dispellableDebuffLocation",
            "dispellableDebuffGrowDirection",
            "dispellableDebuffOffsetX",
            "dispellableDebuffOffsetY",
            "dispellableDebuffSize",
        },
        topNameBar = {
            "topNameBarEnabled",
            "topNameBarHeight",
            "topNameBarDivider",
            "topNameBarDividerMatchColor",
            "topNameBarBgColor",
            "topNameBarBgOpacity",
            "topNameBarTextSize",
            "topNameBarTextColorMode",
            "topNameBarTextColor",
            "topNameBarTextOffsetX",
            "topNameBarTextOffsetY",
            "topNameBarTextAlign",
            "topNameBarBottom",
        },
        rangeTooltip = {
            "oorAlpha",
            "showTooltip",
            "tooltipMode",
            "frameStrata",
        },
    }
    for section, keyList in pairs(map) do
        for _, k in ipairs(keyList) do
            mod._PARTY_KEY_SECTION[k] = section
        end
    end
    for _, k in ipairs(mod.RF_TEXT_NEW_KEYS) do
        mod._PARTY_KEY_SECTION[k] = "textDisplay"
    end
end

-- A border's exact-size companion ("<key>Px", read through CludesUI.BorderPx)
-- is ONE setting with its legacy sibling: wherever the party reads a stored
-- party_<sibling>, the companion resolves ONLY to party_<companion> (nil
-- included), never through to the raid companion. Applied by the proxy
-- __index, the materializer and the ReloadPartyFrames temp-swap. The Blizzard
-- Glow Line pairs with Absorb Style the same way: unset, it follows the style
-- it is read with, so a party that keeps its own style never takes the raid's.
mod._PARTY_PX_SIBLING = {
    borderSizePx = "borderSize",
    hoverBorderSizePx = "hoverBorderSize",
    targetBorderSizePx = "targetBorderSize",
    absorbGlowLine = "absorbStyle",
}

mod._IsPartySectionCustom = function(section)
    if not saved or not saved.profile then
        return false
    end
    local ss = saved.profile.partySyncSections
    if not ss then
        return false
    end
    return ss[section] == false
end

-- Party inherits raid strata unless its Extras section is unsynced.
function mod._ResolveFrameStrata(isParty)
    local strata
    if isParty and mod._IsPartySectionCustom("rangeTooltip") then
        strata = saved.profile.party_frameStrata
    end
    strata = strata or saved.profile.frameStrata or "LOW"
    if
        strata ~= "BACKGROUND"
        and strata ~= "LOW"
        and strata ~= "MEDIUM"
        and strata ~= "HIGH"
        and strata ~= "DIALOG"
    then
        strata = "LOW"
    end
    return strata
end

function mod.ApplyFrameStrata()
    if not saved or not saved.profile then
        return false
    end
    if InCombatLockdown() then
        mod._frameStrataDirty = true
        return false
    end

    mod._frameStrataDirty = nil
    local raidStrata = mod._ResolveFrameStrata(false)
    local partyStrata = mod._ResolveFrameStrata(true)
    local changed = false

    if containerFrame and containerFrame:GetFrameStrata() ~= raidStrata then
        containerFrame:SetFrameStrata(raidStrata)
        changed = true
    end
    if mod._partyContainerFrame and mod._partyContainerFrame:GetFrameStrata() ~= partyStrata then
        mod._partyContainerFrame:SetFrameStrata(partyStrata)
        changed = true
    end
    if changed and mod._RefreshPreviewMouseBlockStrata then
        mod._RefreshPreviewMouseBlockStrata()
    end

    return changed
end

-- The Absorbs section was split out of Health Bar: profiles saved before the
-- split carry no "absorbs" sync state, so they inherit the Health Bar state
-- that governed those settings at the time. Idempotent (only fills a nil key)
-- and runs on every enable/profile swap, so imported profiles are covered too.
mod._NormalizePartySyncSections = function()
    if not (saved and saved.profile) then
        return
    end
    local ss = saved.profile.partySyncSections
    if ss and ss.absorbs == nil and ss.healthBar == false then
        ss.absorbs = false
    end
    -- Enable/profile-swap chokepoint: recompute the proxy fast modes against
    -- the (possibly new) profile table and section state.
    if mod._RefreshProxyModes then
        mod._RefreshProxyModes()
    end
end

mod._partyProxy = setmetatable({}, {
    __index = function(_, key)
        local section = mod._PARTY_KEY_SECTION[key]
        if section and saved and saved.profile and mod._IsPartySectionCustom(section) then
            local sib = mod._PARTY_PX_SIBLING[key]
            if sib and rawget(saved.profile, "party_" .. sib) ~= nil then
                return rawget(saved.profile, "party_" .. key)
            end
            local pv = rawget(saved.profile, "party_" .. key)
            if pv ~= nil then
                return pv
            end
        end
        return saved and saved.profile and saved.profile[key]
    end,
})

-------------------------------------------------------------------------------
--  Auto-resize indicators: scale all indicator sizes/offsets proportionally
--  when a custom raid size tier is active.  Uses a metatable proxy so
--  rendering functions read scaled values transparently.
-------------------------------------------------------------------------------
mod._indicatorScale = 1
-- Separate scale for party frames (party + raid never display together, but the
-- single global was a conflict trap). Computed by ns._UpdatePartyIndicatorScale.
mod._partyIndicatorScale = 1
-- Buff Manager scales: identical formulas but NOT gated on the Auto Resize
-- toggles -- BM indicators always track frame size (raid tier / party size).
mod._bmScale = 1
mod._partyBmScale = 1
-- Extra Frames duplicates: scale ratio from the Extra Width/Height offsets, relative to
-- the size the real raid frames currently render at. ALWAYS on (not gated by Auto
-- Resize): a custom-sized duplicate scales its texts, indicators, auras and BM buffs to
-- match. Composes with the raid tier scales -- the extra proxy chains through
-- ns._scaledProfile, and the BM scale multiplies ns._bmScale. Both set by XF.Layout.
mod._xfExtraRatio = 1
mod._xfBmScale = 1

local INDICATOR_SCALE_KEYS = {}
for _, k in ipairs({
    -- Font sizes
    "nameSize",
    "healthTextSize",
    "healAbsorbTextSize",
    "statusTextSize",
    "powerTextSize",
    "levelTextSize",
    "debuffStacksTextSize",
    "debuffDurTextSize",
    "defDurTextSize",
    -- Icon sizes
    "roleIconSize",
    "leaderIconSize",
    "raidMarkerSize",
    "combatIndicatorSize",
    "pingMarkerSize",
    "missingBuffsSize",
    "debuffSize",
    "defSize",
    "dispellableDebuffSize",
    -- Offsets
    "nameOffsetX",
    "nameOffsetY",
    "healthTextOffsetX",
    "healthTextOffsetY",
    "healAbsorbTextOffsetX",
    "healAbsorbTextOffsetY",
    "powerTextOffsetX",
    "powerTextOffsetY",
    "levelTextOffsetX",
    "levelTextOffsetY",
    "statusTextOffsetX",
    "statusTextOffsetY",
    "roleIconOffsetX",
    "roleIconOffsetY",
    "leaderIconOffsetX",
    "leaderIconOffsetY",
    "raidMarkerOffsetX",
    "raidMarkerOffsetY",
    "missingBuffsOffsetX",
    "missingBuffsOffsetY",
    "combatIndicatorOffsetX",
    "combatIndicatorOffsetY",
    "debuffOffsetX",
    "debuffOffsetY",
    "dispellableDebuffOffsetX",
    "dispellableDebuffOffsetY",
    "debuffStacksOffsetX",
    "debuffStacksOffsetY",
    "debuffDurTextOffsetX",
    "debuffDurTextOffsetY",
    "defOffsetX",
    "defOffsetY",
    "defDurTextOffsetX",
    "defDurTextOffsetY",
    "dispelIconOffsetX",
    "dispelIconOffsetY",
}) do
    INDICATOR_SCALE_KEYS[k] = true
end
-- The second Health Text and the Custom texts: font size and offsets.
for _, k in ipairs(mod.RF_TEXT_NEW_SCALE_KEYS) do
    INDICATOR_SCALE_KEYS[k] = true
end

mod._scaledProfile = setmetatable({}, {
    __index = function(_, key)
        -- Return active tier dimensions so all rendering uses the correct size
        if key == "frameWidth" and mod._activeSizeW then
            return mod._activeSizeW
        end
        if key == "frameHeight" and mod._activeSizeH then
            return mod._activeSizeH
        end
        local val = saved and saved.profile and saved.profile[key]
        if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and mod._indicatorScale ~= 1 then
            return val * mod._indicatorScale
        end
        return val
    end,
})

-- Extra Frames proxy: chains through ns._scaledProfile (so the raid tier
-- indicator scale still applies) and multiplies the scale keys by the Extra
-- Width/Height offset ratio on top. Selected wherever rendering picks a
-- settings source for a d._isExtra button.
mod._scaledExtraProxy = setmetatable({}, {
    __index = function(_, key)
        local val = mod._scaledProfile[key]
        if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and mod._xfExtraRatio ~= 1 then
            return val * mod._xfExtraRatio
        end
        return val
    end,
})

mod._scaledPartyProxy = setmetatable({}, {
    __index = function(_, key)
        -- Return party dimensions for frameWidth/frameHeight reads. The real-
        -- preview effective overlay (ns._pvOverlayProxy) shadows live while a
        -- panel view swap is active; it falls through to db.profile itself.
        if key == "frameWidth" or key == "frameHeight" then
            local p = mod._pvOverlayProxy or (saved and saved.profile)
            if not p then
                return nil
            end
            -- The bars' width: an attached portrait's share of the box is not theirs.
            local wid, hgt, _, res = mod.RF_PartyDims(p)
            if key == "frameWidth" then
                return wid - (res or 0)
            end
            return hgt
        end
        -- Party Frames kit: the settings its layout decides (neutral keys, the
        -- debuff row under the frame) read the kit's values. Only the overlay
        -- view reaches here for them: otherwise the materializer holds them.
        local ovp = mod._pvOverlayProxy
        if ovp and mod.RF_PartyKit() then
            local kv = mod.RF_KitViewKeys(ovp)
            if kv and kv[key] ~= nil then
                return kv[key]
            end
        end
        local val
        local resolved = false
        -- Effective overlay first (preview-scoped ONLY -- ns._partyProxy also serves the
        -- REAL party frames and must never consult it): party_ variant wins over the base
        -- key, mirroring _partyProxy's precedence. Sentinel deletions resolve to nil
        -- WITHOUT falling through to the live view value.
        local shade = mod._pvOverlayProxy and mod._pvOverlay
        if shade then
            local pv
            local section = mod._PARTY_KEY_SECTION[key]
            if section and mod._IsPartySectionCustom(section) then
                pv = shade["party_" .. key]
            end
            if pv == nil then
                -- An exact-size companion whose party sibling is stored, and whose
                -- raid sibling the overlay does not own, stays unresolved so the
                -- party rule in _partyProxy decides (never the raid companion).
                local sib = mod._PARTY_PX_SIBLING and mod._PARTY_PX_SIBLING[key]
                if
                    not (
                        sib
                        and section
                        and mod._IsPartySectionCustom(section)
                        and rawget(saved.profile, "party_" .. sib) ~= nil
                        and shade[sib] == nil
                    )
                then
                    pv = shade[key]
                end
            end
            if pv ~= nil then
                resolved = true
                if pv ~= CludesUI.SPECOV_NIL then
                    val = pv
                end
            end
        end
        if not resolved then
            val = mod._partyProxy[key]
        end
        if INDICATOR_SCALE_KEYS[key] and type(val) == "number" and mod._partyIndicatorScale ~= 1 then
            return val * mod._partyIndicatorScale
        end
        return val
    end,
})

-- MATERIALIZED effective settings: every render-path read goes through the four proxies,
-- whose __index closures (section checks, overlay checks, scale multiplies) were
-- per-read Lua dispatch on the hottest path in group combat. Since the transforms'
-- INPUTS only change on discrete edges (settings writes, scale recompute, section sync
-- flips, overlay set/clear, spec/profile swaps), effective values are computed ONCE per
-- edge and rawset INTO the proxy tables: reads between edges are raw C-speed table hits.
-- The original full-chain closures REMAIN as each proxy's permanent metatable -- identity
-- compares still work, and any key the materializer misses falls through to the live
-- chain (a gap costs dispatch, never correctness). While the real-preview overlay is
-- active, _scaledPartyProxy stays EMPTY so every read falls through to the full chain
-- (overlay values are panel-scoped and edit live). Rebuilt by every _RefreshProxyModes
-- caller (scales, tier size, sync sections, overlay, enable/profile swap) plus
-- _BumpAbsorbGen (the SSet/SWrite options funnel).
function mod._RefreshProxyModes()
    local p = saved and saved.profile
    if not p then
        return
    end
    local scaleKeys = INDICATOR_SCALE_KEYS

    -- _partyProxy: base profile + party_ overrides for custom sections.
    local pp = mod._partyProxy
    wipe(pp)
    for k, v in pairs(p) do
        rawset(pp, k, v)
    end
    local keySection = mod._PARTY_KEY_SECTION
    local pxSib = mod._PARTY_PX_SIBLING
    if keySection and mod._IsPartySectionCustom then
        for k, section in pairs(keySection) do
            if mod._IsPartySectionCustom(section) then
                local pv = rawget(p, "party_" .. k)
                local sib = pxSib[k]
                if sib and rawget(p, "party_" .. sib) ~= nil then
                    -- Companion of a stored party sibling: the party value only
                    -- (a nil unsets the raid copy; the __index rule answers nil too).
                    rawset(pp, k, pv)
                elseif pv ~= nil then
                    rawset(pp, k, pv)
                end
            end
        end
    end

    -- _scaledProfile: raid tier dimensions + indicator scale.
    local sp = mod._scaledProfile
    wipe(sp)
    local iScale = mod._indicatorScale or 1
    for k, v in pairs(p) do
        if iScale ~= 1 and scaleKeys[k] and type(v) == "number" then
            rawset(sp, k, v * iScale)
        else
            rawset(sp, k, v)
        end
    end
    if mod._activeSizeW then
        rawset(sp, "frameWidth", mod._activeSizeW)
    end
    if mod._activeSizeH then
        rawset(sp, "frameHeight", mod._activeSizeH)
    end

    -- _scaledPartyProxy: party view + party dimensions + party scale.
    -- Overlay active = stay empty (full-chain fallthrough serves the panel).
    local spp = mod._scaledPartyProxy
    wipe(spp)
    if not mod._pvOverlayProxy then
        local pScale = mod._partyIndicatorScale or 1
        for k, v in pairs(pp) do
            if pScale ~= 1 and scaleKeys[k] and type(v) == "number" then
                rawset(spp, k, v * pScale)
            else
                rawset(spp, k, v)
            end
        end
        local pw, ph, _, pres = mod.RF_PartyDims(pp)
        rawset(spp, "frameWidth", pw - (pres or 0))
        rawset(spp, "frameHeight", ph)
        if mod.RF_PartyKit() then
            local kv = mod.RF_KitViewKeys(pp)
            if kv then
                for k, v in pairs(kv) do
                    rawset(spp, k, v)
                end
            end
        end
    end

    -- _scaledExtraProxy: the scaled view with the extra-frames ratio on top.
    local sep = mod._scaledExtraProxy
    wipe(sep)
    local xRatio = mod._xfExtraRatio or 1
    for k, v in pairs(sp) do
        if xRatio ~= 1 and scaleKeys[k] and type(v) == "number" then
            rawset(sep, k, v * xRatio)
        else
            rawset(sep, k, v)
        end
    end

    -- Any pass through here can mean absorb-relevant settings changed:
    -- invalidate every button's absorb value-memo (and the gen-gated
    -- settings pushes inside UpdateAbsorb).
    mod._absorbGen = (mod._absorbGen or 0) + 1
    -- The text plans are rebuilt on their next use (CUI_RaidFrames_TextPaint.lua).
    if mod.RF_TextPlanDirty then
        mod.RF_TextPlanDirty()
    end
    -- The level's event follows the views (defined once the unit trackers exist).
    if mod._RFSyncLevelRegistration then
        mod._RFSyncLevelRegistration()
    end
    -- Custom texts' UNIT_TARGET and power events follow the views too (Lifecycle).
    if mod._RFSyncCustomRegistration then
        mod._RFSyncCustomRegistration()
    end
end
mod._RefreshProxyModes()

-- Options-funnel invalidation: SSet/SWrite call this on EVERY profile write
-- (colors, styles, heights...). It now rebuilds the materialized tables too,
-- so an options write can never leave a stale effective value behind.
mod._BumpAbsorbGen = function()
    mod._RefreshProxyModes()
    -- Settings writes also break the same-frame paint-stamp window: a full pass after
    -- an options write must never dedupe against a paint from before the write.
    mod._paintGen = (mod._paintGen or 0) + 1
    -- Heal-prediction toggles ride this same funnel: re-sync the conditional
    -- UNIT_HEAL_PREDICTION registrations (idempotent, 45 trackers).
    if mod._RFSyncPredRegistration then
        mod._RFSyncPredRegistration()
    end
end

-- Compute the party indicator/aura scale (mirrors the raid auto-resize in
-- ReloadFrames). Party frames have a fixed size (no tiers), so the scale is the
-- party frame size relative to the configured raid base, clamped to [0.7, 1.5].
-- Independent of raid: gated on partyAutoResizeIndicators (default off).
mod._UpdatePartyIndicatorScale = function()
    if not (saved and saved.profile) then
        return
    end
    local cfg = saved.profile
    local scale
    if mod.RF_PartyKit() then
        -- Party Frames kit: its Frame Scale is the frame size (at 100% the
        -- user's own icon and text sizes apply, whatever the raid size), and
        -- icons follow it over its whole range.
        scale = cfg.partyKitScale or mod.RF_KIT_SCALE or 1.2
    else
        local baseW = cfg.frameWidth or 72
        local baseH = cfg.frameHeight or 46
        -- The bars' size (an attached portrait does not enlarge the icons).
        local pw, ph, _, pres = mod.RF_PartyDims(cfg)
        pw = pw - (pres or 0)
        scale = math.max(math.min(math.min(pw / baseW, ph / baseH), 1.3), 0.7)
    end
    -- Auto Resize Icons (two independent checkboxes): Tracked Buffs gates the
    -- Buff Manager scale; Indicators & Auras gates indicator/aura/text sizes.
    -- Tracked Buffs defaults on (nil treated as on) to preserve the prior
    -- hardcoded always-on behavior.
    mod._partyBmScale = (cfg.partyAutoResizeTrackedBuffs ~= false) and scale or 1
    mod._partyIndicatorScale = cfg.partyAutoResizeIndicators and scale or 1
    if mod._RefreshProxyModes then
        mod._RefreshProxyModes()
    end
end

-- Create a single SecureGroupHeader for party frames (5 buttons max).
-- Called once from OnEnable.
mod._CreatePartyHeader = function()
    if mod._partyHeader then
        return
    end
    local cfg = saved.profile
    local pw, ph, pcs = mod.RF_PartyDims(cfg)
    local bw, bh, cs = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)

    local initConfig = ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(bw, bh)

    local heading =
        CreateFrame("Frame", "ERFPartyHeader", mod._partyContainerFrame, "SecureGroupHeaderTemplate")
    heading:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
    heading:SetAttribute("template", "SecureUnitButtonTemplate")
    heading:SetAttribute("templateType", "Button")
    heading:SetAttribute("initialConfigFunction", initConfig)
    heading:SetAttribute("point", "TOP")
    heading:SetAttribute("xOffset", 0)
    heading:SetAttribute("yOffset", -cs)
    heading:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
    -- showRaid=true so the header binds raid units inside an arena, where the
    -- team is a raid group, and in Small Raid mode (group 1 only, via the
    -- groupFilter / nameList set in _LayoutPartyFrames). Inert in a normal
    -- 5-man party (no raid units exist), so it only takes effect when the
    -- header is actually shown in a raid group -- which we do only for those
    -- two modes (see _UpdatePartyVisibility). Otherwise the header is hidden
    -- in a real raid, so this never shows 40 raid units.
    heading:SetAttribute("showRaid", true)
    heading:SetAttribute("showParty", true)
    heading:SetAttribute("showPlayer", true)
    heading:SetAttribute("showSolo", cfg.partyShowWhenSolo or false)
    heading:SetAttribute("maxColumns", 1)
    heading:SetAttribute("unitsPerColumn", 5)

    -- Pre-create 5 buttons. Container must be visible for SecureGroupHeaderTemplate to
    -- process children (IsVisible checks parent chain). Show temporarily, then hide.
    -- The header itself stays shown from here on: only the container hides (its
    -- visibility driver can then show the party frames in combat, the header
    -- re-reading the roster on that show).
    mod._partyContainerFrame:Show()
    heading:SetAttribute("startingIndex", -4)
    heading:Show()
    heading:SetAttribute("startingIndex", 1)
    mod._partyContainerFrame:Hide()

    -- Window-phase secure styling; insecure bodies run in the deferred pass.
    -- _isParty goes first: the secure pass sizes party buttons to the party
    -- box (the header's own initConfig size would otherwise be overwritten
    -- with the raid size).
    for index = 1, 5 do
        local button = heading[index]
        if button then
            GetFFD(button)._isParty = true
            mod._StyleButtonSecure(button)
            mod._partyAllButtons[#mod._partyAllButtons + 1] = button
        end
    end

    -- Self button for "Show Self First": a static unit="player" secure button
    -- (composition). Because the unit is fixed, nothing the header does can
    -- ever move it -- it is always slot 0 and cannot flicker. When self-first
    -- is on, the party header runs showPlayer=false and this button owns the
    -- player frame; when off, it is hidden and the header shows the player.
    local selfBtn =
        CreateFrame("Button", "ERFPartySelfButton", mod._partyContainerFrame, "SecureUnitButtonTemplate")
    selfBtn:SetAttribute("unit", "player")
    local sd = GetFFD(selfBtn)
    sd._isParty = true
    sd._isSelf = true
    mod._StyleButtonSecure(selfBtn)
    selfBtn:Hide()
    mod._partyAllButtons[#mod._partyAllButtons + 1] = selfBtn
    mod._partySelfButton = selfBtn

    mod._partyHeader = heading
end

-- Rebuild party unit map from visible party buttons.
mod._RebuildPartyUnitMap = function()
    wipe(mod._partyUnitToButton)
    for _, button in ipairs(mod._partyAllButtons) do
        if button:IsVisible() then
            local u = button:GetAttribute("unit")
            if u then
                mod._partyUnitToButton[u] = button
                local skinData = GetFFD(button)
                local _, classToken = UnitClass(u)
                skinData.classToken = classToken
            end
        end
    end
end

-- Full update for all visible party buttons (shared rendering functions).
mod._UpdateAllPartyButtons = function()
    if mod._partyPvActive then
        return
    end
    for _, button in ipairs(mod._partyAllButtons) do
        local u = button:GetAttribute("unit")
        if u and button:IsVisible() then
            UpdateButton(button)
            UpdateReadyCheck(button, u)
        end
    end
end

-- Position the self button + party header at their slot offsets, sized from the CURRENT
-- frame dimensions. Shared by the full layout pass and the width/height slider hot path
-- (_ResizePartyButtons): the slot offsets and the header's own size both derive from
-- the frame size, so a live resize must re-apply them or the self button drifts from
-- the header stack and the header's centered child anchors keep growing around the
-- stale width. Returns useSelf for the caller's showPlayer attribute logic.
mod._PositionPartySlots = function(bw, bh, cs, unitGrowth)
    if not mod._partyHeader then
        return false
    end
    local cfg = saved.profile
    local pSelfFirst = cfg.partyShowSelfFirst
    if pSelfFirst == nil then
        pSelfFirst = cfg.showSelfFirst
    end
    local pSelfLast = cfg.partySelfLast
    if pSelfLast == nil then
        pSelfLast = cfg.showSelfLast
    end
    local hideSelf = cfg.partyHideSelf
    -- Party-in-raid mode (arena, Small Raid) binds the header to raid units,
    -- which include the player, and showPlayer=false cannot exclude the player
    -- in a raid group. The static self button would then duplicate the player,
    -- so disable it there and let the header show the player natively (there
    -- showPlayer reduces to "not hideSelf" in _LayoutPartyFrames; the raid
    -- nameList -- not showPlayer -- is what omits the player when Hide Self is on).
    -- Sort By = FrameSort: its list places the player, so the self button
    -- stands down and the player stays inside the header.
    -- A party set the group state hides is laid out native (no self button, no
    -- centering): the visibility driver can show it mid-fight, when neither can
    -- be placed, and the header alone then shows every member from the first slot.
    local _, live = mod._RFVisWanted()
    local useSelf = live
        and (pSelfFirst or pSelfLast)
        and not hideSelf
        and IsInGroup()
        and not mod._PartyInRaid()
        and not mod._FsPartyMode()

    -- The header's own size feeds the first child's centered anchor
    -- (point=TOP centers on header width; point=LEFT centers on height).
    -- Anchors track size changes live, so this re-centers the stack with NO
    -- secure child re-process (and therefore no blink) during slider drags.
    -- The header re-derives the same size on its next natural child pass.
    mod._partyHeader:SetSize(bw, bh)

    -- Step between adjacent unit slots along the growth axis. Slot 0 sits at
    -- the container corner the growth direction moves AWAY from (Flip Frame
    -- Growth turns DOWN into UP and RIGHT into LEFT), so the container always
    -- bounds the visual stack.
    local slotStepX, slotStepY = 0, 0
    local basePoint = "TOPLEFT"
    if unitGrowth == "RIGHT" then
        slotStepX = bw + cs
    elseif unitGrowth == "LEFT" then
        slotStepX = -(bw + cs)
        basePoint = "TOPRIGHT"
    elseif unitGrowth == "UP" then
        slotStepY = bh + cs
        basePoint = "BOTTOMLEFT"
    else -- DOWN
        slotStepY = -(bh + cs)
    end

    -- Centered growth shifts the whole stack (self button + header) so the
    -- shown frames sit centered in the always-5-slot container: (5 - shown)/2
    -- slots along the growth axis. Solo is the shown=1 case of the same math,
    -- and the Center When Solo cog forces it while solo regardless of the growth mode.
    local centerShift = 0
    local centered = (cfg.partyFlipGrowth == "centered")
    if not live then
        -- Hidden set: the stack starts at the first slot (see useSelf above).
    elseif not IsInGroup() then
        if centered or cfg.partyCenterWhenSolo then
            centerShift = 2
        end
    elseif centered then
        local isShown = GetNumGroupMembers() or 0
        if isShown > 5 then
            isShown = 5
        end
        if hideSelf then
            isShown = isShown - 1
        end
        if isShown < 1 then
            isShown = 1
        end
        centerShift = (5 - isShown) / 2
    end
    local cShiftX = PixelSnap(slotStepX * centerShift)
    local cShiftY = PixelSnap(slotStepY * centerShift)

    local scrollBar = mod._partySelfButton
    if useSelf then
        local selfSlot, hdrSlot = 0, 1
        if pSelfLast then
            local numOthers = (GetNumGroupMembers() or 1) - 1
            if numOthers < 0 then
                numOthers = 0
            end
            selfSlot, hdrSlot = numOthers, 0
        end
        if scrollBar then
            scrollBar:SetSize(bw, bh)
            scrollBar:ClearAllPoints()
            scrollBar:SetPoint(
                basePoint,
                mod._partyContainerFrame,
                basePoint,
                PixelSnap(slotStepX * selfSlot) + cShiftX,
                PixelSnap(slotStepY * selfSlot) + cShiftY
            )
            if not InCombatLockdown() then
                scrollBar:Show()
            end
        end
        mod._partyHeader:ClearAllPoints()
        mod._partyHeader:SetPoint(
            basePoint,
            mod._partyContainerFrame,
            basePoint,
            PixelSnap(slotStepX * hdrSlot) + cShiftX,
            PixelSnap(slotStepY * hdrSlot) + cShiftY
        )
    else
        if scrollBar and not InCombatLockdown() then
            scrollBar:Hide()
        end
        mod._partyHeader:ClearAllPoints()
        mod._partyHeader:SetPoint(basePoint, mod._partyContainerFrame, basePoint, cShiftX, cShiftY)
    end
    -- The pet frames line up with whichever frame holds slot 0, and your own pet (Beside Owner)
    -- goes with whichever frame shows you.
    local first = (useSelf and not pSelfLast and scrollBar) or mod._partyHeader
    local selfMode = (useSelf and "button") or (hideSelf and "hidden") or "header"
    if first ~= mod._partyFirstSlot or selfMode ~= mod._partySelfMode then
        mod._partyFirstSlot, mod._partySelfMode = first, selfMode
        mod.PF_ReAnchor()
    end
    return useSelf
end

-- Party growth direction. Explicit true only: "centered" keeps the default
-- direction.
mod._PartyGrowth = function(cfg)
    -- (Party Frames kit: horizontal frames carry their buffs above each
    -- frame -- ns.RF_KitBmView -- so the next frame beside it stays clear.)
    if cfg.partyHorizontal then
        return (cfg.partyFlipGrowth == true) and "LEFT" or "RIGHT"
    end
    return (cfg.partyFlipGrowth == true) and "UP" or "DOWN"
end

-- Size the party container (the unlock mover's rect: always 5 slots) from
-- snapped slot dimensions. Every sizer goes through here so they all agree.
-- Resizing the container triggers an implicit SecureGroupHeader child
-- re-process, and that implicit pass has been observed landing with units
-- unassigned (NAMELIST sort especially): children left hidden with unit=nil
-- until the next clean re-process. The resize is bracketed with an explicit
-- header Hide/Show -- the implicit pass runs while hidden (inert) and the
-- Show() performs a clean, reliable re-process -- and skipped when unchanged.
-- Out of combat only (callers gate).
mod._SizePartyContainer = function(bw, bh, cs, unitGrowth)
    local c = mod._partyContainerFrame
    if not c then
        return
    end
    local cw, ch
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        cw, ch = 5 * bw + 4 * cs, bh
    else
        cw, ch = bw, 5 * bh + 4 * cs
    end
    cw, ch = PixelSnap(cw), PixelSnap(ch)
    local curW, curH = c:GetSize()
    if math.abs((curW or 0) - cw) > 0.01 or math.abs((curH or 0) - ch) > 0.01 then
        local heading = mod._partyHeader
        local isShown = heading and heading:IsShown()
        if isShown then
            heading:Hide()
        end
        c:SetSize(cw, ch)
        if isShown then
            heading:Show()
        end
    end
end

Inner.broken = false
