if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_ProfileSync.lua
--  Profile sync mirror groups, per-module sync exclusions, and the sync
--  popup anchored to the sidebar. Loads after CludesUI_Fonts.lua.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
-- Private namespace shared with CludesUI.lua (sidebar buttons).
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)

-------------------------------------------------------------------------------
--  Profile Sync System (mirror groups)
--  A module's sync set is a MEMBERSHIP group (popup adds the configuring profile too).
--  Two-way: active member pushes a selective copy to others on sync click, logout, and
--  profile switch; outside profiles never push in. Storage: CludesUIDB.syncedModules
--  = { [folder] = { [profileName] = true } }. Exclusions: CludesUI._syncExclusions
--  [folder] = { key = true }; dot-wildcard "bars.*.growDirection" skips that key in any sub-table of bars.
-------------------------------------------------------------------------------
do
    -- Modules that should NOT get a sync icon (no per-profile settings; Loadout
    -- Manager and Simple Loot Council keep stores of their own)
    local SYNC_EXEMPT =
        { CludesUIPartyMode = true, CludesUILoadoutManager = true, CludesUISimpleLootCouncil = true }
    CludesUI._syncExempt = SYNC_EXEMPT

    -- Modules with a sync icon but no per-profile data (always "synced"). BlizzardSkin hosts
    -- Dragon Riding's per-profile DB; its sync icon routes to CludesUIDragonRiding via syncFolder.
    local SYNC_GLOBAL_ONLY = { CludesUIForeverEssentials = true }
    CludesUI._syncGlobalOnly = SYNC_GLOBAL_ONLY

    -- Exclusion registry: keys NOT copied during sync (flat or dot-wildcard, see banner)
    local syncExclusions = {}
    CludesUI._syncExclusions = syncExclusions

    function CludesUI.RegisterSyncExclusions(folder, keyList)
        if not syncExclusions[folder] then
            syncExclusions[folder] = {}
        end
        local ex = syncExclusions[folder]
        for _, key in ipairs(keyList) do
            ex[key] = true
        end
    end

    -- Merged exclusions for ONE src->dst copy: static registry plus every setting EITHER
    -- profile holds a spec/conditional OVERRIDE entry for (override-owned keys never sync --
    -- the override system owns them; a pushed blob would drift from the dest's recorded values).
    -- PURE READ of profile tables only (no override store creation/harvest/apply/capture).
    -- Returns staticEx unchanged (zero alloc) when neither profile has override data, else a
    -- fresh table (shared registry never mutated); callers pcall and fall back to staticEx on error.
    -- fkey = folder.."\31"..path, segments joined by "\30" (mirrors SplitFKey in
    -- CludesUI_SpecOverrides.lua); matcher walks the tree dot-joined so gsub("\30",".") is exact.
    CludesUI._SyncExclusionsWithOverrides = function(folder, staticEx, srcProf, dstProf)
        local merged
        local function ensure()
            if not merged then
                merged = {}
                if staticEx then
                    for key in pairs(staticEx) do
                        merged[key] = true
                    end
                end
            end
        end
        local function addStore(storage)
            if type(storage) ~= "table" then
                return
            end
            for _, record in ipairs(storage) do
                local vals = type(record) == "table" and record.values
                if type(vals) == "table" then
                    for _, m in pairs(vals) do -- default map + every spec/gid map
                        if type(m) == "table" then
                            for fkey in pairs(m) do
                                if type(fkey) == "string" then
                                    local f, filePath = fkey:match("^([^\31]+)\31(.*)$")
                                    if f == folder and filePath and filePath ~= "" then
                                        ensure()
                                        merged[filePath:gsub("\30", ".")] = true
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        local function addProf(prof)
            if type(prof) ~= "table" then
                return
            end
            addStore(prof.specOverrides)
            addStore(prof.condOverrides)
            if folder == "CludesUIRaidFrames" then
                -- BM forks are layer-shaped, not fkey-shaped: the fork system writes
                -- bmIndicators/bmSimple/bmDisplayMode/bmIconZoom straight into the live RF blob,
                -- so if EITHER profile carries ANY BM layer, those keys are fork territory and
                -- must not sync (emptiness check mirrors the BM harvest's zero-cost gate).
                local s, c = prof.specBmOverrides, prof.condBmOverrides
                if
                    (
                        type(s) == "table"
                        and (s.active or s.baselineLayout or (type(s.layouts) == "table" and next(s.layouts)))
                    )
                    or (type(c) == "table" and type(c.layouts) == "table" and next(c.layouts))
                then
                    ensure()
                    merged.bmIndicators = true
                    merged.bmSimple = true
                    merged.bmDisplayMode = true
                    merged.bmIconZoom = true
                    merged.bm2 = true -- v2 payload rides BM layers
                end
                -- Debuff Manager forks own the dmDebuff subtree the same way.
                local ds, dc = prof.specDmOverrides, prof.condDmOverrides
                if
                    (
                        type(ds) == "table"
                        and (
                            ds.active
                            or ds.baselineLayout
                            or (type(ds.layouts) == "table" and next(ds.layouts))
                        )
                    )
                    or (type(dc) == "table" and type(dc.layouts) == "table" and next(dc.layouts))
                then
                    ensure()
                    merged.dmDebuff = true
                end
            end
        end
        addProf(srcProf)
        addProf(dstProf)
        return merged or staticEx
    end

    -- Selective deep-copy: src minus excluded keys (flat "barPositions" or wildcard
    -- "bars.*.growDirection" = skip that key in any sub-table of "bars").
    local function SelectiveCopy(source, exclusions, parentPath)
        if type(source) ~= "table" then
            return source
        end
        local copy = {}
        for key, val in pairs(source) do
            local keyStr = tostring(key)
            local fullKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not exclusions[fullKey] then
                if type(val) == "table" then
                    -- Wildcard parent check (e.g. "bars" in "bars.*.X")
                    local isWildcardParent = false
                    local childExclusions = nil
                    for exKey in pairs(exclusions) do
                        local prefixText, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (a bare-name collision is not a wildcard parent)
                        if prefixText and fullKey == prefixText then
                            isWildcardParent = true
                            if not childExclusions then
                                childExclusions = {}
                            end
                            childExclusions[childKey] = true
                        end
                    end
                    if isWildcardParent and childExclusions then
                        -- Copy the container but apply child exclusions to each sub-table
                        local containerCopy = {}
                        for ck, cv in pairs(val) do
                            if type(cv) == "table" then
                                local subCopy = {}
                                local subPath = fullKey .. "." .. tostring(ck)
                                for sk, sv in pairs(cv) do
                                    local leafPath = subPath .. "." .. tostring(sk)
                                    if not childExclusions[tostring(sk)] and not exclusions[leafPath] then
                                        if type(sv) == "table" then
                                            subCopy[sk] = SelectiveCopy(sv, exclusions, leafPath)
                                        else
                                            subCopy[sk] = sv
                                        end
                                    end
                                end
                                containerCopy[ck] = subCopy
                            else
                                containerCopy[ck] = cv
                            end
                        end
                        copy[key] = containerCopy
                    else
                        copy[key] = SelectiveCopy(val, exclusions, fullKey)
                    end
                else
                    copy[key] = val
                end
            end
        end
        return copy
    end
    CludesUI._SelectiveCopy = SelectiveCopy

    -- True when an exclusion is fullKey itself or a path below it, by string prefix; a
    -- wildcard only counts above its '*', so a removed list entry goes with its
    -- wildcard-excluded leaves.
    local function HoldsExclusion(exclusions, fullKey)
        if exclusions[fullKey] then
            return true
        end
        local pre = fullKey .. "."
        for exKey in pairs(exclusions) do
            if exKey:sub(1, #pre) == pre then
                return true
            end
        end
        return false
    end

    -- Exclusion-aware deep overlay for destinations with existing data: writes src into dst
    -- leaf-by-leaf wherever an exclusion path (flat/dotted/wildcard) touches the subtree, so
    -- excluded keys keep dest values (replacing a parent whole would delete them).
    function CludesUI._SelectiveOverlay(source, dst, exclusions, deepCopy, parentPath)
        -- Mirror deletions, as the full copy does: drop dest keys the source no
        -- longer has, unless they hold excluded data.
        for key in pairs(dst) do
            if source[key] == nil then
                local fullKey = parentPath and (parentPath .. "." .. tostring(key)) or tostring(key)
                if not HoldsExclusion(exclusions, fullKey) then
                    dst[key] = nil
                end
            end
        end
        for key, val in pairs(source) do
            local keyStr = tostring(key)
            local fullKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not exclusions[fullKey] then
                if type(val) == "table" then
                    -- Wildcard parent and/or dotted exclusions deeper in this subtree
                    local childExclusions = nil
                    local hasNested = false
                    for exKey in pairs(exclusions) do
                        local prefixText, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (same rule as SelectiveCopy)
                        if prefixText and fullKey == prefixText then
                            if not childExclusions then
                                childExclusions = {}
                            end
                            childExclusions[childKey] = true
                        elseif exKey:sub(1, #fullKey + 1) == (fullKey .. ".") then
                            hasNested = true
                        end
                    end
                    if childExclusions then
                        -- Merge each sub-table, preserving excluded child keys
                        if type(dst[key]) ~= "table" then
                            dst[key] = {}
                        end
                        local dstContainer = dst[key]
                        for ck in pairs(dstContainer) do
                            if
                                val[ck] == nil
                                and not HoldsExclusion(exclusions, fullKey .. "." .. tostring(ck))
                            then
                                dstContainer[ck] = nil
                            end
                        end
                        for ck, cv in pairs(val) do
                            if type(cv) == "table" then
                                if type(dstContainer[ck]) ~= "table" then
                                    dstContainer[ck] = {}
                                end
                                local dstSub = dstContainer[ck]
                                local subPath = fullKey .. "." .. tostring(ck)
                                -- Exact paths below the wildcard (override-owned keys) are
                                -- excluded too, not only the wildcard child names.
                                for sk in pairs(dstSub) do
                                    if
                                        cv[sk] == nil
                                        and not childExclusions[tostring(sk)]
                                        and not HoldsExclusion(exclusions, subPath .. "." .. tostring(sk))
                                    then
                                        dstSub[sk] = nil
                                    end
                                end
                                for sk, sv in pairs(cv) do
                                    local leafPath = subPath .. "." .. tostring(sk)
                                    if not childExclusions[tostring(sk)] and not exclusions[leafPath] then
                                        if type(sv) == "table" and HoldsExclusion(exclusions, leafPath) then
                                            if type(dstSub[sk]) ~= "table" then
                                                dstSub[sk] = {}
                                            end
                                            CludesUI._SelectiveOverlay(
                                                sv,
                                                dstSub[sk],
                                                exclusions,
                                                deepCopy,
                                                leafPath
                                            )
                                        else
                                            dstSub[sk] = type(sv) == "table" and deepCopy(sv) or sv
                                        end
                                    end
                                end
                            else
                                dstContainer[ck] = cv
                            end
                        end
                    elseif hasNested then
                        if type(dst[key]) ~= "table" then
                            dst[key] = {}
                        end
                        CludesUI._SelectiveOverlay(val, dst[key], exclusions, deepCopy, fullKey)
                    else
                        dst[key] = deepCopy(val)
                    end
                else
                    dst[key] = val
                end
            end
        end
    end

    function CludesUI.IsProfileSynced(folder, profileName)
        if not CludesUIDB then
            return false
        end
        local sm = CludesUIDB.syncedModules
        if not sm or not sm[folder] then
            return false
        end
        local targets = sm[folder]
        return type(targets) == "table" and targets[profileName] == true
    end

    function CludesUI.GetSyncedProfiles(folder)
        if not CludesUIDB or not CludesUIDB.syncedModules then
            return {}
        end
        local targets = CludesUIDB.syncedModules[folder]
        if type(targets) == "table" then
            return targets
        end
        return {}
    end

    -- Check if ANY profile is synced for a module (for icon state)
    function CludesUI.IsModuleSynced(folder)
        if not CludesUIDB or not CludesUIDB.syncedModules then
            return false
        end
        local targets = CludesUIDB.syncedModules[folder]
        if type(targets) ~= "table" then
            return false
        end
        for _, val in pairs(targets) do
            if val then
                return true
            end
        end
        return false
    end

    -- Sync one module from active profile to specific target profiles
    function CludesUI.SyncModuleToProfiles(folder, targetProfiles)
        if not CludesUIDB or not CludesUIDB.profiles then
            return
        end
        local isActive = CludesUIDB.activeProfile or "Default"
        local source = CludesUIDB.profiles[isActive]
        if not source or not source.addons or not source.addons[folder] then
            return
        end
        local DeepCopy = CludesUI.Lite and CludesUI.Lite.DeepCopy
        if not DeepCopy then
            return
        end

        local staticEx = syncExclusions[folder]
        local exFn = CludesUI._SyncExclusionsWithOverrides
        for profName in pairs(targetProfiles) do
            if profName ~= isActive then
                local prof = CludesUIDB.profiles[profName]
                if prof then
                    if not prof.addons then
                        prof.addons = {}
                    end
                    -- Merge both profiles' override-entry paths into the static set
                    -- (fail-open: any derive error keeps static-only behavior).
                    local exclusions = staticEx
                    if exFn then
                        local success, m = pcall(exFn, folder, staticEx, source, prof)
                        if success and m then
                            exclusions = m
                        end
                    end
                    if exclusions and next(exclusions) then
                        local dst = prof.addons[folder]
                        if not dst then
                            -- First sync to this profile: no dest values to preserve
                            prof.addons[folder] = SelectiveCopy(source.addons[folder], exclusions)
                        else
                            -- Overlay leaf-by-leaf so excluded keys keep dest values
                            CludesUI._SelectiveOverlay(source.addons[folder], dst, exclusions, DeepCopy)
                        end
                    else
                        -- Full blob copy (no exclusions)
                        prof.addons[folder] = DeepCopy(source.addons[folder])
                    end
                end
            end
        end
    end

    -- Equalize a module across group members from an explicit source ("seed"). Non-active dests
    -- get a selective copy; an ACTIVE dest is written IN PLACE (live db.profile refs stay valid),
    -- defaults re-merged (stored blobs are sparse), then UI refreshed. Excluded (layout) keys keep each dest's values.
    function CludesUI.SyncModuleFromProfile(folder, srcName, targets)
        if not CludesUIDB or not CludesUIDB.profiles then
            return
        end
        local isActive = CludesUIDB.activeProfile or "Default"
        if srcName == isActive then
            CludesUI.SyncModuleToProfiles(folder, targets)
            return
        end
        local DeepCopy = CludesUI.Lite and CludesUI.Lite.DeepCopy
        if not DeepCopy then
            return
        end
        local srcProf = CludesUIDB.profiles[srcName]
        local srcData = srcProf and srcProf.addons and srcProf.addons[folder]
        if not srcData then
            return
        end

        local staticEx = syncExclusions[folder]
        local exFn = CludesUI._SyncExclusionsWithOverrides
        for profName in pairs(targets) do
            if profName ~= srcName then
                local prof = CludesUIDB.profiles[profName]
                if prof then
                    if not prof.addons then
                        prof.addons = {}
                    end
                    -- Same override-ownership exclusions as SyncModuleToProfiles.
                    local exclusions = staticEx
                    if exFn then
                        local success, m = pcall(exFn, folder, staticEx, srcProf, prof)
                        if success and m then
                            exclusions = m
                        end
                    end
                    local dst = prof.addons[folder]
                    if profName == isActive then
                        -- Live profile: adopt in place, never replace the table
                        if type(dst) ~= "table" then
                            dst = {}
                            prof.addons[folder] = dst
                        end
                        if exclusions and next(exclusions) then
                            CludesUI._SelectiveOverlay(srcData, dst, exclusions, DeepCopy)
                        else
                            wipe(dst)
                            for key, val in pairs(srcData) do
                                dst[key] = type(val) == "table" and DeepCopy(val) or val
                            end
                        end
                    elseif not (exclusions and next(exclusions)) then
                        prof.addons[folder] = DeepCopy(srcData)
                    elseif type(dst) == "table" then
                        CludesUI._SelectiveOverlay(srcData, dst, exclusions, DeepCopy)
                    else
                        prof.addons[folder] = SelectiveCopy(srcData, exclusions)
                    end
                end
            end
        end

        if targets[isActive] then
            -- Re-merge defaults into the adopted live table, then refresh addons and any open options page
            local reg = CludesUI.Lite._dbRegistry
            if reg then
                for _, rdb in ipairs(reg) do
                    if rdb.folder == folder then
                        if rdb._profileDefaults and rdb.profile then
                            CludesUI.Lite.DeepMergeDefaults(rdb.profile, rdb._profileDefaults)
                        end
                        break
                    end
                end
            end
            if CludesUI.RefreshAllAddons then
                CludesUI.RefreshAllAddons()
            end
            if CludesUI.RefreshPage then
                CludesUI:RefreshPage()
            end
        end
    end

    -- Pre-logout push to other group members. Only a MEMBER pushes; an outside
    -- profile must never overwrite member data regardless of what is active.
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if CludesUI.Lite and CludesUI.Lite.RegisterPreLogout then
            CludesUI.Lite.RegisterPreLogout(function()
                if not CludesUIDB or not CludesUIDB.syncedModules then
                    return
                end
                local isActive = CludesUIDB.activeProfile or "Default"
                for folder, targets in pairs(CludesUIDB.syncedModules) do
                    if type(targets) == "table" and targets[isActive] then
                        CludesUI.SyncModuleToProfiles(folder, targets)
                    end
                end
            end)
        end
    end)
end

-------------------------------------------------------------------------------
--  Sync Exclusions per Module -- keys listed here are NOT copied when syncing between profiles.
-------------------------------------------------------------------------------
CludesUI.RegisterSyncExclusions("CludesUIActionBars", {
    "barPositions",
    "bars.*.growDirection",
    "bars.*.orientation",
    "bars.*.buttonWidth",
    "bars.*.buttonHeight",
    "bars.*.targetWidth",
    "bars.*.targetHeight",
    "bars.*.width",
    "bars.*.height",
    "bars.*.overrideNumIcons",
    "bars.*.overrideNumRows",
    "bars.*.numIcons",
    "bars.*.numRows",
})

CludesUI.RegisterSyncExclusions("CludesUIUnitFrames", {
    "positions",
    "player.frameWidth",
    "player.healthHeight",
    "target.frameWidth",
    "target.healthHeight",
    "playerTarget.frameWidth",
    "playerTarget.healthHeight",
    "targettarget.frameWidth",
    "targettarget.healthHeight",
    "focustarget.frameWidth",
    "focustarget.healthHeight",
    "pet.frameWidth",
    "pet.healthHeight",
    "focus.frameWidth",
    "focus.healthHeight",
    "boss.frameWidth",
    "boss.healthHeight",
})

CludesUI.RegisterSyncExclusions("CludesUICooldownManager", {
    "cdmBarPositions",
    "cdmBars.bars.*.iconSize",
    "cdmBars.bars.*.numRows",
    "cdmBars.bars.*.anchorFirstRow",
    "cdmBars.bars.*.rowGrowDirection",
    "cdmBars.bars.*.spacing",
    "cdmBars.bars.*.verticalOrientation",
    "cdmBars.bars.*.anchorTo",
    "cdmBars.bars.*.anchorPosition",
    "cdmBars.bars.*.anchorOffsetX",
    "cdmBars.bars.*.anchorOffsetY",
    "cdmBars.bars.*.keybindOffsetX",
    "cdmBars.bars.*.keybindOffsetY",
    "cdmBars.bars.*.keybindAnchor",
    -- Rotation Assist Icon: unlock position, size and keybind placement
    "rotationAssistIcon.position",
    "rotationAssistIcon.iconSize",
    "rotationAssistIcon.keybindAnchor",
    "rotationAssistIcon.keybindOffsetX",
    "rotationAssistIcon.keybindOffsetY",
})

CludesUI.RegisterSyncExclusions("CludesUIResourceBars", {
    "health.width",
    "health.height",
    "health.offsetX",
    "health.offsetY",
    "health.orientation",
    "primary.width",
    "primary.height",
    "primary.offsetX",
    "primary.offsetY",
    "primary.orientation",
    "secondary.pipWidth",
    "secondary.pipHeight",
    "secondary.pipSpacing",
    "secondary.pipOrientation",
    "secondary.offsetX",
    "secondary.offsetY",
    "castBar.width",
    "castBar.height",
    "castBar.anchorX",
    "castBar.anchorY",
    "castBar.unlockPos",
    "totemBar.iconSize",
    "totemBar.spacing",
    "totemBar.unlockPos",
    "callTotemBar.iconSize",
    "callTotemBar.spacing",
    "callTotemBar.unlockPos",
    "general.anchorX",
    "general.anchorY",
    "general.orientation",
})

CludesUI.RegisterSyncExclusions("CludesUIAuraBuffReminders", {
    "unlockPos",
    "display.xOffset",
    "display.yOffset",
})

CludesUI.RegisterSyncExclusions("CludesUIRaidFrames", {
    "unlockPos",
})

CludesUI.RegisterSyncExclusions("CludesUIMythicTimer", {
    "standalonePos",
    "scale",
    "frameWidth",
})

-- Dragon Riding HUD position (unlockPos) stays per-profile on sync, like every module.
CludesUI.RegisterSyncExclusions("CludesUIDragonRiding", {
    "unlockPos",
})

-- QoL Secondary Stats/FPS positions, the cursor slice (GCD ring, cast circle, at
-- profile.cursor) and the Battle Res and Bloodlust positions stay per-profile on
-- sync: exported intact, never push-overwritten.
CludesUI.RegisterSyncExclusions("CludesUIQoL", {
    "secondaryStatsPos",
    "fpsPos",
    "cursor.gcd.pos",
    "cursor.castCircle.pos",
    "battleRes.pos",
    "bloodlust.pos",
})

-- Minimap settings nest under profile.minimap.
CludesUI.RegisterSyncExclusions("CludesUIMinimap", {
    "minimap.position", -- unlock-element drag position
    "minimap.btnPositions", -- per-button shift-drag offsets
})

-- Chat settings nest under profile.chat.
CludesUI.RegisterSyncExclusions("CludesUIChat", {
    "chat.chatPosition", -- unlock drag position
    "chat.chatScreenPoint", -- the screen point that position is measured from
    "chat.chatWidth", -- unlock resize-handle width
    "chat.chatHeight", -- unlock resize-handle height
    "chat.toastPosition", -- BNet toast unlock position
    "chat.iconPositions", -- per-sidebar-icon shift-drag offsets
})

-- Damage Meters settings nest under profile.dm.
CludesUI.RegisterSyncExclusions("CludesUIDamageMeters", {
    "dm.standaloneTimerPos", -- drag-written standalone timer position
    "dm.windows.*.position", -- per-window drag position
    "dm.windows.*.width", -- per-window drag-resize width
    "dm.windows.*.height", -- per-window drag-resize height
})

-- DataBars per-bar geometry lives in the top-level bars array (wildcard shape as ActionBars).
CludesUI.RegisterSyncExclusions("CludesUIDataBars", {
    "bars.*.savedPos", -- unlock drag position
    "bars.*.length", -- unlock resize owned
    "bars.*.thickness", -- unlock resize owned
    "bars.*.snapEdge", -- mutated by the drag save itself
})

-- Bags is the one auto-synced module: without this the bank position mirrors across profiles.
CludesUI.RegisterSyncExclusions("CludesUIBags", {
    "bankPosition", -- bank window drag position
})

-------------------------------------------------------------------------------
--  Sync Popup -- anchored flush to sidebar's right edge, centered on clicked sync icon,
--  clamped to the CUI window bottom.
-------------------------------------------------------------------------------
do
    local _syncPopup = nil

    function CludesUI.CloseSyncPopup()
        if _syncPopup then
            _syncPopup:Hide()
        end
        if CludesUI._syncConfirmFrame then
            CludesUI._syncConfirmFrame:Hide()
        end
    end

    -- Seed-picker confirm for create/update: user picks which member's settings the
    -- group starts from; after that first equalization the group is a mirror.
    function CludesUI._ShowSyncSeedConfirm(options)
        local fontFile = (CludesUI.GetFontPath and CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local Pix = CludesUI.PanelPP or CludesUI.PP
        local W, PAD = 360, 18

        if not CludesUI._syncConfirmFrame then
            -- Controller cursor: screen-level overlays hang off the overlay
            -- parent, which is UIParent unless a controller cursor is loaded.
            local overlayParent = CludesUI.OverlayParent()
            local nf = CreateFrame("Frame", nil, overlayParent)
            nf:SetFrameStrata("FULLSCREEN_DIALOG")
            -- Below 200: the shared dropdown menu (hardcoded level 200) must render above
            nf:SetFrameLevel(150)
            nf:EnableMouse(true)
            local backdrop = nf:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 1)
            nf._bg = backdrop
            -- Fullscreen dimmer: darkens and click-blocks everything behind
            local dim = CreateFrame("Frame", nil, overlayParent)
            dim:SetFrameStrata("FULLSCREEN_DIALOG")
            dim:SetFrameLevel(140)
            dim:SetAllPoints(UIParent)
            dim:EnableMouse(true)
            dim:Hide()
            local dimTex = dim:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.55)
            nf._dimmer = dim
            nf:SetScript("OnHide", function(self)
                self._dimmer:Hide()
            end)
            CludesUI._syncConfirmFrame = nf
            -- Controller cursor: the dimmer and the panel block what is under
            -- them without being stops.
            CludesUI.TrackOverlay(nf)
            CludesUI.TrackOverlay(dim)
            CludesUI.PadHint(nf, "nodepass")
            CludesUI.PadHint(dim, "nodepass")
        end
        local f = CludesUI._syncConfirmFrame

        local function MakeFont(hostFrame, size, r, g, b, a)
            local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(fontStr, true)
            end
            fontStr:SetFont(fontFile, size, "")
            fontStr:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fontStr
        end

        local function MakeBtn(labelText, r, g, b, a, hr, hg, hb)
            local button = CreateFrame("Button", nil, f)
            button:SetSize(120, 26)
            button:SetFrameLevel(f:GetFrameLevel() + 1)
            local bgT = button:CreateTexture(nil, "BACKGROUND")
            bgT:SetAllPoints()
            bgT:SetColorTexture(r, g, b, a)
            local labelFS = button:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(labelFS, false)
            end
            labelFS:SetFont(fontFile, 10, "")
            labelFS:SetTextColor(1, 1, 1, 1)
            labelFS:SetPoint("CENTER")
            labelFS:SetText(labelText)
            button:SetScript("OnEnter", function()
                bgT:SetColorTexture(hr, hg, hb, 1)
            end)
            button:SetScript("OnLeave", function()
                bgT:SetColorTexture(r, g, b, a)
            end)
            -- Back to rest (each show starts un-hovered), in the font path given.
            button._reset = function(fp)
                bgT:SetColorTexture(r, g, b, a)
                labelFS:SetFont(fp, 10, "")
            end
            return button
        end

        local DD_W = 190
        local DD_SCALE = 0.85
        local ddVisW = math.floor(DD_W * DD_SCALE + 0.5)
        local ddVisH = math.floor(30 * DD_SCALE + 0.5)

        -- The dropdown lists this call's members. Its values and order tables are the
        -- same ones every call, so the built control keeps reading them.
        local ui = f._ui
        local ddValues = ui and ui.ddValues or { _noLoc = true } -- profile names: never translate
        local ddOrder = ui and ui.ddOrder or {}
        local members = options.memberOrder
        local sameMembers = ui and #ddOrder == #members
        if sameMembers then
            for idx = 1, #members do
                if ddOrder[idx] ~= members[idx] then
                    sameMembers = false
                    break
                end
            end
        end
        if not sameMembers then
            wipe(ddValues)
            wipe(ddOrder)
            ddValues._noLoc = true
            for idx, name in ipairs(members) do
                ddOrder[idx] = name
                ddValues[name] = name
            end
        end

        -- Built once on the recycled frame; every call re-applies the font, texts,
        -- positions and the buttons' actions.
        if not ui then
            ui = { ddValues = ddValues, ddOrder = ddOrder }
            f._ui = ui
            if Pix then
                CludesUI.MakeRoundedBorder(f, 1, 1, 1, 0.15, f._bg)
            end
            ui.title = MakeFont(f, 14, 1, 1, 1, 0.9)
            ui.msg = MakeFont(f, 11, 1, 1, 1, 0.6)
            ui.msg:SetWidth(W - PAD * 2)
            ui.msg:SetJustifyH("CENTER")
            ui.ddLabel = MakeFont(f, 11, 1, 1, 1, 0.5)

            ui.seedChoice = options.defaultSeed
            local ddHolder = CreateFrame("Frame", nil, f)
            ddHolder:SetSize(ddVisW, ddVisH)
            ddHolder:SetFrameLevel(f:GetFrameLevel() + 1)
            local ddBtn = CludesUI.BuildDropdownControl(
                ddHolder,
                DD_W,
                ddHolder:GetFrameLevel() + 1,
                ddValues,
                ddOrder,
                function()
                    return ui.seedChoice
                end,
                function(val)
                    ui.seedChoice = val
                end
            )
            ddBtn:SetScale(DD_SCALE)
            ddBtn:SetPoint("TOPLEFT", ddHolder, "TOPLEFT", 0, 0)
            -- Menu is created lazily at UIParent scale; match it to the scaled button once it exists
            ddBtn:HookScript("OnClick", function(self)
                if self._ddMenu and self._ddMenu:GetScale() ~= DD_SCALE then
                    self._ddMenu:SetScale(DD_SCALE)
                end
            end)
            ui.ddHolder, ui.ddBtn = ddHolder, ddBtn

            ui.warn = MakeFont(f, 10, 0.92, 0.3, 0.3, 1)
            ui.warn:SetWidth(W - PAD * 2)
            ui.warn:SetJustifyH("CENTER")
            ui.warn:SetText(
                CludesUI.L("Position and size settings are not synced and keep each profile's own values.")
            )

            ui.cancelBtn = MakeBtn(CludesUI.L("Cancel"), 0.172, 0.164, 0.156, 0.9, 0.231, 0.222, 0.215)
            ui.confirmBtn = MakeBtn(CludesUI.L("Sync"), 0.05, 0.52, 0.39, 0.8, 0.07, 0.62, 0.49)
        else
            ui.seedChoice = options.defaultSeed
            if sameMembers then
                ui.ddBtn._refreshLabel()
            else
                -- The member list changed: the next click builds the menu from it.
                ui.ddBtn._invalidateMenu()
            end
        end

        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

        local cy = -PAD

        local title = ui.title
        title:SetFont(fontFile, 14, "")
        title:ClearAllPoints()
        title:SetPoint("TOP", f, "TOP", 0, cy)
        title:SetText(CludesUI.L(options.hadGroup and "Update Sync Group" or "Create Sync Group"))
        cy = cy - 22 - 8

        local msg = ui.msg
        msg:SetFont(fontFile, 11, "")
        msg:ClearAllPoints()
        msg:SetPoint("TOP", f, "TOP", 0, cy)
        msg:SetText(
            CludesUI.Lf(
                "All selected profiles will keep their %1$s settings in sync: changes made on any of them carry over to the others. Choose which profile's settings the group starts from.",
                CludesUI.L(options.displayName)
            )
        )
        cy = cy - (msg:GetStringHeight() or 42) - 14

        local ddLabel = ui.ddLabel
        ddLabel:SetFont(fontFile, 11, "")
        ddLabel:ClearAllPoints()
        ddLabel:SetPoint("TOP", f, "TOP", 0, cy)
        ddLabel:SetText(CludesUI.L("Sync settings from:"))
        cy = cy - 16 - 6

        ui.ddHolder:ClearAllPoints()
        ui.ddHolder:SetPoint("TOP", f, "TOP", 0, cy)
        cy = cy - ddVisH - 14

        local warn = ui.warn
        if options.hasWarning then
            warn:SetFont(fontFile, 10, "")
            warn:ClearAllPoints()
            warn:SetPoint("TOP", f, "TOP", 0, cy)
            warn:Show()
            cy = cy - (warn:GetStringHeight() or 26) - 14
        else
            warn:Hide()
        end

        local cancelBtn, confirmBtn = ui.cancelBtn, ui.confirmBtn
        cancelBtn._reset(fontFile)
        confirmBtn._reset(fontFile)
        cancelBtn:ClearAllPoints()
        cancelBtn:SetPoint("TOPRIGHT", f, "TOP", -6, cy)
        confirmBtn:ClearAllPoints()
        confirmBtn:SetPoint("TOPLEFT", f, "TOP", 6, cy)
        cy = cy - 26

        f:SetSize(W, -cy + PAD)

        confirmBtn:SetScript("OnClick", function()
            f:Hide()
            if not CludesUIDB.syncedModules then
                CludesUIDB.syncedModules = {}
            end
            CludesUIDB.syncedModules[options.folder] = options.targets
            local seedChoice = ui.seedChoice
            if seedChoice then
                CludesUI.SyncModuleFromProfile(options.folder, seedChoice, options.targets)
            end
            if options.onDone then
                options.onDone()
            end
        end)
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
            if options.onCancel then
                options.onCancel()
            end
        end)
        -- Controller cursor: its cancel press backs out through Cancel.
        if CludesUI.PadCP() then
            f.CloseButton = cancelBtn
        end

        f._dimmer:Show()
        f:Show()
        -- Controller cursor: start on the safe button.
        CludesUI.PadFocus(cancelBtn)
    end

    function CludesUI.OpenSyncPopup(folder, displayName, anchorBtn)
        if CludesUI._syncConfirmFrame then
            CludesUI._syncConfirmFrame:Hide()
        end
        -- Toggle off if already open for this module
        if _syncPopup and _syncPopup:IsShown() and _syncPopup._folder == folder then
            _syncPopup:Hide()
            return
        end

        if not CludesUIDB or not CludesUIDB.profiles then
            return
        end
        local isActive = CludesUIDB.activeProfile or "Default"
        local profileOrder = CludesUIDB.profileOrder or {}

        -- Full profile list, profileOrder first then stragglers (active included: groups are explicit membership)
        local allProfiles = {}
        for _, name in ipairs(profileOrder) do
            if CludesUIDB.profiles[name] then
                allProfiles[#allProfiles + 1] = name
            end
        end
        for name in pairs(CludesUIDB.profiles) do
            local found = false
            for _, num in ipairs(allProfiles) do
                if num == name then
                    found = true
                    break
                end
            end
            if not found then
                allProfiles[#allProfiles + 1] = name
            end
        end

        if #allProfiles <= 1 then
            if CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(anchorBtn, "No other profiles to sync to")
                C_Timer.After(1.5, function()
                    CludesUI.HideWidgetTooltip()
                end)
            end
            return
        end

        local MEDIA_PATH = "Interface\\AddOns\\CludesUI\\media\\"
        local fontFile = (CludesUI.GetFontPath and CludesUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
        local accentColor = CludesUI.ACCENT_COLOR or CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local Pix = CludesUI.PanelPP or CludesUI.PP

        local POPUP_W = 300
        local PAD = 16
        local ROW_H = 30
        local ROW_GAP = 2
        local HEADER_H = 26
        local WARN_MODULES = {
            CludesUIActionBars = true,
            CludesUIUnitFrames = true,
            CludesUICooldownManager = true,
            CludesUIResourceBars = true,
            CludesUIMythicTimer = true,
            CludesUIRaidFrames = true,
        }
        local hasWarning = WARN_MODULES[folder]
        local SUBTITLE_H = 30
        local popupH = PAD
            + HEADER_H
            + 7
            + SUBTITLE_H
            + 14
            + #allProfiles * (ROW_H + ROW_GAP)
            - ROW_GAP
            + 16
            + 30
            + PAD

        if not _syncPopup then
            -- Controller cursor: overlay parent (UIParent unless a controller cursor is loaded).
            _syncPopup = CreateFrame("Frame", nil, CludesUI.OverlayParent())
            _syncPopup:SetFrameStrata("FULLSCREEN_DIALOG")
            _syncPopup:SetFrameLevel(200)
            _syncPopup:EnableMouse(true)
            local backdrop = _syncPopup:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 1)
            _syncPopup._bg = backdrop
            -- Born hidden, so the Show below runs its OnShow (the click-away)
            -- on the first open too.
            _syncPopup:Hide()
            CludesUI.TrackOverlay(_syncPopup)
            CludesUI.PadHint(_syncPopup, "nodepass")
        end
        local dialog = _syncPopup
        dialog._folder = folder
        dialog:SetFrameLevel(200)

        dialog:SetSize(POPUP_W, popupH)
        -- The popup's border, header, profile rows (pooled by position) and action
        -- button are built once; every open re-applies their fonts, texts, colours,
        -- positions and actions.
        local ui = dialog._ui
        if not ui then
            ui = { rows = {} }
            dialog._ui = ui
            if Pix then
                CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, dialog._bg)
            end
        end

        -- Position: flush right of sidebar, centered on the sync icon, clamped
        local sidebar = CludesUI._sidebar
        local root = CludesUI._mainFrame
        if sidebar and anchorBtn then
            local btnMidY = select(2, anchorBtn:GetCenter()) or 0
            local sidebarMidY = select(2, sidebar:GetCenter()) or 0
            local offsetY = btnMidY - sidebarMidY
            -- Clamp to CUI window bottom
            if root then
                local rootBot = root:GetBottom() or 0
                local popupBot = btnMidY - popupH / 2
                if popupBot < rootBot then
                    offsetY = offsetY + (rootBot - popupBot)
                end
            end
            dialog:ClearAllPoints()
            dialog:SetPoint("LEFT", sidebar, "RIGHT", 0, offsetY)
        else
            dialog:ClearAllPoints()
            dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end

        local function MakeFont(hostFrame, size, r, g, b, a)
            local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(fontStr, true)
            end
            fontStr:SetFont(fontFile, size, "")
            fontStr:SetTextColor(r or 1, g or 1, b or 1, a or 1)
            return fontStr
        end

        local cy = -PAD

        -- Header: sync icon (left), title (centered), close X (right)
        if not ui.iconTex then
            local iconTex = dialog:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(19, 19)
            iconTex:SetTexture(MEDIA_PATH .. "icons\\linked.png")
            ui.iconTex = iconTex
            ui.title = MakeFont(dialog, 14, 1, 1, 1, 0.9)
            local subtitle = MakeFont(dialog, 10, 1, 1, 1, 0.45)
            subtitle:SetWidth(POPUP_W - PAD * 2)
            subtitle:SetJustifyH("CENTER")
            subtitle:SetText(
                CludesUI.L(
                    "Syncing allows you to auto update all profiles whenever you change settings. This can be enabled per module."
                )
            )
            ui.subtitle = subtitle
        end
        local iconTex = ui.iconTex
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD - 1, cy + 1)
        -- Accent when this module has an active sync group, gray otherwise
        if CludesUI.IsModuleSynced(folder) then
            iconTex:SetVertexColor(accentColor.r, accentColor.g, accentColor.b, 1)
        else
            iconTex:SetVertexColor(0.55, 0.55, 0.55, 1)
        end

        local title = ui.title
        title:SetFont(fontFile, 14, "")
        title:ClearAllPoints()
        title:SetPoint("TOP", dialog, "TOP", 0, cy - 1)
        title:SetText(CludesUI.Lf("%1$s Sync", CludesUI.L(displayName)))
        cy = cy - HEADER_H - 7

        local subtitle = ui.subtitle
        subtitle:SetFont(fontFile, 10, "")
        subtitle:ClearAllPoints()
        subtitle:SetPoint("TOP", dialog, "TOP", 0, cy)
        cy = cy - SUBTITLE_H - 14

        -- Toggle rows for every profile (the active one included)
        local currentSynced = CludesUI.GetSyncedProfiles(folder)
        local toggleState = {}
        local hadGroup = next(currentSynced) ~= nil
        local refreshSyncBtnLabel -- defined with the button below
        -- The pooled rows' toggles and clicks read and write this open's state.
        dialog._toggleState = toggleState
        dialog._refreshLabel = nil

        local accentHex = string.format(
            "%02x%02x%02x",
            math.floor(accentColor.r * 255 + 0.5),
            math.floor(accentColor.g * 255 + 0.5),
            math.floor(accentColor.b * 255 + 0.5)
        )

        local BuildToggleControl = CludesUI.BuildToggleControl
        local rowList = ui.rows
        for idx, profName in ipairs(allProfiles) do
            local isSynced = currentSynced[profName] == true
            toggleState[profName] = isSynced

            -- Card-style row: label left, toggle right, whole row clickable
            local row = rowList[idx]
            if not row then
                row = CreateFrame("Button", nil, dialog)
                row:SetFrameLevel(dialog:GetFrameLevel() + 1)
                local rowBg = row:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(1, 1, 1, 0.05)
                row._bg = rowBg
                row._profName = profName

                local tg, _, tgSnap = BuildToggleControl(row, row:GetFrameLevel() + 1, function()
                    return dialog._toggleState[row._profName]
                end, function(val)
                    dialog._toggleState[row._profName] = val
                    if dialog._refreshLabel then
                        dialog._refreshLabel()
                    end
                end, { sizeRatio = 0.75 })
                tg:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                row._tg, row._tgSnap = tg, tgSnap

                row:SetScript("OnClick", function(self)
                    local status = dialog._toggleState
                    status[self._profName] = not status[self._profName]
                    self._tgSnap()
                    if dialog._refreshLabel then
                        dialog._refreshLabel()
                    end
                end)
                row:SetScript("OnEnter", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.08)
                end)
                row:SetScript("OnLeave", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.05)
                end)
                -- Toggle hover fires the row's OnLeave (child frame); keep the card lit
                tg:HookScript("OnEnter", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.08)
                end)
                tg:HookScript("OnLeave", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.05)
                end)

                local lblText = MakeFont(row, 12, 1, 1, 1, 0.85)
                lblText:SetPoint("LEFT", row, "LEFT", 10, 0)
                row._lbl = lblText
                rowList[idx] = row
            end
            row._profName = profName
            row:SetSize(POPUP_W - PAD * 2, ROW_H)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, cy)
            row:SetFrameLevel(dialog:GetFrameLevel() + 1)
            row._tg:SetFrameLevel(row:GetFrameLevel() + 1)
            row._bg:SetColorTexture(1, 1, 1, 0.05)
            row._tgSnap()
            row:Show()

            local lblText = row._lbl
            lblText:SetFont(fontFile, 12, "")
            if profName == isActive then
                lblText:SetText(profName .. " |cff" .. accentHex .. "(active)|r")
            else
                lblText:SetText(profName)
            end

            cy = cy - ROW_H - ROW_GAP
        end
        for idx = #allProfiles + 1, #rowList do
            rowList[idx]:Hide()
        end

        cy = cy - (16 - ROW_GAP)

        -- Action button: full-width accent outline; label tracks the toggle state
        if not ui.syncBtn then
            local syncBtn = CreateFrame("Button", nil, dialog)
            syncBtn:SetFrameLevel(dialog:GetFrameLevel() + 1)
            local sBg = syncBtn:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            local sBrd
            if Pix then
                sBrd =
                    CludesUI.MakeRoundedBorder(syncBtn, accentColor.r, accentColor.g, accentColor.b, 0.7, sBg)
            end
            local sLbl = syncBtn:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(sLbl, false)
            end
            sLbl:SetPoint("CENTER")
            ui.syncBtn, ui.sBg, ui.sBrd, ui.sLbl = syncBtn, sBg, sBrd, sLbl
        end
        local syncBtn, sBg, sBrd, sLbl = ui.syncBtn, ui.sBg, ui.sBrd, ui.sLbl
        syncBtn:SetSize(POPUP_W - PAD * 2, 30)
        syncBtn:ClearAllPoints()
        syncBtn:SetPoint("TOP", dialog, "TOP", 0, cy)
        syncBtn:SetFrameLevel(dialog:GetFrameLevel() + 1)
        sLbl:SetFont(fontFile, 11, "")

        -- Grayed out until the toggles actually differ from the saved group
        local function ApplyBtnState(dirty)
            syncBtn._dirty = dirty
            if dirty then
                sBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.08)
                if sBrd then
                    sBrd:SetColor(accentColor.r, accentColor.g, accentColor.b, 0.7)
                end
                sLbl:SetTextColor(accentColor.r, accentColor.g, accentColor.b, 1)
            else
                sBg:SetColorTexture(1, 1, 1, 0.03)
                if sBrd then
                    sBrd:SetColor(1, 1, 1, 0.15)
                end
                sLbl:SetTextColor(1, 1, 1, 0.35)
            end
        end
        syncBtn:SetScript("OnEnter", function()
            if not syncBtn._dirty then
                return
            end
            sBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.18)
        end)
        syncBtn:SetScript("OnLeave", function()
            ApplyBtnState(syncBtn._dirty)
        end)

        refreshSyncBtnLabel = function()
            local total = 0
            local dirty = false
            for profName, val in pairs(toggleState) do
                if val then
                    total = total + 1
                end
                if val ~= (currentSynced[profName] == true) then
                    dirty = true
                end
            end
            if hadGroup and total == 0 then
                sLbl:SetText(CludesUI.L("Disband Sync Group"))
            elseif hadGroup then
                sLbl:SetText(CludesUI.L("Update Sync Group"))
            else
                sLbl:SetText(CludesUI.L("Create Sync Group"))
            end
            ApplyBtnState(dirty)
        end
        dialog._refreshLabel = refreshSyncBtnLabel
        refreshSyncBtnLabel()

        local function RefreshSidebarSyncIcon()
            local sidebarBtns = CUI_NS.sidebarButtons
            if sidebarBtns and sidebarBtns[folder] and sidebarBtns[folder]._syncBtn then
                local scrollBar = sidebarBtns[folder]._syncBtn
                if scrollBar._refreshAlpha then
                    scrollBar._refreshAlpha()
                end
            end
        end

        syncBtn:SetScript("OnClick", function()
            if not syncBtn._dirty then
                return
            end
            -- The group is exactly the toggled-on profiles
            local targets = {}
            local total = 0
            local anyNew = false
            for profName, checked in pairs(toggleState) do
                if checked then
                    targets[profName] = true
                    total = total + 1
                    if not currentSynced[profName] then
                        anyNew = true
                    end
                end
            end

            if total == 0 then
                -- Disband (or nothing was ever configured)
                if not CludesUIDB.syncedModules then
                    CludesUIDB.syncedModules = {}
                end
                CludesUIDB.syncedModules[folder] = {}
                dialog:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            if total == 1 then
                if CludesUI.ShowWidgetTooltip then
                    CludesUI.ShowWidgetTooltip(syncBtn, "A sync group needs at least two profiles")
                    C_Timer.After(1.5, function()
                        CludesUI.HideWidgetTooltip()
                    end)
                end
                return
            end

            if not anyNew then
                -- Pure removal / no change: nothing overwritten, save without confirmation
                if not CludesUIDB.syncedModules then
                    CludesUIDB.syncedModules = {}
                end
                CludesUIDB.syncedModules[folder] = targets
                dialog:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            -- New members joining: confirm with a seed picker; default = an existing member
            -- on update (newcomers adopt group settings), active on create.
            local memberOrder = {}
            for _, name in ipairs(allProfiles) do
                if targets[name] then
                    memberOrder[#memberOrder + 1] = name
                end
            end
            local defaultSeed
            if hadGroup then
                for _, name in ipairs(memberOrder) do
                    if currentSynced[name] then
                        defaultSeed = name
                        break
                    end
                end
            end
            if not defaultSeed then
                defaultSeed = targets[isActive] and isActive or memberOrder[1]
            end

            dialog:SetFrameLevel(90)
            dialog:SetScript("OnUpdate", nil)
            CludesUI._ShowSyncSeedConfirm({
                folder = folder,
                displayName = displayName,
                targets = targets,
                memberOrder = memberOrder,
                defaultSeed = defaultSeed,
                hadGroup = hadGroup,
                hasWarning = hasWarning,
                active = isActive,
                onDone = function()
                    dialog:Hide()
                    RefreshSidebarSyncIcon()
                end,
                onCancel = function()
                    dialog:Hide()
                end,
            })
        end)

        -- Click-off to close (OnUpdate poll like CC popups)
        dialog:SetScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(self2)
                if IsMouseButtonDown("LeftButton") then
                    if not self2:IsMouseOver() and not (anchorBtn and anchorBtn:IsMouseOver()) then
                        self2:Hide()
                    end
                end
            end)
        end)
        dialog:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        -- Controller cursor: its cancel press clicks the sync icon, which
        -- toggles this popup off.
        if CludesUI.PadCP() then
            dialog.CloseButton = anchorBtn
        end
        dialog:Show()
        -- Controller cursor: move it into the popup (its first row).
        CludesUI.PadFocus(dialog)
    end
end
