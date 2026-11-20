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

    function CludesUI.RegisterSyncExclusions(moduleFolder, keyList)
        if not syncExclusions[moduleFolder] then
            syncExclusions[moduleFolder] = {}
        end
        local ex = syncExclusions[moduleFolder]
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
    CludesUI._SyncExclusionsWithOverrides = function(moduleFolder, staticEx, srcProf, dstProf)
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
                                    if f == moduleFolder and filePath and filePath ~= "" then
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
        local function addProf(profileTbl)
            if type(profileTbl) ~= "table" then
                return
            end
            addStore(profileTbl.specOverrides)
            addStore(profileTbl.condOverrides)
            if moduleFolder == "CludesUIRaidFrames" then
                -- BM forks are layer-shaped, not fkey-shaped: the fork system writes
                -- bmIndicators/bmSimple/bmDisplayMode/bmIconZoom straight into the live RF blob,
                -- so if EITHER profile carries ANY BM layer, those keys are fork territory and
                -- must not sync (emptiness check mirrors the BM harvest's zero-cost gate).
                local s, c = profileTbl.specBmOverrides, profileTbl.condBmOverrides
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
                local ds, dc = profileTbl.specDmOverrides, profileTbl.condDmOverrides
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
    local function SelectiveCopy(source, excluded, parentPath)
        if type(source) ~= "table" then
            return source
        end
        local copy = {}
        for key, val in pairs(source) do
            local keyStr = tostring(key)
            local qualifiedKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not excluded[qualifiedKey] then
                if type(val) == "table" then
                    -- Wildcard parent check (e.g. "bars" in "bars.*.X")
                    local isWildcardParent = false
                    local childExcluded = nil
                    for exKey in pairs(excluded) do
                        local prefixText, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (a bare-name collision is not a wildcard parent)
                        if prefixText and qualifiedKey == prefixText then
                            isWildcardParent = true
                            if not childExcluded then
                                childExcluded = {}
                            end
                            childExcluded[childKey] = true
                        end
                    end
                    if isWildcardParent and childExcluded then
                        -- Copy the container but apply child exclusions to each sub-table
                        local containerCopy = {}
                        for childKey, cv in pairs(val) do
                            if type(cv) == "table" then
                                local subCopy = {}
                                local subPath = qualifiedKey .. "." .. tostring(childKey)
                                for syncKey, savedVars in pairs(cv) do
                                    local leafPath = subPath .. "." .. tostring(syncKey)
                                    if not childExcluded[tostring(syncKey)] and not excluded[leafPath] then
                                        if type(savedVars) == "table" then
                                            subCopy[syncKey] = SelectiveCopy(savedVars, excluded, leafPath)
                                        else
                                            subCopy[syncKey] = savedVars
                                        end
                                    end
                                end
                                containerCopy[childKey] = subCopy
                            else
                                containerCopy[childKey] = cv
                            end
                        end
                        copy[key] = containerCopy
                    else
                        copy[key] = SelectiveCopy(val, excluded, qualifiedKey)
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
    local function HoldsExclusion(excluded, qualifiedKey)
        if excluded[qualifiedKey] then
            return true
        end
        local pre = qualifiedKey .. "."
        for exKey in pairs(excluded) do
            if exKey:sub(1, #pre) == pre then
                return true
            end
        end
        return false
    end

    -- Exclusion-aware deep overlay for destinations with existing data: writes src into dst
    -- leaf-by-leaf wherever an exclusion path (flat/dotted/wildcard) touches the subtree, so
    -- excluded keys keep dest values (replacing a parent whole would delete them).
    function CludesUI._SelectiveOverlay(source, destination, excluded, deepCopy, parentPath)
        -- Mirror deletions, as the full copy does: drop dest keys the source no
        -- longer has, unless they hold excluded data.
        for key in pairs(destination) do
            if source[key] == nil then
                local qualifiedKey = parentPath and (parentPath .. "." .. tostring(key)) or tostring(key)
                if not HoldsExclusion(excluded, qualifiedKey) then
                    destination[key] = nil
                end
            end
        end
        for key, val in pairs(source) do
            local keyStr = tostring(key)
            local qualifiedKey = parentPath and (parentPath .. "." .. keyStr) or keyStr
            if not excluded[qualifiedKey] then
                if type(val) == "table" then
                    -- Wildcard parent and/or dotted exclusions deeper in this subtree
                    local childExcluded = nil
                    local hasNested = false
                    for exKey in pairs(excluded) do
                        local prefixText, childKey = exKey:match("^(.-)%.%*%.(.+)$")
                        -- Full-path match only (same rule as SelectiveCopy)
                        if prefixText and qualifiedKey == prefixText then
                            if not childExcluded then
                                childExcluded = {}
                            end
                            childExcluded[childKey] = true
                        elseif exKey:sub(1, #qualifiedKey + 1) == (qualifiedKey .. ".") then
                            hasNested = true
                        end
                    end
                    if childExcluded then
                        -- Merge each sub-table, preserving excluded child keys
                        if type(destination[key]) ~= "table" then
                            destination[key] = {}
                        end
                        local dstContainer = destination[key]
                        for childKey in pairs(dstContainer) do
                            if
                                val[childKey] == nil
                                and not HoldsExclusion(excluded, qualifiedKey .. "." .. tostring(childKey))
                            then
                                dstContainer[childKey] = nil
                            end
                        end
                        for childKey, cv in pairs(val) do
                            if type(cv) == "table" then
                                if type(dstContainer[childKey]) ~= "table" then
                                    dstContainer[childKey] = {}
                                end
                                local dstSub = dstContainer[childKey]
                                local subPath = qualifiedKey .. "." .. tostring(childKey)
                                -- Exact paths below the wildcard (override-owned keys) are
                                -- excluded too, not only the wildcard child names.
                                for syncKey in pairs(dstSub) do
                                    if
                                        cv[syncKey] == nil
                                        and not childExcluded[tostring(syncKey)]
                                        and not HoldsExclusion(excluded, subPath .. "." .. tostring(syncKey))
                                    then
                                        dstSub[syncKey] = nil
                                    end
                                end
                                for syncKey, savedVars in pairs(cv) do
                                    local leafPath = subPath .. "." .. tostring(syncKey)
                                    if not childExcluded[tostring(syncKey)] and not excluded[leafPath] then
                                        if type(savedVars) == "table" and HoldsExclusion(excluded, leafPath) then
                                            if type(dstSub[syncKey]) ~= "table" then
                                                dstSub[syncKey] = {}
                                            end
                                            CludesUI._SelectiveOverlay(
                                                savedVars,
                                                dstSub[syncKey],
                                                excluded,
                                                deepCopy,
                                                leafPath
                                            )
                                        else
                                            dstSub[syncKey] = type(savedVars) == "table" and deepCopy(savedVars) or savedVars
                                        end
                                    end
                                end
                            else
                                dstContainer[childKey] = cv
                            end
                        end
                    elseif hasNested then
                        if type(destination[key]) ~= "table" then
                            destination[key] = {}
                        end
                        CludesUI._SelectiveOverlay(val, destination[key], excluded, deepCopy, qualifiedKey)
                    else
                        destination[key] = deepCopy(val)
                    end
                else
                    destination[key] = val
                end
            end
        end
    end

    function CludesUI.IsProfileSynced(moduleFolder, profileName)
        if not CludesUIDB then
            return false
        end
        local sm = CludesUIDB.syncedModules
        if not sm or not sm[moduleFolder] then
            return false
        end
        local syncTargets = sm[moduleFolder]
        return type(syncTargets) == "table" and syncTargets[profileName] == true
    end

    function CludesUI.GetSyncedProfiles(moduleFolder)
        if not CludesUIDB or not CludesUIDB.syncedModules then
            return {}
        end
        local syncTargets = CludesUIDB.syncedModules[moduleFolder]
        if type(syncTargets) == "table" then
            return syncTargets
        end
        return {}
    end

    -- Check if ANY profile is synced for a module (for icon state)
    function CludesUI.IsModuleSynced(moduleFolder)
        if not CludesUIDB or not CludesUIDB.syncedModules then
            return false
        end
        local syncTargets = CludesUIDB.syncedModules[moduleFolder]
        if type(syncTargets) ~= "table" then
            return false
        end
        for _, val in pairs(syncTargets) do
            if val then
                return true
            end
        end
        return false
    end

    -- Sync one module from active profile to specific target profiles
    function CludesUI.SyncModuleToProfiles(moduleFolder, targetProfiles)
        if not CludesUIDB or not CludesUIDB.profiles then
            return
        end
        local isActive = CludesUIDB.activeProfile or "Default"
        local source = CludesUIDB.profiles[isActive]
        if not source or not source.addons or not source.addons[moduleFolder] then
            return
        end
        local DeepCopy = CludesUI.Lite and CludesUI.Lite.DeepCopy
        if not DeepCopy then
            return
        end

        local staticEx = syncExclusions[moduleFolder]
        local exFn = CludesUI._SyncExclusionsWithOverrides
        for profileName in pairs(targetProfiles) do
            if profileName ~= isActive then
                local profileTbl = CludesUIDB.profiles[profileName]
                if profileTbl then
                    if not profileTbl.addons then
                        profileTbl.addons = {}
                    end
                    -- Merge both profiles' override-entry paths into the static set
                    -- (fail-open: any derive error keeps static-only behavior).
                    local excluded = staticEx
                    if exFn then
                        local success, m = pcall(exFn, moduleFolder, staticEx, source, profileTbl)
                        if success and m then
                            excluded = m
                        end
                    end
                    if excluded and next(excluded) then
                        local destination = profileTbl.addons[moduleFolder]
                        if not destination then
                            -- First sync to this profile: no dest values to preserve
                            profileTbl.addons[moduleFolder] = SelectiveCopy(source.addons[moduleFolder], excluded)
                        else
                            -- Overlay leaf-by-leaf so excluded keys keep dest values
                            CludesUI._SelectiveOverlay(source.addons[moduleFolder], destination, excluded, DeepCopy)
                        end
                    else
                        -- Full blob copy (no exclusions)
                        profileTbl.addons[moduleFolder] = DeepCopy(source.addons[moduleFolder])
                    end
                end
            end
        end
    end

    -- Equalize a module across group members from an explicit source ("seed"). Non-active dests
    -- get a selective copy; an ACTIVE dest is written IN PLACE (live db.profile refs stay valid),
    -- defaults re-merged (stored blobs are sparse), then UI refreshed. Excluded (layout) keys keep each dest's values.
    function CludesUI.SyncModuleFromProfile(moduleFolder, srcName, syncTargets)
        if not CludesUIDB or not CludesUIDB.profiles then
            return
        end
        local isActive = CludesUIDB.activeProfile or "Default"
        if srcName == isActive then
            CludesUI.SyncModuleToProfiles(moduleFolder, syncTargets)
            return
        end
        local DeepCopy = CludesUI.Lite and CludesUI.Lite.DeepCopy
        if not DeepCopy then
            return
        end
        local srcProf = CludesUIDB.profiles[srcName]
        local srcData = srcProf and srcProf.addons and srcProf.addons[moduleFolder]
        if not srcData then
            return
        end

        local staticEx = syncExclusions[moduleFolder]
        local exFn = CludesUI._SyncExclusionsWithOverrides
        for profileName in pairs(syncTargets) do
            if profileName ~= srcName then
                local profileTbl = CludesUIDB.profiles[profileName]
                if profileTbl then
                    if not profileTbl.addons then
                        profileTbl.addons = {}
                    end
                    -- Same override-ownership exclusions as SyncModuleToProfiles.
                    local excluded = staticEx
                    if exFn then
                        local success, m = pcall(exFn, moduleFolder, staticEx, srcProf, profileTbl)
                        if success and m then
                            excluded = m
                        end
                    end
                    local destination = profileTbl.addons[moduleFolder]
                    if profileName == isActive then
                        -- Live profile: adopt in place, never replace the table
                        if type(destination) ~= "table" then
                            destination = {}
                            profileTbl.addons[moduleFolder] = destination
                        end
                        if excluded and next(excluded) then
                            CludesUI._SelectiveOverlay(srcData, destination, excluded, DeepCopy)
                        else
                            wipe(destination)
                            for key, val in pairs(srcData) do
                                destination[key] = type(val) == "table" and DeepCopy(val) or val
                            end
                        end
                    elseif not (excluded and next(excluded)) then
                        profileTbl.addons[moduleFolder] = DeepCopy(srcData)
                    elseif type(destination) == "table" then
                        CludesUI._SelectiveOverlay(srcData, destination, excluded, DeepCopy)
                    else
                        profileTbl.addons[moduleFolder] = SelectiveCopy(srcData, excluded)
                    end
                end
            end
        end

        if syncTargets[isActive] then
            -- Re-merge defaults into the adopted live table, then refresh addons and any open options page
            local reg = CludesUI.Lite._dbRegistry
            if reg then
                for _, rdb in ipairs(reg) do
                    if rdb.folder == moduleFolder then
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
                for moduleFolder, syncTargets in pairs(CludesUIDB.syncedModules) do
                    if type(syncTargets) == "table" and syncTargets[isActive] then
                        CludesUI.SyncModuleToProfiles(moduleFolder, syncTargets)
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
            local noteFrame = CreateFrame("Frame", nil, overlayParent)
            noteFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            -- Below 200: the shared dropdown menu (hardcoded level 200) must render above
            noteFrame:SetFrameLevel(150)
            noteFrame:EnableMouse(true)
            local backdrop = noteFrame:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 1)
            noteFrame._bg = backdrop
            -- Fullscreen dimmer: darkens and click-blocks everything behind
            local dimmer = CreateFrame("Frame", nil, overlayParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetFrameLevel(140)
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.55)
            noteFrame._dimmer = dimmer
            noteFrame:SetScript("OnHide", function(self)
                self._dimmer:Hide()
            end)
            CludesUI._syncConfirmFrame = noteFrame
            -- Controller cursor: the dimmer and the panel block what is under
            -- them without being stops.
            CludesUI.TrackOverlay(noteFrame)
            CludesUI.TrackOverlay(dimmer)
            CludesUI.PadHint(noteFrame, "nodepass")
            CludesUI.PadHint(dimmer, "nodepass")
        end
        local frame = CludesUI._syncConfirmFrame

        local function MakeFont(hostFrame, size, red, green, blue, a)
            local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(fontStr, true)
            end
            fontStr:SetFont(fontFile, size, "")
            fontStr:SetTextColor(red or 1, green or 1, blue or 1, a or 1)
            return fontStr
        end

        local function MakeBtn(labelText, red, green, blue, a, hr, hg, hb)
            local button = CreateFrame("Button", nil, frame)
            button:SetSize(120, 26)
            button:SetFrameLevel(frame:GetFrameLevel() + 1)
            local bgT = button:CreateTexture(nil, "BACKGROUND")
            bgT:SetAllPoints()
            bgT:SetColorTexture(red, green, blue, a)
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
                bgT:SetColorTexture(red, green, blue, a)
            end)
            -- Back to rest (each show starts un-hovered), in the font path given.
            button._reset = function(fp)
                bgT:SetColorTexture(red, green, blue, a)
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
        local parts = frame._ui
        local ddValues = parts and parts.ddValues or { _noLoc = true } -- profile names: never translate
        local ddOrder = parts and parts.ddOrder or {}
        local members = options.memberOrder
        local sameMembers = parts and #ddOrder == #members
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
        if not parts then
            parts = { ddValues = ddValues, ddOrder = ddOrder }
            frame._ui = parts
            if Pix then
                CludesUI.MakeRoundedBorder(frame, 1, 1, 1, 0.15, frame._bg)
            end
            parts.title = MakeFont(frame, 14, 1, 1, 1, 0.9)
            parts.msg = MakeFont(frame, 11, 1, 1, 1, 0.6)
            parts.msg:SetWidth(W - PAD * 2)
            parts.msg:SetJustifyH("CENTER")
            parts.ddLabel = MakeFont(frame, 11, 1, 1, 1, 0.5)

            parts.seedChoice = options.defaultSeed
            local ddHolder = CreateFrame("Frame", nil, frame)
            ddHolder:SetSize(ddVisW, ddVisH)
            ddHolder:SetFrameLevel(frame:GetFrameLevel() + 1)
            local ddBtn = CludesUI.BuildDropdownControl(
                ddHolder,
                DD_W,
                ddHolder:GetFrameLevel() + 1,
                ddValues,
                ddOrder,
                function()
                    return parts.seedChoice
                end,
                function(val)
                    parts.seedChoice = val
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
            parts.ddHolder, parts.ddBtn = ddHolder, ddBtn

            parts.warn = MakeFont(frame, 10, 0.92, 0.3, 0.3, 1)
            parts.warn:SetWidth(W - PAD * 2)
            parts.warn:SetJustifyH("CENTER")
            parts.warn:SetText(
                CludesUI.L("Position and size settings are not synced and keep each profile's own values.")
            )

            parts.cancelBtn = MakeBtn(CludesUI.L("Cancel"), 0.172, 0.164, 0.156, 0.9, 0.231, 0.222, 0.215)
            parts.confirmBtn = MakeBtn(CludesUI.L("Sync"), 0.05, 0.52, 0.39, 0.8, 0.07, 0.62, 0.49)
        else
            parts.seedChoice = options.defaultSeed
            if sameMembers then
                parts.ddBtn._refreshLabel()
            else
                -- The member list changed: the next click builds the menu from it.
                parts.ddBtn._invalidateMenu()
            end
        end

        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)

        local rowY = -PAD

        local title = parts.title
        title:SetFont(fontFile, 14, "")
        title:ClearAllPoints()
        title:SetPoint("TOP", frame, "TOP", 0, rowY)
        title:SetText(CludesUI.L(options.hadGroup and "Update Sync Group" or "Create Sync Group"))
        rowY = rowY - 22 - 8

        local msg = parts.msg
        msg:SetFont(fontFile, 11, "")
        msg:ClearAllPoints()
        msg:SetPoint("TOP", frame, "TOP", 0, rowY)
        msg:SetText(
            CludesUI.Lf(
                "All selected profiles will keep their %1$s settings in sync: changes made on any of them carry over to the others. Choose which profile's settings the group starts from.",
                CludesUI.L(options.displayName)
            )
        )
        rowY = rowY - (msg:GetStringHeight() or 42) - 14

        local ddLabel = parts.ddLabel
        ddLabel:SetFont(fontFile, 11, "")
        ddLabel:ClearAllPoints()
        ddLabel:SetPoint("TOP", frame, "TOP", 0, rowY)
        ddLabel:SetText(CludesUI.L("Sync settings from:"))
        rowY = rowY - 16 - 6

        parts.ddHolder:ClearAllPoints()
        parts.ddHolder:SetPoint("TOP", frame, "TOP", 0, rowY)
        rowY = rowY - ddVisH - 14

        local warn = parts.warn
        if options.hasWarning then
            warn:SetFont(fontFile, 10, "")
            warn:ClearAllPoints()
            warn:SetPoint("TOP", frame, "TOP", 0, rowY)
            warn:Show()
            rowY = rowY - (warn:GetStringHeight() or 26) - 14
        else
            warn:Hide()
        end

        local cancelBtn, confirmBtn = parts.cancelBtn, parts.confirmBtn
        cancelBtn._reset(fontFile)
        confirmBtn._reset(fontFile)
        cancelBtn:ClearAllPoints()
        cancelBtn:SetPoint("TOPRIGHT", frame, "TOP", -6, rowY)
        confirmBtn:ClearAllPoints()
        confirmBtn:SetPoint("TOPLEFT", frame, "TOP", 6, rowY)
        rowY = rowY - 26

        frame:SetSize(W, -rowY + PAD)

        confirmBtn:SetScript("OnClick", function()
            frame:Hide()
            if not CludesUIDB.syncedModules then
                CludesUIDB.syncedModules = {}
            end
            CludesUIDB.syncedModules[options.folder] = options.targets
            local seedChoice = parts.seedChoice
            if seedChoice then
                CludesUI.SyncModuleFromProfile(options.folder, seedChoice, options.targets)
            end
            if options.onDone then
                options.onDone()
            end
        end)
        cancelBtn:SetScript("OnClick", function()
            frame:Hide()
            if options.onCancel then
                options.onCancel()
            end
        end)
        -- Controller cursor: its cancel press backs out through Cancel.
        if CludesUI.PadCP() then
            frame.CloseButton = cancelBtn
        end

        frame._dimmer:Show()
        frame:Show()
        -- Controller cursor: start on the safe button.
        CludesUI.PadFocus(cancelBtn)
    end

    function CludesUI.OpenSyncPopup(moduleFolder, displayName, anchorBtn)
        if CludesUI._syncConfirmFrame then
            CludesUI._syncConfirmFrame:Hide()
        end
        -- Toggle off if already open for this module
        if _syncPopup and _syncPopup:IsShown() and _syncPopup._folder == moduleFolder then
            _syncPopup:Hide()
            return
        end

        if not CludesUIDB or not CludesUIDB.profiles then
            return
        end
        local isActive = CludesUIDB.activeProfile or "Default"
        local profileOrder = CludesUIDB.profileOrder or {}

        -- Full profile list, profileOrder first then stragglers (active included: groups are explicit membership)
        local profileNames = {}
        for _, name in ipairs(profileOrder) do
            if CludesUIDB.profiles[name] then
                profileNames[#profileNames + 1] = name
            end
        end
        for name in pairs(CludesUIDB.profiles) do
            local found = false
            for _, num in ipairs(profileNames) do
                if num == name then
                    found = true
                    break
                end
            end
            if not found then
                profileNames[#profileNames + 1] = name
            end
        end

        if #profileNames <= 1 then
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
        local accentRGB = CludesUI.ACCENT_COLOR or CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
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
        local hasWarning = WARN_MODULES[moduleFolder]
        local SUBTITLE_H = 30
        local popupH = PAD
            + HEADER_H
            + 7
            + SUBTITLE_H
            + 14
            + #profileNames * (ROW_H + ROW_GAP)
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
        dialog._folder = moduleFolder
        dialog:SetFrameLevel(200)

        dialog:SetSize(POPUP_W, popupH)
        -- The popup's border, header, profile rows (pooled by position) and action
        -- button are built once; every open re-applies their fonts, texts, colours,
        -- positions and actions.
        local parts = dialog._ui
        if not parts then
            parts = { rows = {} }
            dialog._ui = parts
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

        local function MakeFont(hostFrame, size, red, green, blue, a)
            local fontStr = hostFrame:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(fontStr, true)
            end
            fontStr:SetFont(fontFile, size, "")
            fontStr:SetTextColor(red or 1, green or 1, blue or 1, a or 1)
            return fontStr
        end

        local rowY = -PAD

        -- Header: sync icon (left), title (centered), close X (right)
        if not parts.iconTex then
            local iconTex = dialog:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(19, 19)
            iconTex:SetTexture(MEDIA_PATH .. "icons\\linked.png")
            parts.iconTex = iconTex
            parts.title = MakeFont(dialog, 14, 1, 1, 1, 0.9)
            local subtitle = MakeFont(dialog, 10, 1, 1, 1, 0.45)
            subtitle:SetWidth(POPUP_W - PAD * 2)
            subtitle:SetJustifyH("CENTER")
            subtitle:SetText(
                CludesUI.L(
                    "Syncing allows you to auto update all profiles whenever you change settings. This can be enabled per module."
                )
            )
            parts.subtitle = subtitle
        end
        local iconTex = parts.iconTex
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD - 1, rowY + 1)
        -- Accent when this module has an active sync group, gray otherwise
        if CludesUI.IsModuleSynced(moduleFolder) then
            iconTex:SetVertexColor(accentRGB.r, accentRGB.g, accentRGB.b, 1)
        else
            iconTex:SetVertexColor(0.55, 0.55, 0.55, 1)
        end

        local title = parts.title
        title:SetFont(fontFile, 14, "")
        title:ClearAllPoints()
        title:SetPoint("TOP", dialog, "TOP", 0, rowY - 1)
        title:SetText(CludesUI.Lf("%1$s Sync", CludesUI.L(displayName)))
        rowY = rowY - HEADER_H - 7

        local subtitle = parts.subtitle
        subtitle:SetFont(fontFile, 10, "")
        subtitle:ClearAllPoints()
        subtitle:SetPoint("TOP", dialog, "TOP", 0, rowY)
        rowY = rowY - SUBTITLE_H - 14

        -- Toggle rows for every profile (the active one included)
        local currentSynced = CludesUI.GetSyncedProfiles(moduleFolder)
        local toggleState = {}
        local hadGroup = next(currentSynced) ~= nil
        local refreshSyncBtnLabel -- defined with the button below
        -- The pooled rows' toggles and clicks read and write this open's state.
        dialog._toggleState = toggleState
        dialog._refreshLabel = nil

        local accentHex = string.format(
            "%02x%02x%02x",
            math.floor(accentRGB.r * 255 + 0.5),
            math.floor(accentRGB.g * 255 + 0.5),
            math.floor(accentRGB.b * 255 + 0.5)
        )

        local BuildToggleControl = CludesUI.BuildToggleControl
        local rowList = parts.rows
        for idx, profileName in ipairs(profileNames) do
            local isSynced = currentSynced[profileName] == true
            toggleState[profileName] = isSynced

            -- Card-style row: label left, toggle right, whole row clickable
            local line = rowList[idx]
            if not line then
                line = CreateFrame("Button", nil, dialog)
                line:SetFrameLevel(dialog:GetFrameLevel() + 1)
                local rowBg = line:CreateTexture(nil, "BACKGROUND")
                rowBg:SetAllPoints()
                rowBg:SetColorTexture(1, 1, 1, 0.05)
                line._bg = rowBg
                line._profName = profileName

                local tg, _, tgSnap = BuildToggleControl(line, line:GetFrameLevel() + 1, function()
                    return dialog._toggleState[line._profName]
                end, function(val)
                    dialog._toggleState[line._profName] = val
                    if dialog._refreshLabel then
                        dialog._refreshLabel()
                    end
                end, { sizeRatio = 0.75 })
                tg:SetPoint("RIGHT", line, "RIGHT", -10, 0)
                line._tg, line._tgSnap = tg, tgSnap

                line:SetScript("OnClick", function(self)
                    local status = dialog._toggleState
                    status[self._profName] = not status[self._profName]
                    self._tgSnap()
                    if dialog._refreshLabel then
                        dialog._refreshLabel()
                    end
                end)
                line:SetScript("OnEnter", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.08)
                end)
                line:SetScript("OnLeave", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.05)
                end)
                -- Toggle hover fires the row's OnLeave (child frame); keep the card lit
                tg:HookScript("OnEnter", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.08)
                end)
                tg:HookScript("OnLeave", function()
                    rowBg:SetColorTexture(1, 1, 1, 0.05)
                end)

                local lblText = MakeFont(line, 12, 1, 1, 1, 0.85)
                lblText:SetPoint("LEFT", line, "LEFT", 10, 0)
                line._lbl = lblText
                rowList[idx] = line
            end
            line._profName = profileName
            line:SetSize(POPUP_W - PAD * 2, ROW_H)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, rowY)
            line:SetFrameLevel(dialog:GetFrameLevel() + 1)
            line._tg:SetFrameLevel(line:GetFrameLevel() + 1)
            line._bg:SetColorTexture(1, 1, 1, 0.05)
            line._tgSnap()
            line:Show()

            local lblText = line._lbl
            lblText:SetFont(fontFile, 12, "")
            if profileName == isActive then
                lblText:SetText(profileName .. " |cff" .. accentHex .. "(active)|r")
            else
                lblText:SetText(profileName)
            end

            rowY = rowY - ROW_H - ROW_GAP
        end
        for idx = #profileNames + 1, #rowList do
            rowList[idx]:Hide()
        end

        rowY = rowY - (16 - ROW_GAP)

        -- Action button: full-width accent outline; label tracks the toggle state
        if not parts.syncBtn then
            local syncButton = CreateFrame("Button", nil, dialog)
            syncButton:SetFrameLevel(dialog:GetFrameLevel() + 1)
            local sBg = syncButton:CreateTexture(nil, "BACKGROUND")
            sBg:SetAllPoints()
            local sBrd
            if Pix then
                sBrd =
                    CludesUI.MakeRoundedBorder(syncButton, accentRGB.r, accentRGB.g, accentRGB.b, 0.7, sBg)
            end
            local subLabel = syncButton:CreateFontString(nil, "OVERLAY")
            if CludesUI and CludesUI.PrimeFontShadow then
                CludesUI.PrimeFontShadow(subLabel, false)
            end
            subLabel:SetPoint("CENTER")
            parts.syncBtn, parts.sBg, parts.sBrd, parts.sLbl = syncButton, sBg, sBrd, subLabel
        end
        local syncButton, sBg, sBrd, subLabel = parts.syncBtn, parts.sBg, parts.sBrd, parts.sLbl
        syncButton:SetSize(POPUP_W - PAD * 2, 30)
        syncButton:ClearAllPoints()
        syncButton:SetPoint("TOP", dialog, "TOP", 0, rowY)
        syncButton:SetFrameLevel(dialog:GetFrameLevel() + 1)
        subLabel:SetFont(fontFile, 11, "")

        -- Grayed out until the toggles actually differ from the saved group
        local function ApplyBtnState(dirty)
            syncButton._dirty = dirty
            if dirty then
                sBg:SetColorTexture(accentRGB.r, accentRGB.g, accentRGB.b, 0.08)
                if sBrd then
                    sBrd:SetColor(accentRGB.r, accentRGB.g, accentRGB.b, 0.7)
                end
                subLabel:SetTextColor(accentRGB.r, accentRGB.g, accentRGB.b, 1)
            else
                sBg:SetColorTexture(1, 1, 1, 0.03)
                if sBrd then
                    sBrd:SetColor(1, 1, 1, 0.15)
                end
                subLabel:SetTextColor(1, 1, 1, 0.35)
            end
        end
        syncButton:SetScript("OnEnter", function()
            if not syncButton._dirty then
                return
            end
            sBg:SetColorTexture(accentRGB.r, accentRGB.g, accentRGB.b, 0.18)
        end)
        syncButton:SetScript("OnLeave", function()
            ApplyBtnState(syncButton._dirty)
        end)

        refreshSyncBtnLabel = function()
            local total = 0
            local dirty = false
            for profileName, val in pairs(toggleState) do
                if val then
                    total = total + 1
                end
                if val ~= (currentSynced[profileName] == true) then
                    dirty = true
                end
            end
            if hadGroup and total == 0 then
                subLabel:SetText(CludesUI.L("Disband Sync Group"))
            elseif hadGroup then
                subLabel:SetText(CludesUI.L("Update Sync Group"))
            else
                subLabel:SetText(CludesUI.L("Create Sync Group"))
            end
            ApplyBtnState(dirty)
        end
        dialog._refreshLabel = refreshSyncBtnLabel
        refreshSyncBtnLabel()

        local function RefreshSidebarSyncIcon()
            local sidebarBtns = CUI_NS.sidebarButtons
            if sidebarBtns and sidebarBtns[moduleFolder] and sidebarBtns[moduleFolder]._syncBtn then
                local scrollBar = sidebarBtns[moduleFolder]._syncBtn
                if scrollBar._refreshAlpha then
                    scrollBar._refreshAlpha()
                end
            end
        end

        syncButton:SetScript("OnClick", function()
            if not syncButton._dirty then
                return
            end
            -- The group is exactly the toggled-on profiles
            local syncTargets = {}
            local total = 0
            local anyNew = false
            for profileName, checked in pairs(toggleState) do
                if checked then
                    syncTargets[profileName] = true
                    total = total + 1
                    if not currentSynced[profileName] then
                        anyNew = true
                    end
                end
            end

            if total == 0 then
                -- Disband (or nothing was ever configured)
                if not CludesUIDB.syncedModules then
                    CludesUIDB.syncedModules = {}
                end
                CludesUIDB.syncedModules[moduleFolder] = {}
                dialog:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            if total == 1 then
                if CludesUI.ShowWidgetTooltip then
                    CludesUI.ShowWidgetTooltip(syncButton, "A sync group needs at least two profiles")
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
                CludesUIDB.syncedModules[moduleFolder] = syncTargets
                dialog:Hide()
                RefreshSidebarSyncIcon()
                return
            end

            -- New members joining: confirm with a seed picker; default = an existing member
            -- on update (newcomers adopt group settings), active on create.
            local memberOrder = {}
            for _, name in ipairs(profileNames) do
                if syncTargets[name] then
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
                defaultSeed = syncTargets[isActive] and isActive or memberOrder[1]
            end

            dialog:SetFrameLevel(90)
            dialog:SetScript("OnUpdate", nil)
            CludesUI._ShowSyncSeedConfirm({
                folder = moduleFolder,
                displayName = displayName,
                targets = syncTargets,
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
