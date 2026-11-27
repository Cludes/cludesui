if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Profiles.lua
--
--  Global profile system: import/export, presets, spec assignment.
--  Handles serialization (LibDeflate + custom serializer) and profile
--  management across all CludesUI addons.
--
--  Load order (via TOC):
--    1. Libs/LibDeflate.lua
--    2. CludesUI_Lite.lua
--    3. CludesUI.lua
--    4. CludesUI_Widgets.lua
--    5. CludesUI_Presets.lua
--    6. CludesUI_Profiles.lua  -- THIS FILE
-------------------------------------------------------------------------------

local CUI = _G.CludesUI

-------------------------------------------------------------------------------
--  LibDeflate reference (loaded before us via TOC)
--  LibDeflate registers via LibStub, not as a global, so use LibStub to get it.
-------------------------------------------------------------------------------
local LibDeflate = LibStub and LibStub("LibDeflate", true) or _G.LibDeflate

-------------------------------------------------------------------------------
--  Addon registry: display-order list of all managed addons.
--  Each entry: { folder, display, svName }
--    folder  = addon folder name (matches _dbRegistry key)
--    display = human-readable name for the Profiles UI
--    svName  = SavedVariables name (e.g. "CludesUINameplatesDB")
--
--  All addons use _dbRegistry for profile access. Order matters for UI display.
-------------------------------------------------------------------------------
-- `suffix` is the rename-immune module id (the folder name minus the
-- "CludesUI" prefix). It NEVER contains the contiguous "CludesUI" token,
-- so the standalone packager's textual rename leaves it byte-identical in every
-- build. It is the anchor for the canonical export/import key (see below).
local ADDON_DB_MAP = {
    {
        folder = "CludesUIActionBars",
        display = "Action Bars",
        svName = "CludesUIActionBarsDB",
        suffix = "ActionBars",
    },
    {
        folder = "CludesUINameplates",
        display = "Nameplates",
        svName = "CludesUINameplatesDB",
        suffix = "Nameplates",
    },
    {
        folder = "CludesUIUnitFrames",
        display = "Unit Frames",
        svName = "CludesUIUnitFramesDB",
        suffix = "UnitFrames",
    },
    {
        folder = "CludesUICooldownManager",
        display = "Cooldown Manager",
        svName = "CludesUICooldownManagerDB",
        suffix = "CooldownManager",
    },
    {
        folder = "CludesUIResourceBars",
        display = "Resource Bars",
        svName = "CludesUIResourceBarsDB",
        suffix = "ResourceBars",
    },
    {
        folder = "CludesUIRaidFrames",
        display = "Raid & Party Frames",
        svName = "CludesUIRaidFramesDB",
        suffix = "RaidFrames",
    },
    {
        folder = "CludesUIAuraBuffReminders",
        display = "Buff Reminders",
        svName = "CludesUIAuraBuffRemindersDB",
        suffix = "AuraBuffReminders",
    },
    -- v6.6 split-out addons (were previously bundled under the retired
    -- CludesUIBasics, removed from the suite v8.7.x).
    {
        folder = "CludesUIQoL",
        display = "Utilities",
        svName = "CludesUIQoLDB",
        suffix = "QoL",
    },
    {
        folder = "CludesUITank",
        display = "Tank Kit",
        svName = "CludesUITankDB",
        suffix = "Tank",
    },
    {
        folder = "CludesUIRaidLead",
        display = "Raid Lead",
        svName = "CludesUIRaidLeadDB",
        suffix = "RaidLead",
    },
    -- BlizzardSkin itself is excluded: it stores settings on the shared
    -- CludesUIDB root, not through NewDB, so it has no module profile
    -- (its few per-profile keys -- disableWindowSkins, the character sheet
    -- style, the whole-UI window look -- sit on the profile root itself).
    -- Dragon Riding is the one exception inside that addon -- it owns a real
    -- per-profile DB (CludesUIDragonRidingDB) but ships as a file inside the
    -- BlizzardSkin addon, so it is NOT a separately loadable addon. hostAddon
    -- tells the loaded check (export strip + import/export checkboxes) to resolve
    -- "installed?" through the BlizzardSkin folder instead of the (nonexistent)
    -- CludesUIDragonRiding addon. Without this it would always be stripped.
    {
        folder = "CludesUIDragonRiding",
        display = "Dragon Riding",
        svName = "CludesUIDragonRidingDB",
        suffix = "DragonRiding",
        hostAddon = "CludesUIBlizzardSkin",
    },
    {
        folder = "CludesUIBags",
        display = "Bags",
        svName = "CludesUIBagsDB",
        suffix = "Bags",
    },
    {
        folder = "CludesUIFriends",
        display = "Friends List",
        svName = "CludesUIFriendsDB",
        suffix = "Friends",
    },
    {
        folder = "CludesUIMythicTimer",
        display = "Mythic+ Tools",
        svName = "CludesUIMythicTimerDB",
        suffix = "MythicTimer",
    },
    {
        folder = "CludesUIQuestTracker",
        display = "Quest Tracker",
        svName = "CludesUIQuestTrackerDB",
        suffix = "QuestTracker",
    },
    {
        folder = "CludesUIMinimap",
        display = "Minimap",
        svName = "CludesUIMinimapDB",
        suffix = "Minimap",
    },
    {
        folder = "CludesUIDamageMeters",
        display = "Damage Meters",
        svName = "CludesUIDamageMetersDB",
        suffix = "DamageMeters",
    },
    {
        folder = "CludesUIChat",
        display = "Chat",
        svName = "CludesUIChatDB",
        suffix = "Chat",
    },
    {
        folder = "CludesUIDataBars",
        display = "Info Bar",
        svName = "CludesUIDataBarsDB",
        suffix = "DataBars",
    },
    {
        folder = "CludesUIQuickdraw",
        display = "Action Wheel",
        svName = "CludesUIQuickdrawDB",
        suffix = "Quickdraw",
    },
}
CUI._ADDON_DB_MAP = ADDON_DB_MAP

-------------------------------------------------------------------------------
--  Canonical addon keys (suite <-> standalone profile-string interop)
--
--  Profile strings key each addon's data by the addon FOLDER NAME. In a
--  standalone build the packager textually renames "CludesUI" -> the build's
--  token, so the local folder/db key (e.g. "CUIStandaloneBags") diverges from
--  the suite's ("CludesUIBags") and cross-build imports never match.
--
--  Fix: every exported string uses a CANONICAL key = the suite folder name,
--  which both builds can reconstruct. The packager renames only the CONTIGUOUS
--  token "CludesUI", so writing the prefix split as "Cludes".."UI" leaves
--  no contiguous match -- it stays "CludesUI" at runtime in EVERY build. The
--  bare `suffix` is likewise never a rename target, so canon = prefix..suffix ==
--  the suite folder name everywhere. Live DBs keep their own (renamed) folder;
--  only the serialized string is normalized. In the suite canon == folder, so
--  every translation is content-identity (no behavior change, no SV migration).
-------------------------------------------------------------------------------
local CUI_CANON_PREFIX = "Cludes" .. "UI" -- split literal: rename-immune
local FOLDER_TO_CANON = {}
local CANON_TO_FOLDER = {}
-- folder -> the addon whose loaded-state proves this module is installed. Most
-- modules host themselves; a sub-module (e.g. Dragon Riding) maps to its host.
local FOLDER_HOST = {}
for _, record in ipairs(ADDON_DB_MAP) do
    local canon = CUI_CANON_PREFIX .. (record.suffix or "")
    record.canon = canon
    FOLDER_TO_CANON[record.folder] = canon
    CANON_TO_FOLDER[canon] = record.folder
    FOLDER_HOST[record.folder] = record.hostAddon or record.folder
end

-- Re-key an addons table from this build's local db.folder keys to canonical
-- keys (used on export). Unknown keys pass through unchanged.
local function AddonsToCanon(addonMap)
    if type(addonMap) ~= "table" then return addonMap end
    local output = {}
    for key, val in pairs(addonMap) do
        output[FOLDER_TO_CANON[key] or key] = val
    end
    return output
end

-- Re-key an addons table from canonical keys to this build's local db.folder
-- keys (used on import). Unknown keys pass through unchanged.
local function CanonToLocal(addonMap)
    if type(addonMap) ~= "table" then return addonMap end
    local output = {}
    for key, val in pairs(addonMap) do
        output[CANON_TO_FOLDER[key] or key] = val
    end
    return output
end

-------------------------------------------------------------------------------
--  Account data that must never travel in a profile string
--
--  These keys held per-character state -- character names, realms, classes,
--  gold balances, scan caches -- inside a module's profile blob, so a shared
--  profile carried the exporter's character list to everyone who imported it
--  (visible in the DataBars gold tooltip). They live top-level in CludesUIDB
--  now, but strings exported by older versions still carry them, and an
--  imported blob would otherwise sit in the recipient's profile and ride THEIR
--  next export -- propagating one player's characters indefinitely. So strip
--  on the way out AND on the way in.
--
--  The folder literals contain "CludesUI", which the standalone packager
--  renames to the build token, so they match the local keyspace on every
--  build; the canon lookup covers a decoded payload's canonical keys.
-------------------------------------------------------------------------------
local PRIVATE_ADDON_KEYS = {
    ["CludesUIDataBars"] = { "characters" }, -- gold record -> CludesUIDB.goldLedger
    ["CludesUIQoL"] = { "chars" }, -- upgrade calc -> CludesUIDB.qolUpgradeCalcChars
}

-- Strip account data from an addons table, in place. Accepts either keyspace
-- (local folder keys before canonicalization on export, canonical keys in a
-- decoded payload), so one pass serves both directions.
local function StripPrivateAddonData(addonMap)
    if type(addonMap) ~= "table" then return end
    for moduleFolder, keyList in pairs(PRIVATE_ADDON_KEYS) do
        local blob = addonMap[moduleFolder] or addonMap[FOLDER_TO_CANON[moduleFolder] or moduleFolder]
        if type(blob) == "table" then
            for _, entryKey in ipairs(keyList) do
                blob[entryKey] = nil
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Unlock-element key -> owning module (LOCAL folder) resolver
--
--  The selective-layout export/import attributes each anchor / size-match
--  relationship (keyed by unlock-element key) to a module so layout can be
--  exported per-module. Authoritative source is a passed-in folder (elem.folder
--  stamped at registration, or a payload keyToFolder value); this static
--  prefix/bare-word resolver is the fallback that covers every key in use today
--  (verified) plus any future key the authoritative source misses.
--
--  Returns a LOCAL folder name: the literals below contain "CludesUI", which
--  the standalone packager renames to the build token, so on each build this
--  matches the local selectedAddons keyspace and the stamped elem.folder. (Only
--  the payload keyToFolder is canonicalized -- see ExportProfile.) nil = unknown.
-------------------------------------------------------------------------------
local KEY_PREFIX_FOLDER = {
    ["CDM_"] = "CludesUICooldownManager",
    ["TBB_"] = "CludesUICooldownManager",
    ["ERB_"] = "CludesUIResourceBars",
    ["ECHAT_"] = "CludesUIChat",
    ["EBS_"] = "CludesUIMinimap",
    ["EQT_"] = "CludesUIQuestTracker",
    ["EDR_"] = "CludesUIBlizzardSkin",
    ["EMT_"] = "CludesUIMythicTimer",
    ["EABR_"] = "CludesUIAuraBuffReminders",
    ["RF_"] = "CludesUIRaidFrames",
    ["ECL_"] = "CludesUIQoL",
    ["CUI_"] = "CludesUIQoL",
    ["TANK_"] = "CludesUITank",
    ["RLEAD_"] = "CludesUIRaidLead",
}
-- Bare-word (un-prefixed) keys, by owning module. These appear as anchor TARGETS
-- (e.g. a castbar anchored to "player", a bar anchored to "Bar4") even when the
-- child carries a stamped folder, so the resolver must know them.
local AB_BAREWORD = {
    MainBar = true,
    Bar2 = true,
    Bar3 = true,
    Bar4 = true,
    Bar5 = true,
    Bar6 = true,
    Bar7 = true,
    Bar8 = true,
    StanceBar = true,
    PetBar = true,
    XPBar = true,
    RepBar = true,
    ExtraActionButton = true,
    EncounterBar = true,
    QueueStatus = true,
    MicroBar = true,
    BagBar = true,
}
-- WoW Forever never registers the House Favor bar: classify it statically
-- there so its anchor and size-match links keep travelling in exports.
if CUI.IS_FOREVER == true then AB_BAREWORD.FavorBar = true end
local UF_BAREWORD = {
    player = true,
    target = true,
    focus = true,
    pet = true,
    targettarget = true,
    focustarget = true,
    boss = true,
    classPower = true,
    playerCastbar = true,
    targetCastbar = true,
    focusCastbar = true,
    petCastbar = true,
}
-- providedFolder (already a local folder: elem.folder, or a payload value that
-- has been CanonToLocal'd) wins; the static resolution is the fallback.
local function ResolveKeyToFolder(entryKey, providedFolder)
    if providedFolder then return providedFolder end
    if type(entryKey) ~= "string" then return nil end
    for prefixText, moduleFolder in pairs(KEY_PREFIX_FOLDER) do
        if entryKey:sub(1, #prefixText) == prefixText then return moduleFolder end
    end
    if AB_BAREWORD[entryKey] then return "CludesUIActionBars" end
    if UF_BAREWORD[entryKey] then return "CludesUIUnitFrames" end
    return nil
end
CUI.ResolveKeyToFolder = ResolveKeyToFolder

-- Set of folders that have NO import/export checkbox (not in ADDON_DB_MAP), so
-- their anchor/match edges are never exported -- the element keeps its own saved
-- absolute position on import (decision: always export them unanchored): the
-- Dragon Riding cluster (CludesUIBlizzardSkin) and every Forever Essentials
-- element (their settings are all account-wide).
local NO_CHECKBOX_FOLDER = {}
do
    local has = {}
    for _, record in ipairs(ADDON_DB_MAP) do
        has[record.folder] = true
    end
    -- Any folder the resolver can return that isn't a checkbox module:
    for _, moduleFolder in pairs(KEY_PREFIX_FOLDER) do
        if not has[moduleFolder] then NO_CHECKBOX_FOLDER[moduleFolder] = true end
    end
    -- Stamped on its elements at registration (it has no key prefix of its own).
    NO_CHECKBOX_FOLDER["CludesUIForeverEssentials"] = true
end
CUI._NoCheckboxFolder = NO_CHECKBOX_FOLDER

-------------------------------------------------------------------------------
--  Serializer: Lua table <-> string (no AceSerializer dependency)
--  Handles: string, number, boolean, nil, table (nested), color tables
-------------------------------------------------------------------------------
local Serializer = {}

local function SerializeValue(v, pieces)
    local kind = type(v)
    if kind == "string" then
        pieces[#pieces + 1] = "s"
        -- Length-prefixed to avoid delimiter issues
        pieces[#pieces + 1] = #v
        pieces[#pieces + 1] = ":"
        pieces[#pieces + 1] = v
    elseif kind == "number" then
        pieces[#pieces + 1] = "n"
        pieces[#pieces + 1] = tostring(v)
        pieces[#pieces + 1] = ";"
    elseif kind == "boolean" then
        pieces[#pieces + 1] = v and "T" or "F"
    elseif kind == "nil" then
        pieces[#pieces + 1] = "N"
    elseif kind == "table" then
        pieces[#pieces + 1] = "{"
        -- Serialize array part first (integer keys 1..n)
        local num = #v
        for i = 1, num do
            SerializeValue(v[i], pieces)
        end
        -- Then hash part (non-integer keys, or integer keys > n)
        for key, value in pairs(v) do
            local kt = type(key)
            if kt == "number" and key >= 1 and key <= num and key == math.floor(key) then
                -- Already serialized in array part
            else
                pieces[#pieces + 1] = "K"
                SerializeValue(key, pieces)
                SerializeValue(value, pieces)
            end
        end
        pieces[#pieces + 1] = "}"
    end
end

function Serializer.Serialize(dataTbl)
    local pieces = {}
    SerializeValue(dataTbl, pieces)
    return table.concat(pieces)
end

-- Deserializer Optional cooperative-yield hook: when set (async decode),
-- DeserializeValue calls it periodically with the current parse position so a wrapping
-- coroutine can spread the work across frames. nil (the default) keeps all synchronous
-- callers exactly as before.
local deserializeYieldHook
local deserializeOps = 0

-- A truncated s/n token (no delimiter, so no way to advance) flags the parse
-- and jumps past the end, so every enclosing table loop stops. Not error():
-- the async decode yields mid-parse, which a pcall would forbid.
local function Malformed(packed)
    Serializer._malformed = true
    return nil, #packed + 1
end

local function DeserializeValue(packed, place)
    if deserializeYieldHook then
        deserializeOps = deserializeOps + 1
        if deserializeOps >= 2048 then
            deserializeOps = 0
            deserializeYieldHook(place)
        end
    end
    local tagText = packed:sub(place, place)
    if tagText == "s" then
        -- Find the colon after the length
        local colonPos = packed:find(":", place + 1, true)
        if not colonPos then return Malformed(packed) end
        local len = tonumber(packed:sub(place + 1, colonPos - 1))
        if not len or not (len >= 0) then return Malformed(packed) end -- negative/NaN would not advance
        local value = packed:sub(colonPos + 1, colonPos + len)
        return value, colonPos + len + 1
    elseif tagText == "n" then
        local semi = packed:find(";", place + 1, true)
        if not semi then return Malformed(packed) end
        return tonumber(packed:sub(place + 1, semi - 1)), semi + 1
    elseif tagText == "T" then
        return true, place + 1
    elseif tagText == "F" then
        return false, place + 1
    elseif tagText == "N" then
        return nil, place + 1
    elseif tagText == "{" then
        local dataTbl = {}
        local position = 1
        local p = place + 1
        while p <= #packed do
            local char = packed:sub(p, p)
            if char == "}" then
                return dataTbl, p + 1
            elseif char == "K" then
                -- Key-value pair
                local entryKey, value
                entryKey, p = DeserializeValue(packed, p + 1)
                value, p = DeserializeValue(packed, p)
                if entryKey ~= nil then dataTbl[entryKey] = value end
            else
                -- Array element
                local value
                value, p = DeserializeValue(packed, p)
                dataTbl[position] = value
                position = position + 1
            end
        end
        return dataTbl, p
    end
    return nil, place + 1
end

function Serializer.Deserialize(packed)
    if not packed or #packed == 0 then return nil end
    -- The flag is shared module state and the async decode yields mid-parse: a
    -- decode run while another is parked keeps that one's flag as it found it.
    local prev = Serializer._malformed
    Serializer._malformed = nil
    local value, _ = DeserializeValue(packed, 1)
    local bad = Serializer._malformed
    Serializer._malformed = prev
    if bad then return nil end
    return value
end

-- Install/clear the deserializer's cooperative-yield hook (async decode).
function Serializer.SetYieldHook(func)
    deserializeYieldHook = func
    deserializeOps = 0
end

CUI._Serializer = Serializer

-------------------------------------------------------------------------------
--  Deep copy utility
-------------------------------------------------------------------------------
local function CopyDeep(src, seen)
    if type(src) ~= "table" then return src end
    if seen and seen[src] then return seen[src] end
    if not seen then seen = {} end
    local duplicate = {}
    seen[src] = duplicate
    for key, val in pairs(src) do
        -- Skip frame references and other userdata that can't be serialized
        if type(val) ~= "userdata" and type(val) ~= "function" then duplicate[key] = CopyDeep(val, seen) end
    end
    return duplicate
end

local function DeepMerge(destination, src)
    for key, val in pairs(src) do
        if type(val) == "table" and type(destination[key]) == "table" then
            DeepMerge(destination[key], val)
        else
            destination[key] = CopyDeep(val)
        end
    end
end

CUI._DeepCopy = CopyDeep

-------------------------------------------------------------------------------
--  Selective-layout core helpers (shared by export, import, and the
--  connectivity-aware checkbox UI). All operate on an unlockLayout table
--  { anchors, widthMatch, heightMatch, phantomBounds } and LOCAL folder keys.
-------------------------------------------------------------------------------

-- Build { [key] = localFolder } for every key referenced in an unlockLayout
-- (anchor children + targets, width/height-match children + values), using the
-- live registry's elem.folder first, then the static resolver. Also returns a
-- `stale` set of keys NOT in the live registry (deleted/other-spec bars) so the
-- caller can prune dead edges. Use at EXPORT time (needs the exporter registry).
function CUI.BuildLayoutKeyToFolder(layout)
    local registryTbl = CUI._unlockRegisteredElements or {}
    local keyToFolder, stale = {}, {}
    local function addFn(entryKey)
        if type(entryKey) ~= "string" or keyToFolder[entryKey] ~= nil then return end
        local elem = registryTbl[entryKey]
        local moduleFolder = ResolveKeyToFolder(entryKey, elem and elem.folder)
        if moduleFolder then keyToFolder[entryKey] = moduleFolder end
        if not elem then stale[entryKey] = true end
    end
    if type(layout) == "table" then
        if type(layout.anchors) == "table" then
            for childFrame, details in pairs(layout.anchors) do
                addFn(childFrame)
                if type(details) == "table" then addFn(details.target) end
            end
        end
        if type(layout.widthMatch) == "table" then
            for childFrame, target in pairs(layout.widthMatch) do
                addFn(childFrame)
                addFn(target)
            end
        end
        if type(layout.heightMatch) == "table" then
            for childFrame, target in pairs(layout.heightMatch) do
                addFn(childFrame)
                addFn(target)
            end
        end
    end
    return keyToFolder, stale
end

-- Match extras (widthMatchExtra / heightMatchExtra: childKey -> px) mean
-- something only beside their child's link, so they travel with it.
-- CopyLinkedExtras returns a new table of the extras whose child still has a
-- link in `links`. OverlayLinkedExtras gives every child linked in `links` its
-- extra from `extras`; a child without one there loses the extra `dst` held.
local function CopyLinkedExtras(extras, links)
    local output = {}
    if type(extras) == "table" and type(links) == "table" then
        for childFrame, px in pairs(extras) do
            if links[childFrame] ~= nil then output[childFrame] = px end
        end
    end
    return output
end

local function OverlayLinkedExtras(destination, links, extras)
    if type(links) ~= "table" then return end
    if type(extras) ~= "table" then extras = nil end
    for childFrame in pairs(links) do
        destination[childFrame] = extras and extras[childFrame] or nil
    end
end

-- Return a NEW unlockLayout keeping only entries whose BOTH endpoints resolve to
-- a folder in `folderSet` (set of LOCAL folders), with both endpoints live (not
-- stale), known, and NOT in a no-checkbox folder. This is the per-entry filter
-- that guarantees no retained relationship references an excluded module.
-- k2f/stale may be passed (e.g. import-side, built from payload meta) or omitted
-- (export-side, built from the live registry).
function CUI.FilterLayoutToFolders(layout, folderSet, keyToFolder)
    if type(layout) ~= "table" then return layout end
    if not keyToFolder then keyToFolder = CUI.BuildLayoutKeyToFolder(layout) end
    -- Classification is by the static resolver (registry-independent) so this can
    -- never over-drop just because the unlock registry isn't fully populated yet.
    -- An edge survives only if BOTH endpoints classify to a folder in folderSet and
    -- neither is a no-checkbox module. (A dead/deleted-bar edge that happens to
    -- survive is harmless: its missing child frame just no-ops on apply.)
    local function endpointOK(entryKey)
        if type(entryKey) ~= "string" then return false end
        local folder = keyToFolder[entryKey]
        if not folder then return false end -- unclassifiable -> drop
        if NO_CHECKBOX_FOLDER[folder] then return false end -- never export no-checkbox edges
        return folderSet[folder] == true -- both endpoints in S
    end
    -- Screen-edge targets (CUI_UnlockMode) exist on every install and belong to no
    -- module: a link TO one travels with its child's module. Target only -- a screen
    -- edge is never an anchor child or a size-match endpoint.
    local isEdge = CUI.IsScreenEdgeKey
    local output = { anchors = {}, widthMatch = {}, heightMatch = {}, phantomBounds = {} }
    if type(layout.anchors) == "table" then
        for childFrame, details in pairs(layout.anchors) do
            if
                type(details) == "table"
                and endpointOK(childFrame)
                and (endpointOK(details.target) or (isEdge and isEdge(details.target)))
            then
                output.anchors[childFrame] = CopyDeep(details)
            end
        end
    end
    if type(layout.widthMatch) == "table" then
        for childFrame, target in pairs(layout.widthMatch) do
            if endpointOK(childFrame) and endpointOK(target) then output.widthMatch[childFrame] = target end
        end
    end
    if type(layout.heightMatch) == "table" then
        for childFrame, target in pairs(layout.heightMatch) do
            if endpointOK(childFrame) and endpointOK(target) then output.heightMatch[childFrame] = target end
        end
    end
    -- An extra survives only where its link did.
    output.widthMatchExtra = CopyLinkedExtras(layout.widthMatchExtra, output.widthMatch)
    output.heightMatchExtra = CopyLinkedExtras(layout.heightMatchExtra, output.heightMatch)
    return output
end

-- Union-find over modules: two folders share a component if any LIVE, non-no-
-- checkbox anchor/match edge connects them. Returns folderToMembers where
-- folderToMembers[folder] = { set of folders in folder's component }. A folder
-- with no cross-module edge is absent (treat as a singleton: just itself).
-- Drives the hard-couple checkbox auto-toggle. k2f/stale may be passed in.
function CUI.BuildModuleComponents(layout, keyToFolder)
    if not keyToFolder then keyToFolder = CUI.BuildLayoutKeyToFolder(layout) end
    local hostFrame = {}
    local function find(posX)
        while hostFrame[posX] and hostFrame[posX] ~= posX do
            posX = hostFrame[posX]
        end
        return posX
    end
    local function union(lhs, rhs)
        if not hostFrame[lhs] then hostFrame[lhs] = lhs end
        if not hostFrame[rhs] then hostFrame[rhs] = rhs end
        local ra, rb = find(lhs), find(rhs)
        if ra ~= rb then hostFrame[ra] = rb end
    end
    local function edge(c, t)
        if type(c) ~= "string" or type(t) ~= "string" then return end
        local fc, ft = keyToFolder[c], keyToFolder[t]
        if not fc or not ft then return end
        if NO_CHECKBOX_FOLDER[fc] or NO_CHECKBOX_FOLDER[ft] then return end
        if fc ~= ft then union(fc, ft) end
    end
    if type(layout) == "table" then
        if type(layout.anchors) == "table" then
            for c, i in pairs(layout.anchors) do
                if type(i) == "table" then edge(c, i.target) end
            end
        end
        if type(layout.widthMatch) == "table" then
            for c, t in pairs(layout.widthMatch) do
                edge(c, t)
            end
        end
        if type(layout.heightMatch) == "table" then
            for c, t in pairs(layout.heightMatch) do
                edge(c, t)
            end
        end
    end
    local rootList = {}
    for f in pairs(hostFrame) do
        local r = find(f)
        rootList[r] = rootList[r] or {}
        rootList[r][f] = true
    end
    local folderToMembers = {}
    for _, members in pairs(rootList) do
        for f in pairs(members) do
            folderToMembers[f] = members
        end
    end
    return folderToMembers
end

-- IMPORT side: build { [key] = CANON folder } for every key in an imported
-- unlockLayout. The payload's keyToFolder meta wins (already canonical); for any
-- key it lacks -- including ALL keys when importing an OLD string with no meta --
-- fall back to the static resolver (LOCAL) re-canonicalized via FOLDER_TO_CANON.
-- This is what keeps a meta-less string from classifying nothing and dropping the
-- whole layout. Matches selectedImports' CANON keyspace.
function CUI.BuildImportKeyToFolder(layout, metaK2F)
    metaK2F = metaK2F or {}
    local keyToFolder = {}
    local function addFn(entryKey)
        if type(entryKey) ~= "string" or keyToFolder[entryKey] ~= nil then return end
        local f = metaK2F[entryKey]
        if not f then
            local localF = ResolveKeyToFolder(entryKey, nil)
            if localF then f = FOLDER_TO_CANON[localF] or localF end
        end
        if f then keyToFolder[entryKey] = f end
    end
    if type(layout) == "table" then
        if type(layout.anchors) == "table" then
            for c, i in pairs(layout.anchors) do
                addFn(c)
                if type(i) == "table" then addFn(i.target) end
            end
        end
        if type(layout.widthMatch) == "table" then
            for c, t in pairs(layout.widthMatch) do
                addFn(c)
                addFn(t)
            end
        end
        if type(layout.heightMatch) == "table" then
            for c, t in pairs(layout.heightMatch) do
                addFn(c)
                addFn(t)
            end
        end
    end
    return keyToFolder
end

-- IMPORT merge: build the new profile's unlockLayout by merging the imported
-- (already module-filtered) relationships INTO the base (current-profile) layout,
-- PER MODULE. The new profile keeps the base's relationships for modules NOT
-- imported, and takes the imported relationships for modules that ARE imported.
-- Ownership is by the CHILD key's module (an anchor/match entry positions/sizes
-- its child). importedFolders = set of LOCAL folders being imported. For a full
-- import (every module) this reduces to "replace with imported" (every child is
-- owned by an imported module). LOCAL keyspace throughout.
function CUI.MergeImportedLayout(baseTbl, incoming, importedFolders)
    baseTbl = (type(baseTbl) == "table") and baseTbl or {}
    incoming = (type(incoming) == "table") and incoming or {}
    importedFolders = importedFolders or {}
    local output = {
        anchors = CopyDeep(baseTbl.anchors or {}),
        widthMatch = CopyDeep(baseTbl.widthMatch or {}),
        heightMatch = CopyDeep(baseTbl.heightMatch or {}),
        phantomBounds = CopyDeep(baseTbl.phantomBounds or {}),
    }
    -- 1) Drop base entries OWNED by an imported module (child in importedFolders),
    --    so the imported module's layout fully replaces the base's for that module.
    --    Classify the BASE children via the live (recipient) registry + static
    --    resolver, since these are the recipient's own profile keys.
    local baseK2F = CUI.BuildLayoutKeyToFolder(baseTbl)
    local function childImported(childFrame)
        local f = baseK2F[childFrame]
        return f ~= nil and importedFolders[f] == true
    end
    for childFrame in pairs(output.anchors) do
        if childImported(childFrame) then output.anchors[childFrame] = nil end
    end
    for childFrame in pairs(output.widthMatch) do
        if childImported(childFrame) then output.widthMatch[childFrame] = nil end
    end
    for childFrame in pairs(output.heightMatch) do
        if childImported(childFrame) then output.heightMatch[childFrame] = nil end
    end
    -- 2) Overlay the imported entries (already filtered to the imported modules).
    if type(incoming.anchors) == "table" then
        for childFrame, details in pairs(incoming.anchors) do
            output.anchors[childFrame] = CopyDeep(details)
        end
    end
    if type(incoming.widthMatch) == "table" then
        for childFrame, t in pairs(incoming.widthMatch) do
            output.widthMatch[childFrame] = t
        end
    end
    if type(incoming.heightMatch) == "table" then
        for childFrame, t in pairs(incoming.heightMatch) do
            output.heightMatch[childFrame] = t
        end
    end
    -- 3) Match extras follow their links: a kept base link keeps its extra, an
    --    imported link brings the import's extra (or none).
    output.widthMatchExtra = CopyLinkedExtras(baseTbl.widthMatchExtra, output.widthMatch)
    output.heightMatchExtra = CopyLinkedExtras(baseTbl.heightMatchExtra, output.heightMatch)
    OverlayLinkedExtras(output.widthMatchExtra, incoming.widthMatch, incoming.widthMatchExtra)
    OverlayLinkedExtras(output.heightMatchExtra, incoming.heightMatch, incoming.heightMatchExtra)
    return output
end

-- Build the (filtered) unlockLayout + canonical keyToFolder meta to embed in an
-- export string, honoring the "Include layout" toggle and the selected modules.
--   unlockLayout : the profile's live layout (active profile == CludesUIDB.*)
--   includeLayout: false -> returns (nil, nil); no relationships embedded
--   folderSet    : set of LOCAL folders to keep (subset export); nil -> all
--                  checkbox modules (full export, still drops no-checkbox edges)
-- Returns (filteredUnlockLayout, meta) where meta.keyToFolder is CANONICAL.
function CUI.BuildExportUnlockLayout(unlockLayout, includeLayout, folderSet)
    if not includeLayout or type(unlockLayout) ~= "table" then return nil, nil end
    if not folderSet then
        folderSet = {}
        for _, record in ipairs(ADDON_DB_MAP) do
            folderSet[record.folder] = true
        end
    end
    local keyToFolder = CUI.BuildLayoutKeyToFolder(unlockLayout)
    local filtered = CUI.FilterLayoutToFolders(unlockLayout, folderSet, keyToFolder)
    local meta = { keyToFolder = {} }
    local function addMeta(entryKey)
        if type(entryKey) == "string" and meta.keyToFolder[entryKey] == nil then
            local localF = keyToFolder[entryKey]
            if localF then meta.keyToFolder[entryKey] = FOLDER_TO_CANON[localF] or localF end
        end
    end
    for c, i in pairs(filtered.anchors) do
        addMeta(c)
        if type(i) == "table" then addMeta(i.target) end
    end
    for c, t in pairs(filtered.widthMatch) do
        addMeta(c)
        addMeta(t)
    end
    for c, t in pairs(filtered.heightMatch) do
        addMeta(c)
        addMeta(t)
    end
    return filtered, meta
end

-------------------------------------------------------------------------------
--  Profile DB helpers
--  Profiles are stored in CludesUIDB.profiles = { [name] = profileData }
--  profileData = {
--      addons = { [folderName] = <snapshot of that addon's profile table> },
--      fonts  = <snapshot of CludesUIDB.fonts>,
--      customColors = <snapshot of CludesUIDB.customColors>,
--      darkMode = <per-profile Dark Mode palette + class/power/resource darken>,
--      numberFormat = <per-profile Number Format, CludesUI_NumberFormat.lua>,
--  }
--  CludesUIDB.activeProfile = "Default"  (name of active profile)
--  CludesUIDB.profileOrder  = { "Default", ... }
--  CludesUIDB.specProfiles  = { [specID] = "profileName" }
-------------------------------------------------------------------------------
local function GetProfilesDB()
    if not CludesUIDB then CludesUIDB = {} end
    if not CludesUIDB.profiles then CludesUIDB.profiles = {} end
    if not CludesUIDB.profileOrder then CludesUIDB.profileOrder = {} end
    if not CludesUIDB.specProfiles then CludesUIDB.specProfiles = {} end
    return CludesUIDB
end
CUI.GetProfilesDB = GetProfilesDB

-------------------------------------------------------------------------------
--  Anchor offset format conversion
--
--  Anchor offsets were originally stored relative to the target's center
--  (format version 0/nil). The current system stores them relative to
--  stable edges (format version 1):
--    TOP/BOTTOM: offsetX relative to target LEFT edge
--    LEFT/RIGHT: offsetY relative to target TOP edge
--
--- Check if an addon is loaded
local IsAddonLoaded = C_AddOns.IsAddOnLoaded

--- Is the module behind this profile folder actually installed/loaded?
--- Resolves through hostAddon for sub-modules (e.g. Dragon Riding lives inside
--- the BlizzardSkin addon, so its folder is never a loadable addon on its own).
--- Unknown folders fall back to a direct check so behaviour is unchanged.
function CUI.IsModuleAddonLoaded(moduleFolder) return IsAddonLoaded(FOLDER_HOST[moduleFolder] or moduleFolder) end

--- Builds a profile unlockLayout snapshot (anchors + size matches + phantom
--- bounds). CONTRACT: unlockLayout snapshots hold BASELINE links only -- the
--- restore side writes them into the live globals and resets the active
--- unlock-layer pointer, ASSERTING baseline. While a spec/conditional
--- group's unlock layer is live, the live globals hold that layer's links:
--- snapshotting them raw stamped a group fork as the profile's "baseline",
--- and the next layer harvest banked the fork into baselineLayout
--- permanently (the default-layout corruption class). Unlock Save & Exit
--- already honors this via SpecOverrides_UnlockBaselineLinks; every profile
--- snapshot writer must go through here. TBB child-role entries are
--- per-spec bucket data that layers never carry -- they ride from live so a
--- baseline-sourced snapshot does not drop them (mirrors ApplyLayer).
local function SnapshotUnlockLayout()
    if not CludesUIDB then return nil end
    local ba, bwm, bhm, bwx, bhx
    if CUI.SpecOverrides_UnlockBaselineLinks then
        ba, bwm, bhm, bwx, bhx = CUI.SpecOverrides_UnlockBaselineLinks()
    end
    local layoutSnap = {
        anchors = CopyDeep(ba or CludesUIDB.unlockAnchors or {}),
        widthMatch = CopyDeep(bwm or CludesUIDB.unlockWidthMatch or {}),
        heightMatch = CopyDeep(bhm or CludesUIDB.unlockHeightMatch or {}),
        -- Match extras ride with the links, from the same source.
        widthMatchExtra = CopyDeep(bwx or CludesUIDB.unlockWidthMatchExtra or {}),
        heightMatchExtra = CopyDeep(bhx or CludesUIDB.unlockHeightMatchExtra or {}),
        phantomBounds = CopyDeep(CludesUIDB.phantomBounds or {}),
    }
    if ba then
        for key, val in pairs(CludesUIDB.unlockAnchors or {}) do
            if type(key) == "string" and key:find("^TBB_%d+$") then
                layoutSnap.anchors[key] = CopyDeep(val)
            end
        end
        for key, val in pairs(CludesUIDB.unlockWidthMatch or {}) do
            if type(key) == "string" and key:find("^TBB_%d+$") then layoutSnap.widthMatch[key] = val end
        end
        for key, val in pairs(CludesUIDB.unlockHeightMatch or {}) do
            if type(key) == "string" and key:find("^TBB_%d+$") then layoutSnap.heightMatch[key] = val end
        end
        for key, val in pairs(CludesUIDB.unlockWidthMatchExtra or {}) do
            if type(key) == "string" and key:find("^TBB_%d+$") then layoutSnap.widthMatchExtra[key] = val end
        end
        for key, val in pairs(CludesUIDB.unlockHeightMatchExtra or {}) do
            if type(key) == "string" and key:find("^TBB_%d+$") then layoutSnap.heightMatchExtra[key] = val end
        end
    end
    return layoutSnap
end

--- Stamp-on-first-touch: a profile with NO unlockLayout snapshot gets one
--- recorded the moment it is activated, sourced from the current (baseline-
--- resolved) live links. This replaces the old "leave the live unlock data
--- untouched" inherit: the inherited links were never RECORDED, so they
--- mutated with every subsequent switch, got baked into whatever profile was
--- switched away from next, and broke the restore contract that snapshots
--- always hold baseline links. Callers stamp BEFORE flipping activeProfile
--- so the baseline source resolves against the OUTGOING store (the store the
--- live tables actually belong to). Brand-new profiles also receive the
--- castbar anchor/width-match defaults the old first-touch branch seeded.
local function StampUnlockLayoutIfMissing(profileTbl)
    if not profileTbl or profileTbl.unlockLayout ~= nil then return end
    local layoutSnap = SnapshotUnlockLayout()
    if not layoutSnap then return end
    local CB_DEFAULTS = {
        { cb = "playerCastbar", parent = "player" },
        { cb = "targetCastbar", parent = "target" },
        { cb = "focusCastbar", parent = "focus" },
        { cb = "petCastbar", parent = "pet" },
    }
    for _, def in ipairs(CB_DEFAULTS) do
        if not layoutSnap.anchors[def.cb] then
            layoutSnap.anchors[def.cb] = { target = def.parent, side = "BOTTOM" }
        end
        if not layoutSnap.widthMatch[def.cb] then layoutSnap.widthMatch[def.cb] = def.parent end
    end
    profileTbl.unlockLayout = layoutSnap
end

--- Re-point all db.profile references to the given profile name.
--- Called when switching profiles so addons see the new data immediately.
local function RepointAllDBs(profName)
    if not CludesUIDB.profiles then CludesUIDB.profiles = {} end
    if type(CludesUIDB.profiles[profName]) ~= "table" then CludesUIDB.profiles[profName] = {} end
    local profileRec = CludesUIDB.profiles[profName]
    if not profileRec.addons then profileRec.addons = {} end

    -- Sync handoff: pull synced module data from the outgoing profile into the incoming
    -- one, so a group member is current the moment it loads. activeProfile is already
    -- set to the new name by callers, so the copy MUST source from the registry's
    -- not-yet-repointed profile name -- SyncModuleToProfiles cannot be used here (it
    -- sources from the active profile, which is already the incoming one). Mirror
    -- group: the pull only happens when BOTH the outgoing and the incoming profile are
    -- members of the module's group; a profile outside the group never pushes into it.
    local sm = CludesUIDB.syncedModules
    if sm then
        local registryTbl = CUI.Lite and CUI.Lite._dbRegistry
        local outName = registryTbl and registryTbl[1] and registryTbl[1]._profileName or "Default"
        local outProf = CludesUIDB.profiles[outName]
        if outProf and outProf.addons and outName ~= profName then
            for moduleFolder, syncTargets in pairs(sm) do
                if
                    type(syncTargets) == "table"
                    and syncTargets[profName]
                    and syncTargets[outName]
                    and outProf.addons[moduleFolder]
                then
                    -- Override-owned settings never sync: merge both profiles'
                    -- override-entry paths into the static exclusions
                    -- (fail-open -- a derive error keeps the static set).
                    local exclusions = CUI._syncExclusions and CUI._syncExclusions[moduleFolder]
                    local exFn = CUI._SyncExclusionsWithOverrides
                    if exFn then
                        local success, m = pcall(exFn, moduleFolder, exclusions, outProf, profileRec)
                        if success and m then exclusions = m end
                    end
                    local destination = profileRec.addons[moduleFolder]
                    if not (exclusions and next(exclusions)) then
                        profileRec.addons[moduleFolder] = CopyDeep(outProf.addons[moduleFolder])
                    elseif type(destination) == "table" then
                        -- Overlay leaf-by-leaf so excluded keys (including
                        -- nested and wildcard paths) keep the dest's values
                        CUI._SelectiveOverlay(outProf.addons[moduleFolder], destination, exclusions, CopyDeep)
                    else
                        -- First sync to this profile: no dest values to preserve
                        profileRec.addons[moduleFolder] =
                            CUI._SelectiveCopy(outProf.addons[moduleFolder], exclusions)
                    end
                end
            end
        end
    end

    local registryTbl = CUI.Lite and CUI.Lite._dbRegistry
    if not registryTbl then return end
    for _, saved in ipairs(registryTbl) do
        local moduleFolder = saved.folder
        if moduleFolder then
            if type(profileRec.addons[moduleFolder]) ~= "table" then profileRec.addons[moduleFolder] = {} end
            saved.profile = profileRec.addons[moduleFolder]
            saved._profileName = profName
            -- Re-merge defaults so new profile has all keys
            if saved._profileDefaults then
                CUI.Lite.DeepMergeDefaults(saved.profile, saved._profileDefaults)
            end
        end
    end
    -- Restore unlock layout from the profile. Callers stamp a missing snapshot BEFORE
    -- flipping activeProfile (see StampUnlockLayoutIfMissing); this is the last-resort
    -- stamp for any flow that missed it. By now the flip already happened, so the
    -- baseline source resolves against the INCOMING store -- for a truly snapshot-less
    -- profile that store is empty and the stamp records raw live (the old inherit, but
    -- RECORDED: the links stop mutating on every switch and the baseline restore
    -- contract holds from here on).
    local layout = profileRec.unlockLayout
    if not layout then
        StampUnlockLayoutIfMissing(profileRec)
        layout = profileRec.unlockLayout
    end
    if layout then
        CludesUIDB.unlockAnchors = CopyDeep(layout.anchors or {})
        CludesUIDB.unlockWidthMatch = CopyDeep(layout.widthMatch or {})
        CludesUIDB.unlockHeightMatch = CopyDeep(layout.heightMatch or {})
        CludesUIDB.phantomBounds = CopyDeep(layout.phantomBounds or {})
        -- Match extras always restore with the links: a snapshot without them
        -- restores none, never the outgoing profile's.
        CludesUIDB.unlockWidthMatchExtra = CopyDeep(layout.widthMatchExtra or {})
        CludesUIDB.unlockHeightMatchExtra = CopyDeep(layout.heightMatchExtra or {})
        -- unlockLayout snapshots always carry BASELINE links (CommitPositions
        -- sources them from the stored baseline layout while a group layer is
        -- live), so live now holds the baseline: reset the incoming profile's
        -- active-layer pointer to match. SpecOverrides_ApplyUnlock re-applies
        -- the right group layer for the incoming spec right after.
        if CUI.SpecOverrides_UnlockResetActive then CUI.SpecOverrides_UnlockResetActive(profileRec) end
        -- Buff Manager forks have NO baseline snapshot restore (the RF addon
        -- profile is the live data and travels with the blob), so their
        -- pointer stays consistent -- only orphan pointers are healed.
        if CUI.SpecOverrides_BmResetActive then CUI.SpecOverrides_BmResetActive(profileRec) end
        if CUI.SpecOverrides_DmResetActive then CUI.SpecOverrides_DmResetActive(profileRec) end
        -- Tracking Bar link entries in the snapshot are stale copies of whichever spec
        -- last saved unlock mode -- TBB links are per-spec (CDM-owned buckets).
        -- Re-assert the active spec's own entries over the freshly restored stores.
        if CUI._TBBRestoreUnlockLinks then CUI._TBBRestoreUnlockLinks() end
    end
    -- (Castbar anchor defaults for brand-new profiles are seeded into the
    -- stamped snapshot by StampUnlockLayoutIfMissing and arrive via the
    -- restore above -- re-seeding live on every load would clobber a user's
    -- deliberate un-anchor the next time the profile is applied.)
    -- Restore fonts and custom colors from the profile
    if profileRec.fonts then
        local fontsDB = CUI.GetFontsDB()
        for key in pairs(fontsDB) do
            fontsDB[key] = nil
        end
        for key, val in pairs(profileRec.fonts) do
            fontsDB[key] = CopyDeep(val)
        end
        if fontsDB.global == nil then fontsDB.global = CUI.DEFAULT_FONT_NAME end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow" end
        -- The fonts DB was just rewritten in place; drop the resolution cache.
        CUI.InvalidateFontCache()
    end
    -- Custom colors: a section with "Apply to All Profiles" ON (default) keeps its
    -- shared palette whatever the active profile, so nothing to re-apply on switch.
    -- A per-profile section (toggle OFF) DOES change with the active profile, so
    -- re-apply when any section is per-profile. GetCustomColorsDB() resolves the
    -- right tables LIVE (edits write straight to the profiles' own customColors --
    -- never a wipe/restore, which is what once let a combat-end spec switch reset
    -- colours). ApplyColorsToOUF self-guards combat on its action-bar branch.
    if CludesUIDB and CUI.AnyColorSectionPerProfile() and CUI.ApplyColorsToOUF then CUI.ApplyColorsToOUF() end
    -- Dark Mode settings are ALWAYS per-profile, so the active profile's dark
    -- palette + darken amounts change on every repoint. Re-read and repaint.
    -- RefreshDarkMode() also runs ApplyColorsToOUF, so the (possibly different)
    -- darken propagates to class/power colours even in global colour mode.
    CUI.RefreshDarkMode()
    -- Number Format is per-profile too: drop the resolved configs and redraw.
    CUI.RefreshNumberFormat()
    -- Sidebar sync icons key off the ACTIVE profile's group membership;
    -- re-evaluate them on every repoint (switch/create/delete/rename/import)
    if CUI._syncRefreshFns then
        for _, func in pairs(CUI._syncRefreshFns) do
            func()
        end
    end
    -- The account-wide window skins follow the whole-UI look of the profile
    -- now active (Blizz UI Enhanced; nil while that module is disabled).
    -- Skins install at load: the switch sites offer the reload.
    if CUI.ReconcileWindowSkinLook then CUI.ReconcileWindowSkinLook() end
end

-------------------------------------------------------------------------------
--  ResolveSpecProfile
--
--  Single authoritative function that resolves the current spec's target
--  profile name. Used by both PreSeedSpecProfile (before OnEnable) and the
--  runtime spec event handler.
--
--  Resolution order:
--    1. Cached spec from lastSpecByChar (reliable across sessions)
--    2. Live C_SpecializationInfo.GetSpecialization() API (available after ADDON_LOADED for
--       returning characters, may be nil for brand-new characters)
--
--  Returns: targetProfileName, resolvedSpecID, charKey  -- or nil if no
--           spec assignment exists or spec cannot be resolved yet.
-------------------------------------------------------------------------------
local function ResolveSpecProfile()
    if not CludesUIDB then return nil end
    local specProfiles = CludesUIDB.specProfiles
    if not specProfiles or not next(specProfiles) then return nil end

    local characterKey = CUI.CharKey(" - ", CludesUIDB.lastSpecByChar)
    if not CludesUIDB.lastSpecByChar then CludesUIDB.lastSpecByChar = {} end

    -- Prefer cached spec from last session (always reliable)
    local resolvedSpec = CludesUIDB.lastSpecByChar[characterKey]

    -- Fall back to live API if no cached value
    if not resolvedSpec then
        local specIndex = C_SpecializationInfo.GetSpecialization()
        if specIndex and specIndex > 0 then
            local liveSpecID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
            if liveSpecID then
                resolvedSpec = liveSpecID
                CludesUIDB.lastSpecByChar[characterKey] = resolvedSpec
            end
        end
    end

    if not resolvedSpec then return nil end

    -- SpecFor: WoW Forever reports one spec per class; its class counts as
    -- every retail spec (the first assigned one in class order wins).
    local destProfile = specProfiles[CUI.SpecFor(resolvedSpec, CUI.SpecHasEntry, specProfiles)]
    if not destProfile then return nil end

    local profileNames = CludesUIDB.profiles
    if not profileNames or not profileNames[destProfile] then return nil end

    return destProfile, resolvedSpec, characterKey
end

-------------------------------------------------------------------------------
--  Spec profile pre-seed
--
--  Runs once just before child addon OnEnable calls, after all OnInitialize
--  calls have completed (so all NewDB calls have run).
--  At this point the spec API is available, so we can resolve the current
--  spec and re-point all db.profile references to the correct profile table
--  in the central store before any addon builds its UI.
--
--  This is the sole pre-OnEnable resolution point. NewDB reads activeProfile
--  as-is (defaults to "Default" or whatever was saved from last session).
-------------------------------------------------------------------------------

--- Called by CludesUI_Lite just before child addon OnEnable calls fire.
--- Uses ResolveSpecProfile() to determine the correct profile, then
--- re-points all db.profile references via RepointAllDBs.
function CUI.PreSeedSpecProfile()
    local destProfile, resolvedSpec = ResolveSpecProfile()
    if not destProfile then
        -- No spec assignment resolved; lock auto-save if spec profiles exist
        if CludesUIDB and CludesUIDB.specProfiles and next(CludesUIDB.specProfiles) then
            CUI._profileSaveLocked = true
        end
        return
    end

    -- Stamp BEFORE the flip: the baseline source must resolve against the
    -- OUTGOING store the live link tables belong to.
    StampUnlockLayoutIfMissing(CludesUIDB.profiles and CludesUIDB.profiles[destProfile])
    CludesUIDB.activeProfile = destProfile
    RepointAllDBs(destProfile)
    CUI._preSeedComplete = true
end

--- Get the live profile table for an addon.
--- All addons use _dbRegistry (which points into
--- CludesUIDB.profiles[active].addons[folder]).
local function GetAddonProfile(record)
    if CUI.Lite and CUI.Lite._dbRegistry then
        for _, saved in ipairs(CUI.Lite._dbRegistry) do
            if saved.folder == record.folder then return saved.profile end
        end
    end
    return nil
end

--- Snapshot the current state of all loaded addons into a profile data table
function CUI.SnapshotAllAddons()
    local body = { addons = {} }
    for _, record in ipairs(ADDON_DB_MAP) do
        -- Host-aware: Dragon Riding's folder is not a loadable addon (it lives
        -- inside BlizzardSkin), so a bare IsAddonLoaded(entry.folder) would drop
        -- it from every full-profile export. IsModuleAddonLoaded resolves through
        -- the hostAddon, matching the per-addon export path (ExportProfile).
        if CUI.IsModuleAddonLoaded(record.folder) then
            local activeProfile = GetAddonProfile(record)
            if activeProfile then body.addons[record.folder] = CopyDeep(activeProfile) end
        end
    end
    -- Include global font and color settings
    body.fonts = CopyDeep(CUI.GetFontsDB())
    local cc = CUI.GetCustomColorsDB()
    body.customColors = CopyDeep(cc)
    -- Dark Mode palette + darken amounts (always the active profile's own).
    body.darkMode = CopyDeep(CUI.GetDarkModeDB())
    body.numberFormat = CopyDeep(CUI.GetNumberFormatDB())
    -- Spec Overrides ride with the profile (freshen the current spec's stored
    -- values from live first so exports never lag recent edits).
    if CUI.SpecOverrides_HarvestCurrent then CUI.SpecOverrides_HarvestCurrent() end
    do
        local profileTbl = CludesUIDB
            and CludesUIDB.profiles
            and CludesUIDB.profiles[CludesUIDB.activeProfile or "Default"]
        if profileTbl and type(profileTbl.specOverrides) == "table" and #profileTbl.specOverrides > 0 then
            body.specOverrides = CopyDeep(profileTbl.specOverrides)
        end
        if
            profileTbl
            and type(profileTbl.specOverrideGroups) == "table"
            and #profileTbl.specOverrideGroups > 0
        then
            body.specOverrideGroups = CopyDeep(profileTbl.specOverrideGroups)
            body.specOverrideNextId = profileTbl.specOverrideNextId
        end
        if
            profileTbl
            and type(profileTbl.condOverrideGroups) == "table"
            and #profileTbl.condOverrideGroups > 0
        then
            body.condOverrideGroups = CopyDeep(profileTbl.condOverrideGroups)
        end
        if profileTbl and type(profileTbl.condOverrides) == "table" and #profileTbl.condOverrides > 0 then
            body.condOverrides = CopyDeep(profileTbl.condOverrides)
        end
        if profileTbl and type(profileTbl.condUnlockOverrides) == "table" then
            body.condUnlockOverrides = CopyDeep(profileTbl.condUnlockOverrides)
        end
        if profileTbl and type(profileTbl.specUnlockOverrides) == "table" then
            body.specUnlockOverrides = CopyDeep(profileTbl.specUnlockOverrides)
        end
        if profileTbl and type(profileTbl.condBmOverrides) == "table" then
            body.condBmOverrides = CopyDeep(profileTbl.condBmOverrides)
        end
        if profileTbl and type(profileTbl.specBmOverrides) == "table" then
            body.specBmOverrides = CopyDeep(profileTbl.specBmOverrides)
        end
        if profileTbl and type(profileTbl.condDmOverrides) == "table" then
            body.condDmOverrides = CopyDeep(profileTbl.condDmOverrides)
        end
        if profileTbl and type(profileTbl.specDmOverrides) == "table" then
            body.specDmOverrides = CopyDeep(profileTbl.specDmOverrides)
        end
        if profileTbl and type(profileTbl.unlockOverrideAnchors) == "table" then
            body.unlockOverrideAnchors = CopyDeep(profileTbl.unlockOverrideAnchors)
        end
    end
    -- Include unlock mode layout data (anchors, size matches). Baseline-
    -- sourced while a group layer is live (see SnapshotUnlockLayout).
    if CludesUIDB then
        body.unlockLayout = SnapshotUnlockLayout()
        -- UI accent color (per-profile). Serialize the RESOLVED accent so an
        -- imported profile reproduces the source's visible accent regardless of
        -- whether it came from an explicit per-profile value or the fallback.
        local u, red, green, blue = CUI.ResolveProfileAccent(CUI.GetActiveProfileData())
        -- Serialize useClass explicitly (false included) so an imported custom
        -- profile reports the right mode to the swatch on a character whose
        -- global useClassAccentColor is true.
        body.cuiAccent = { useClass = u, custom = (not u) and { r = red, g = green, b = blue } or nil }
    end
    return body
end

--- Apply imported profile data into the live db.profile tables.
--- Used by import to write external data into the active profile.
--- For normal profile switching, use SwitchProfile (which calls RepointAllDBs).
function CUI.ApplyProfileData(profileRec)
    if not profileRec or not profileRec.addons then return end

    -- An open unlock session's snapshots and pending edits belong to the
    -- OUTGOING data about to be replaced: discard-close before the wipe
    -- (mirrors SwitchProfile / spec changes / condition flips).
    if CUI._unlockModeSessionActive and CUI.ForceCloseUnlockDiscard then CUI.ForceCloseUnlockDiscard() end

    -- Any open editing-as session (spec group / conditional / Default view) must close
    -- BEFORE the live tables are wiped and refilled: the exits bank against the
    -- outgoing store, and the post-apply establish (Conditions_MarkStale + Recheck)
    -- refuses to run under a live session, which would strand the incoming profile
    -- un-overlaid ("bricked") until the next zone change.
    if CUI.SpecOverrides_CloseEditSessions then CUI.SpecOverrides_CloseEditSessions() end

    -- Build a folder -> db lookup from the Lite registry
    local dbByFolder = {}
    if CUI.Lite and CUI.Lite._dbRegistry then
        for _, saved in ipairs(CUI.Lite._dbRegistry) do
            if saved.folder then dbByFolder[saved.folder] = saved end
        end
    end

    for _, record in ipairs(ADDON_DB_MAP) do
        local layoutSnap = profileRec.addons[record.folder]
        if layoutSnap and IsAddonLoaded(record.folder) then
            local saved = dbByFolder[record.folder]
            if saved then
                local activeProfile = saved.profile
                -- CDM spell content (barSpells, TBB, barGlows) lives in the
                -- per-profile store at spellAssignments.profiles[name], NOT in
                -- this profile blob. No save/restore needed here: ImportProfile
                -- sets the new profile's bucket directly, and on a profile switch
                -- the live accessor + RefreshAllAddons rebuild pick it up.
                for key in pairs(activeProfile) do
                    activeProfile[key] = nil
                end
                for key, val in pairs(layoutSnap) do
                    activeProfile[key] = CopyDeep(val)
                end
                -- Pre-dropdown imports carry showPlayerAbsorb as the legacy boolean
                -- toggle. The conversion migrations are SKIPPED for imported profiles
                -- (inherited migration flags), and a boolean reaches the texture
                -- resolver as a key -- which used to abort unit frame init outright.
                -- The resolver now refuses non-string keys, so this is no longer fatal,
                -- but without the conversion the absorb still renders as a fallback
                -- texture instead of honouring the setting. Normalise on the way in,
                -- matching the mapping the migrations use.
                if record.folder == "CludesUIUnitFrames" then
                    for _, unitCfg in pairs(activeProfile) do
                        if type(unitCfg) == "table" then
                            local v = unitCfg.showPlayerAbsorb
                            if v == true then
                                unitCfg.showPlayerAbsorb = "striped"
                            elseif v ~= nil and type(v) ~= "string" then
                                unitCfg.showPlayerAbsorb = "none"
                            end
                        end
                    end
                end
                -- Pre-split imports carry the shared totPet table but no
                -- targettarget/focustarget. The login split migration is SKIPPED
                -- for imported profiles (ImportProfile builds merged =
                -- DeepCopy(current), which inherits the current profile's
                -- migration flags), so forward-copy here -- BEFORE
                -- DeepMergeDefaults would otherwise fill in DEFAULT minis.
                if record.folder == "CludesUIUnitFrames" and type(activeProfile.totPet) == "table" then
                    if activeProfile.targettarget == nil then
                        activeProfile.targettarget = CopyDeep(activeProfile.totPet)
                    end
                    if activeProfile.focustarget == nil then
                        activeProfile.focustarget = CopyDeep(activeProfile.totPet)
                    end
                end
                -- Old-profile imports carry customized boss regular text keys
                -- but no simple* twins. Simple Debuff Display defaults ON and
                -- reads the simple* keys, which DeepMergeDefaults fills with
                -- false/14, orphaning the user's stored sizes. The seed
                -- migration (uf_boss_simple_text_seed_v1) is SKIPPED for
                -- imported profiles (inherited migration flags), so
                -- forward-copy here BEFORE the merge masks the nil keys.
                if record.folder == "CludesUIUnitFrames" and type(activeProfile.boss) == "table" then
                    local bossCfg = activeProfile.boss
                    if
                        bossCfg.simpleDebuffCooldownTextSize == nil
                        and type(bossCfg.debuffCooldownTextSize) == "number"
                        and bossCfg.debuffCooldownTextSize ~= 10
                    then
                        bossCfg.simpleDebuffCooldownTextSize = bossCfg.debuffCooldownTextSize
                    end
                    if
                        bossCfg.simpleDebuffShowCooldownText == nil
                        and bossCfg.debuffShowCooldownText == true
                    then
                        bossCfg.simpleDebuffShowCooldownText = true
                    end
                    if
                        bossCfg.simpleBuffCooldownTextSize == nil
                        and type(bossCfg.buffCooldownTextSize) == "number"
                        and bossCfg.buffCooldownTextSize ~= 10
                    then
                        bossCfg.simpleBuffCooldownTextSize = bossCfg.buffCooldownTextSize
                    end
                    if bossCfg.simpleBuffShowCooldownText == nil and bossCfg.buffShowCooldownText == true then
                        bossCfg.simpleBuffShowCooldownText = true
                    end
                end
                -- Pre-MultiBag imports carry the legacy bagDefaultOneBag boolean
                -- but no bagDefaultBagType. The conversion migration is SKIPPED for
                -- imported profiles (inherited migration flags), so forward-copy
                -- here BEFORE DeepMergeDefaults fills the "all" default and masks
                -- the legacy key from the resolver.
                if
                    record.folder == "CludesUIBags"
                    and activeProfile.bagDefaultBagType == nil
                    and activeProfile.bagDefaultOneBag == true
                then
                    activeProfile.bagDefaultBagType = "onebag"
                end
                -- Pre-split imports carry the legacy single miniboss color but no
                -- boss color. The mini-boss/boss split migration is SKIPPED for
                -- imported profiles (inherited migration flags), so forward-copy
                -- here BEFORE DeepMergeDefaults fills the DEFAULT boss color and
                -- changes the user's boss nameplates.
                if
                    record.folder == "CludesUINameplates"
                    and activeProfile.boss == nil
                    and type(activeProfile.miniboss) == "table"
                then
                    activeProfile.boss = CopyDeep(activeProfile.miniboss)
                end
                -- Pre-dropdown imports carry the legacy coordsBelow / clockInside /
                -- zoneInside toggles but none of the new mode keys. The minimap
                -- migrations are SKIPPED for imported profiles (inherited migration
                -- flags), so forward-copy here BEFORE DeepMergeDefaults fills the new
                -- defaults and masks the legacy keys.
                if record.folder == "CludesUIMinimap" and type(activeProfile.minimap) == "table" then
                    local minimapCfg = activeProfile.minimap
                    if minimapCfg.coordsMode == nil then
                        if minimapCfg.coordsBelow then
                            minimapCfg.coordsMode = "always"
                            minimapCfg.coordsPosition = "belowMap"
                        else
                            minimapCfg.coordsMode = "hover"
                            minimapCfg.coordsPosition = "topLeft"
                            -- The X/Y nudge only applied in below-map mode; clear
                            -- leftovers so they don't shift the hover coordinates.
                            minimapCfg.coordsBelowOffsetX = nil
                            minimapCfg.coordsBelowOffsetY = nil
                        end
                    end
                    -- Only pre-dropdown exports (no mode key) are mapped: a post-update
                    -- export can carry a stale showClock/ hideZoneText alongside a
                    -- deliberately-set mode, which must win. Hidden via the removed
                    -- Show Blizzard Elements Zone/Clock checkboxes maps to "none".
                    if minimapCfg.clockMode == nil then
                        if minimapCfg.showClock == false then
                            minimapCfg.clockMode = "none"
                        else
                            minimapCfg.clockMode = (minimapCfg.clockInside == false) and "edge" or "inside"
                        end
                    end
                    if minimapCfg.locationMode == nil then
                        if minimapCfg.hideZoneText == true then
                            minimapCfg.locationMode = "none"
                        else
                            minimapCfg.locationMode = minimapCfg.zoneInside and "inside" or "edge"
                        end
                    end
                    if minimapCfg.omniumFolioMode == nil then
                        minimapCfg.omniumFolioMode = (minimapCfg.showOmniumFolio == false) and "never"
                            or "always"
                    end
                end
                -- Pre-enum imports carry the legacy anchorFirstRow boolean but
                -- no rowGrowDirection. The conversion migration
                -- (cdm_row_grow_direction_v1) is SKIPPED for imported profiles
                -- (inherited migration flags), so forward-copy here so the
                -- pinned-row behavior survives the import.
                if
                    record.folder == "CludesUICooldownManager"
                    and type(activeProfile.cdmBars) == "table"
                    and type(activeProfile.cdmBars.bars) == "table"
                then
                    for _, barRec in ipairs(activeProfile.cdmBars.bars) do
                        if barRec.anchorFirstRow then
                            if barRec.rowGrowDirection == nil then
                                barRec.rowGrowDirection = barRec.verticalOrientation and "RIGHT" or "DOWN"
                            end
                            barRec.anchorFirstRow = nil
                        end
                    end
                end
                if saved._profileDefaults then
                    CUI.Lite.DeepMergeDefaults(activeProfile, saved._profileDefaults)
                end
                -- Ensure per-unit bg colors are never nil after import
                if record.folder == "CludesUIUnitFrames" then
                    local UF_UNITS = { "player", "target", "focus", "boss", "pet", "totPet" }
                    local DEF_BG = 17 / 255
                    for _, uKey in ipairs(UF_UNITS) do
                        local cfg = activeProfile[uKey]
                        if cfg and cfg.customBgColor == nil then
                            cfg.customBgColor = { r = DEF_BG, g = DEF_BG, b = DEF_BG }
                        end
                    end
                end
            end
        end
    end
    -- Apply fonts (account-wide store) ONLY when the profile carries a font
    -- snapshot. A partial import nils profileData.fonts to keep the recipient's
    -- own fonts -- wiping unconditionally here reset them to the default
    -- (Expressway/shadow) instead. Mirrors SwitchProfile's guarded restore.
    -- Custom colours are getter-redirected (GetCustomColorsDB) and must NEVER be
    -- wiped/restored here (see the custom-colours global-mode design).
    if profileRec.fonts then
        local fontsDB = CUI.GetFontsDB()
        for key in pairs(fontsDB) do
            fontsDB[key] = nil
        end
        for key, val in pairs(profileRec.fonts) do
            fontsDB[key] = CopyDeep(val)
        end
        if fontsDB.global == nil then fontsDB.global = CUI.DEFAULT_FONT_NAME end
        if fontsDB.outlineMode == nil then fontsDB.outlineMode = "shadow" end
        -- The fonts DB was just rewritten in place; drop the resolution cache.
        CUI.InvalidateFontCache()
    end
    -- Custom colors are GLOBAL appearance, not per-profile: never wipe or restore
    -- CludesUIDB.customColors from a profile snapshot. (See the detailed note in the
    -- sibling apply path; this block previously wiped the live colors UNCONDITIONALLY
    -- before a conditional restore, so applying a profile with no/stale color snapshot
    -- reset every custom color to default.) Restore unlock mode layout data
    if CludesUIDB then
        local layout = profileRec.unlockLayout
        if layout then
            CludesUIDB.unlockAnchors = CopyDeep(layout.anchors or {})
            CludesUIDB.unlockWidthMatch = CopyDeep(layout.widthMatch or {})
            CludesUIDB.unlockHeightMatch = CopyDeep(layout.heightMatch or {})
            CludesUIDB.phantomBounds = CopyDeep(layout.phantomBounds or {})
            -- Match extras always restore with the links (none when absent).
            CludesUIDB.unlockWidthMatchExtra = CopyDeep(layout.widthMatchExtra or {})
            CludesUIDB.unlockHeightMatchExtra = CopyDeep(layout.heightMatchExtra or {})
            -- Tracking Bar link entries in the snapshot are stale copies of
            -- whichever spec last saved unlock mode -- TBB links are
            -- per-spec (CDM-owned buckets). Re-assert the active spec's own
            -- entries over the freshly restored stores.
            if CUI._TBBRestoreUnlockLinks then CUI._TBBRestoreUnlockLinks() end
        end
        -- If profile predates unlockLayout, leave live data untouched
    end
    -- Re-resolve + apply the UI accent for the now-active profile so an applied
    -- (imported) profile's accent takes effect immediately, consistent with the
    -- fonts/colors applied above. activeProfile is already repointed before
    -- ApplyProfileData runs, so this reads the correct profile's cuiAccent and
    -- falls back to the frozen global root when none is set.
    CUI.RefreshAccent()
end

--- Per-module refresh steps for RefreshAllAddons, in load-bearing order.
--- Kept as an array of closures so the budgeted path can run each step (or a
--- time-boxed slice of steps) as its own watchdog execution. Every step is a
--- stateless re-apply reading the LIVE db at call time, so a step firing a
--- frame or two after the swap reads the same settled data the synchronous
--- path would have.
local REFRESH_ADDON_STEPS = {
    -- ResourceBars (full rebuild)
    function()
        if _G._CURB_Apply then _G._CURB_Apply() end
    end,
    -- CDM: skip during spec-profile switch. CDM's SPELLS_CHANGED handler
    -- will detect the spec key mismatch and rebuild with the correct spec.
    -- Running it here would race with that rebuild.
    function()
        if not CUI._specProfileSwitching then
            if _G._CUCME_LoadSpecProfile and _G._CUCME_GetCurrentSpecKey then
                local curKey = _G._CUCME_GetCurrentSpecKey()
                if curKey then _G._CUCME_LoadSpecProfile(curKey) end
            end
            if _G._CUCME_Apply then _G._CUCME_Apply() end
        end
    end,
    -- Cursor (style + position), Crosshair, Self Combat Text, and the QoL
    -- extras (FPS counter + Secondary Stats -- one call for both: the FPS
    -- readout may be drawn by the Secondary Stats block, so the two owners
    -- re-evaluate together).
    function()
        if _G._CUCL_Apply then _G._CUCL_Apply() end
        if _G._CUCL_ApplyTrail then _G._CUCL_ApplyTrail() end
        if _G._CUCL_ApplyGCDCircle then _G._CUCL_ApplyGCDCircle() end
        if _G._CUCL_ApplyCastCircle then _G._CUCL_ApplyCastCircle() end
        if CUI._applyCrosshair then CUI._applyCrosshair() end
        if CUI._applySelfCombatText then CUI._applySelfCombatText() end
        if CUI._applyUpgradeTooltips then CUI._applyUpgradeTooltips() end
        if CUI._applyFPSDisplay then
            CUI._applyFPSDisplay()
        elseif CUI._applySecondaryStats then
            CUI._applySecondaryStats()
        end
    end,
    -- QoL Battle Res and Bloodlust (enable state, visibility, position;
    -- neither exists on WoW Forever)
    function()
        if _G._CUI_BattleRes_Apply then _G._CUI_BattleRes_Apply() end
        if _G._CUI_Bloodlust_Apply then _G._CUI_Bloodlust_Apply() end
    end,
    -- AuraBuffReminders (style + refresh + position)
    function()
        if _G._CUABR_UpdateGroupAuraRegistration then _G._CUABR_UpdateGroupAuraRegistration() end
        if _G._CUABR_ApplyAllIconBorders then _G._CUABR_ApplyAllIconBorders() end
        if _G._CUABR_RequestRefresh then _G._CUABR_RequestRefresh() end
        if _G._CUABR_ApplyUnlockPos then _G._CUABR_ApplyUnlockPos() end
    end,
    -- ActionBars (style + layout + position)
    function()
        if _G._CUAB_Apply then _G._CUAB_Apply() end
    end,
    -- UnitFrames (style + layout + position)
    function()
        if _G._CUUF_ReloadFrames then _G._CUUF_ReloadFrames() end
    end,
    -- Raid Frames + Party Frames (style + layout + size; positions re-applied
    -- by the tail)
    function()
        if _G._CURF_RefreshAll then _G._CURF_RefreshAll() end
    end,
    -- Nameplates
    function()
        if _G._CUNP_RefreshAllSettings then _G._CUNP_RefreshAllSettings() end
    end,
    -- Quest Tracker
    function()
        if _G._CUQT_RefreshAll then _G._CUQT_RefreshAll() end
    end,
    -- Chat (sidebar icons, borders, fonts, visibility)
    function()
        if _G._CUCHAT_RefreshAll then _G._CUCHAT_RefreshAll() end
    end,
    -- Chat Bubbles (Blizz UI Enhanced; settings on the profile root)
    function()
        if _G._CUBS_RefreshChatBubbles then _G._CUBS_RefreshChatBubbles() end
    end,
    -- Bags (window order, categories and the Junk Marker follow the selected
    -- profile immediately)
    function()
        if _G.CUI_Bags and _G.CUI_Bags.ApplyWindowLayering then _G.CUI_Bags:ApplyWindowLayering() end
        if _G.CUI_Bags and _G.CUI_Bags.OnProfileApplied then _G.CUI_Bags:OnProfileApplied() end
    end,
    -- Friends List + Mythic Timer
    function()
        if _G._CUFR_ApplyFriends then _G._CUFR_ApplyFriends() end
        -- An open friends list repaints its decoration with the new profile:
        -- the legacy list's row pass, then the 12.1 cards and stock rows.
        if _G._CUFR_ProcessFriendButtons then _G._CUFR_ProcessFriendButtons() end
        if _G._CUFR_RedecorateTiles then _G._CUFR_RedecorateTiles() end
        if _G._CUMT_Apply then _G._CUMT_Apply() end
    end,
    -- Damage Meters
    function()
        if _G._CUDM_Apply then _G._CUDM_Apply() end
    end,
    -- DataBars (bar set + blocks + layout + positions are all per-profile)
    function()
        if _G._CUDB_Apply then _G._CUDB_Apply() end
    end,
    -- Quickdraw (enable state + palette count drive the override bindings),
    -- Dragon Riding HUD, Minimap (flyout button state)
    function()
        if _G._CUQD_Apply then _G._CUQD_Apply() end
        if _G._CUDR_Rebuild then _G._CUDR_Rebuild() end
        if _G._CUMIN_RefreshFlyout then _G._CUMIN_RefreshFlyout() end
    end,
    -- Global class/power colors (updates oUF, nameplates, raid frames)
    function() CUI.ApplyColorsToOUF() end,
    -- Re-register unlock elements for all modules whose bar sets can
    -- differ between profiles. Without this, _applySavedPositions uses
    -- stale registrations from the outgoing profile and anchors fail
    -- for elements that only exist in the incoming profile (they land
    -- at CENTER/CENTER = screen center).
    function()
        if _G._CUCME_RegisterUnlock then _G._CUCME_RegisterUnlock() end
        if _G._CUCME_RegisterTBBUnlock then _G._CUCME_RegisterTBBUnlock() end
        if _G._CURB_RegisterUnlock then _G._CURB_RegisterUnlock() end
        if _G._CUABR_RegisterUnlock then _G._CUABR_RegisterUnlock() end
        if _G._CUCL_RegisterUnlock then _G._CUCL_RegisterUnlock() end
        if _G._CUI_BattleRes_RegisterUnlock then _G._CUI_BattleRes_RegisterUnlock() end
        if _G._CUDB_RegisterUnlock then _G._CUDB_RegisterUnlock() end
    end,
}

--- Completion tail shared by both RefreshAllAddons drivers. In the budgeted
--- path this runs from the drain's final execution, so its ordering
--- guarantees ("after all addons have rebuilt") hold identically.
local function RefreshAllAddonsTail()
    -- After all addons have rebuilt and positioned their frames from
    -- db.profile.positions, re-apply centralized grow-direction positioning (handles
    -- lazy migration of imported TOPLEFT positions to CENTER format) and resync anchor
    -- offsets so the anchor relationships stay correct for future drags.
    -- Triple-deferred so it runs AFTER debounced rebuilds have completed and frames are
    -- at final positions. Position re-application and anchor resync are deferred to
    -- OnSpecSwitchComplete (if spec switching) or run inline here for non-spec profile
    -- switches (manual switch from options). This also clears _abAnchorSuppressed
    -- (inside _applySavedPositions), so the suppression window spans every
    -- module step regardless of driver.
    if not CUI._specProfileSwitching then
        C_Timer.After(0, function()
            C_Timer.After(0, function()
                if CUI._applySavedPositions then CUI._applySavedPositions() end
                if CUI.ResyncAnchorOffsets then CUI.ResyncAnchorOffsets() end
            end)
        end)
    end
    -- The open options window caches per-profile pages (e.g. the CDM bar
    -- dropdown). A live profile swap re-points db.profile but leaves those cached
    -- pages showing the OLD profile until a /reload. Drop the cache so any page
    -- rebuilds fresh on next view, and rebuild the one on screen now. The profile
    -- DROPDOWN switch already does this inline; routing it through here also
    -- covers profile keybind + spec-driven auto-swaps, which only call us.
    CUI:InvalidatePageCache()
    if CUI:IsShown() and CUI.RefreshPage then CUI:RefreshPage(true) end
    -- Conditional overrides: a profile apply swaps every store wholesale, so
    -- the engine's applied pointer refers to the OLD profile's groups. Reset
    -- it and re-establish the overlay against the incoming profile.
    if CUI.Conditions_MarkStale then
        CUI.Conditions_MarkStale()
        CUI.Conditions_Recheck()
    end
    -- If CDM is loaded, it calls OnSpecSwitchComplete from ProcessSpecChange
    -- after its SPELLS_CHANGED rebuild finishes. If CDM is NOT loaded,
    -- complete immediately since there's nothing to wait for.
    local cdmLoaded = C_AddOns
        and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("CludesUICooldownManager")
    if not cdmLoaded then CUI.OnSpecSwitchComplete() end
end

--- Trigger live refresh on all loaded addons after a profile apply.
--- `budgeted` true runs the module steps through CludesUI.RunBudgeted --
--- each step (or time-boxed slice of steps) in its own script-watchdog
--- execution -- so a full-suite refresh can never hit 12.1's "script ran too
--- long" on slow machines. Pass it ONLY from MANUAL swap sites (profile
--- dropdown, profile keybind, options spec-assign apply): spec-DRIVEN
--- switches must stay synchronous, because CDM's SPELLS_CHANGED pipeline
--- calls OnSpecSwitchComplete on its own clock and could otherwise apply
--- saved positions mid-drain, before some modules have re-applied.
function CUI.RefreshAllAddons(budgeted)
    -- Spec Overrides: write the current spec's override values into the live
    -- profile FIRST, so every module refresh below picks them up. This makes
    -- profile swaps and imports override-correct without their own pass.
    -- (The import-time default re-bank runs SYNCHRONOUSLY inside
    -- ImportProfile, never from here: by the time any RefreshAllAddons fires,
    -- overlays may already be live and re-banking would poison defaults.)
    -- The whole preamble stays in the caller's execution in both drivers:
    -- these are cheap flag/value writes that later steps depend on.
    if CUI.SpecOverrides_ApplyValues then CUI.SpecOverrides_ApplyValues() end
    -- Suppress stale anchor moves on AB bars during the rebuild phase. LayoutBar
    -- positions them from the new profile's barPositions; resize hooks would reposition
    -- them with old-profile offsets (1-frame blink). Separate flag from
    -- _applyingSavedPositions so CDM's early-return in ApplyAnchorPosition (which
    -- checks _applyingSavedPositions) isn't triggered prematurely by the wider window.
    CUI._abAnchorSuppressed = true
    -- Phase 3: RefreshAllAddons runs on a real profile apply (swap/import) and on
    -- a per-spec-profile spec switch -- both load a NEW cdmBarPositions table with
    -- its own saved edges + follow baselines, so clear the follow-ready flag.
    -- Anchored CDM growth bars then re-pin to the new profile's absolute edge
    -- (delta 0) until that profile's chain settles and the settle debounce re-arms
    -- follow. A SHARED-profile spec change does NOT call RefreshAllAddons, so the
    -- flag stays set there and the bars track the sliding target smoothly.
    CUI._anchorFollowReady = nil
    -- Re-resolve + apply the UI accent color for the now-active profile BEFORE
    -- child modules refresh, since several re-read GetAccentColor() during their
    -- own apply (chat, cursor, mythic timer, glows, borders). Per-profile accent
    -- falls back to the frozen global root, so swapping profiles never changes
    -- the accent for users who never set a per-profile one.
    CUI.RefreshAccent()
    if budgeted and CUI.RunBudgeted then
        CUI.RunBudgeted(REFRESH_ADDON_STEPS, 8, RefreshAllAddonsTail)
    else
        for i = 1, #REFRESH_ADDON_STEPS do
            REFRESH_ADDON_STEPS[i]()
        end
        RefreshAllAddonsTail()
    end
end

--- Called by CDM (or RefreshAllAddons if CDM not loaded) when the spec
--- switch rebuild is fully settled. Clears the suppression flag and
--- re-applies width/height matches so all matched frames pick up
--- the new profile dimensions.
function CUI.OnSpecSwitchComplete()
    CUI._specProfileSwitching = false
    -- Unlock spec-overrides: perform any deferred generic-element position
    -- writes and the override settle BEFORE the matches/positions/resync
    -- below, so this pass lays out against the final swapped stores.
    if CUI.SpecOverrides_FlushUnlock then CUI.SpecOverrides_FlushUnlock() end
    if CUI.ApplyAllWidthHeightMatches then CUI.ApplyAllWidthHeightMatches() end
    if CUI._applySavedPositions then CUI._applySavedPositions() end
    if CUI.ResyncAnchorOffsets then CUI.ResyncAnchorOffsets() end
    -- A conditional establish/flip that found the spec pipeline mid-flight
    -- deferred itself (the transition handler returns false while busy).
    -- The pipeline is settled now -- resolve it. No-op when nothing changed.
    if CUI.Conditions_Recheck then CUI.Conditions_Recheck() end
end

-------------------------------------------------------------------------------
--  Profile Keybinds
--  Each profile can have a key bound to switch to it instantly.
--  Stored in CludesUIDB.profileKeybinds = { ["Name"] = "CTRL-1", ... }
--  Uses hidden buttons + SetOverrideBindingClick, same pattern as Party Mode.
-------------------------------------------------------------------------------
local _profileBindBtns = {} -- [profileName] = hidden Button

local function GetProfileKeybinds()
    if not CludesUIDB then CludesUIDB = {} end
    if not CludesUIDB.profileKeybinds then CludesUIDB.profileKeybinds = {} end
    return CludesUIDB.profileKeybinds
end

local function EnsureProfileBindBtn(profName)
    if _profileBindBtns[profName] then return _profileBindBtns[profName] end
    local safeName = profName:gsub("[^%w]", "")
    local button = CreateFrame("Button", "CludesUIProfileBind_" .. safeName, UIParent)
    button:Hide()
    button:SetScript("OnClick", function()
        local isActive = CUI.GetActiveProfileName()
        if isActive == profName then return end
        local _, profileNames = CUI.GetProfileList()
        local fontWillChange = CUI.ProfileChangesFont(profileNames and profileNames[profName])
        local skinsWillChange = CUI.ProfileChangesWindowSkins(profileNames and profileNames[profName])
        local styleWillChange = CUI.ProfileChangesStyle(profileNames and profileNames[profName])
        CUI.SwitchProfile(profName)
        -- true = budgeted: manual swap site, watchdog-sliced module refresh.
        CUI.RefreshAllAddons(true)
        if fontWillChange or skinsWillChange or styleWillChange then
            CUI:ShowConfirmPopup({
                title = "Reload Required",
                message = fontWillChange and "Font changed. A UI reload is needed to apply the new font."
                    or skinsWillChange and "Window skins changed for this profile. A UI reload is needed to apply them."
                    or "Style changed for this profile. A UI reload is needed to apply it.",
                confirmText = "Reload Now",
                cancelText = "Later",
                reload = true,
            })
        else
            CUI:RefreshPage()
        end
    end)
    _profileBindBtns[profName] = button
    return button
end

function CUI.SetProfileKeybind(profName, entryKey)
    local bindings = GetProfileKeybinds()
    -- Clear old binding for this profile
    local oldKey = bindings[profName]
    local button = EnsureProfileBindBtn(profName)
    if oldKey then ClearOverrideBindings(button) end
    if entryKey then
        bindings[profName] = entryKey
        SetOverrideBindingClick(button, true, entryKey, button:GetName())
    else
        bindings[profName] = nil
    end
end

function CUI.GetProfileKeybind(profName)
    local bindings = GetProfileKeybinds()
    return bindings[profName]
end

--- Called on login to restore all saved profile keybinds
function CUI.RestoreProfileKeybinds()
    local bindings = GetProfileKeybinds()
    for profName, entryKey in pairs(bindings) do
        if entryKey then
            local button = EnsureProfileBindBtn(profName)
            SetOverrideBindingClick(button, true, entryKey, button:GetName())
        end
    end
end

--- Update keybind references when a profile is renamed
function CUI.OnProfileRenamed(previousName, nextName)
    local bindings = GetProfileKeybinds()
    local entryKey = bindings[previousName]
    if entryKey then
        local oldBtn = _profileBindBtns[previousName]
        if oldBtn then ClearOverrideBindings(oldBtn) end
        _profileBindBtns[previousName] = nil
        bindings[previousName] = nil
        bindings[nextName] = entryKey
        local newBtn = EnsureProfileBindBtn(nextName)
        SetOverrideBindingClick(newBtn, true, entryKey, newBtn:GetName())
    end
end

--- Clean up keybind when a profile is deleted
function CUI.OnProfileDeleted(profName)
    local bindings = GetProfileKeybinds()
    if bindings[profName] then
        local button = _profileBindBtns[profName]
        if button then ClearOverrideBindings(button) end
        _profileBindBtns[profName] = nil
        bindings[profName] = nil
    end
end

--- Returns true if applying profileData would change the global font or outline mode.
--- Used to decide whether to show a reload popup after a profile switch.
function CUI.ProfileChangesFont(profileRec)
    if not profileRec or not profileRec.fonts then return false end
    local current = CUI.GetFontsDB()
    local curFont = current.global or CUI.DEFAULT_FONT_NAME
    local curOutline = current.outlineMode or "shadow"
    local newFont = profileRec.fonts.global or CUI.DEFAULT_FONT_NAME
    local newOutline = profileRec.fonts.outlineMode or "shadow"
    -- "none" and "shadow" are both drop-shadow (no outline) -- treat as identical
    if curOutline == "none" then curOutline = "shadow" end
    if newOutline == "none" then newOutline = "shadow" end
    return curFont ~= newFont or curOutline ~= newOutline
end

--- Returns true if switching to profileData would cross the per-profile
--- "Disable Window Skins" flag in either direction. Skins install at load,
--- so a crossing needs a UI reload to fully apply -- callers pair this with
--- the same reload popup as the font check above. Must be called BEFORE
--- the switch (compares the CURRENT active profile root against the target).
function CUI.ProfileChangesWindowSkins(profileRec)
    if type(profileRec) ~= "table" then return false end
    local current = CUI.GetActiveProfileData()
    local a = (current and current.disableWindowSkins) and true or false
    local b = profileRec.disableWindowSkins and true or false
    if a ~= b then return true end
    -- The whole-UI window look (Blizz UI Enhanced; nil while it is disabled):
    -- the switch swaps the account's window skins to the incoming profile's
    -- look, which only installs at the next load.
    local lookOf = CUI.ProfileWindowSkinLook
    if lookOf then
        local incoming = lookOf(profileRec)
        local slots = CludesUIDB and CludesUIDB.windowSkinStyleSlots
        local live = type(slots) == "table" and slots.active or "cui"
        if incoming and incoming ~= live then return true end
    end
    return false
end

--- Returns true if switching to profileData would give any module a different
--- style (Global Settings > Style: CludesUI, Blizzard Style or Classic WoW
--- UI, plus WoW Forever on that client) from the look it is rendering.
--- Styles are reload-gated: each module latches its style key at load and
--- keeps that look until the UI reloads, so callers pair this with the same
--- reload popup as the font check above. Must be called BEFORE the switch
--- (the Action Bars flags, which have no latch, are read live from the
--- outgoing profile).
-- Each surface carries a Blizzard flag and a sibling Classic flag; the style
-- key reads classic when the Classic flag is set, else blizzard when the
-- Blizzard flag is, else cui. `active` names the module's latched key getter;
-- optional `extra` names a module getter that is handed the incoming module
-- profile and returns true when another latched, reload-gated choice would
-- change (Raid Frames: the Party page's Frame Style). `data` names the
-- incoming profile's addons key when it is not the module folder (the
-- Skyriding HUD's own DB inside Blizz UI Enhanced); `retailOnly` skips the entry on WoW
-- Forever (no Style row there, its getter always reads cui or is absent).
-- `forever` (read on the Forever client only) names the sibling flag of the
-- WoW Forever variant of Blizzard Style (set together with the Blizzard flag)
-- and, on a latched module, `foreverActive` its getter that says the variant
-- renders (Action Bars reads the flag live like its other flags); only the
-- modules whose variant draws differently (Forever-only pieces, or that
-- client's own art where plain Blizzard Style draws the retail sheets) carry
-- them, so a profile that differs only by the variant prompts where the look
-- changes. Every other module reads the variant as Blizzard Style on both
-- sides.
local STYLE_FLAGS = {
    {
        folder = "CludesUIActionBars",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        forever = "useForeverStyle",
    },
    {
        folder = "CludesUIUnitFrames",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        active = "UF_Style",
        forever = "useForeverStyle",
        foreverActive = "UF_Forever",
    },
    {
        folder = "CludesUIUnitFrames",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "playerAuraBars",
        active = "PAB_Style",
    },
    {
        folder = "CludesUINameplates",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        active = "NP_Style",
        forever = "useForeverStyle",
        foreverActive = "NP_Forever",
    },
    {
        folder = "CludesUICooldownManager",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        active = "CdmIconStyle",
        forever = "useForeverStyle",
        foreverActive = "CdmIconsForever",
    },
    {
        folder = "CludesUICooldownManager",
        key = "useBlizzardStyleBars",
        classic = "useClassicStyleBars",
        active = "CdmBarStyle",
        forever = "useForeverStyleBars",
        foreverActive = "CdmBarsForever",
    },
    {
        folder = "CludesUIResourceBars",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "castBar",
        active = "ERB_CastStyle",
        forever = "useForeverStyle",
        foreverActive = "ERB_CastForever",
    },
    {
        folder = "CludesUIResourceBars",
        key = "useBlizzardStyleBars",
        classic = "useClassicStyleBars",
        active = "ERB_BarsStyle",
    },
    {
        folder = "CludesUIMinimap",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "minimap",
        active = "MinimapStyle",
        forever = "useForeverStyle",
        foreverActive = "MinimapForever",
        extra = "MinimapFvBorderChanged",
    },
    {
        folder = "CludesUIDamageMeters",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "dm",
        active = "DMStyle",
        forever = "useForeverStyle",
        foreverActive = "DMForever",
        extra = "DMFvBorderChanged",
    },
    {
        folder = "CludesUIQuestTracker",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "questTracker",
        active = "QT_Style",
    },
    {
        folder = "CludesUIFriends",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "friends",
        active = "FR_Style",
    },
    {
        folder = "CludesUIChat",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        sub = "chat",
        active = "ChatStyle",
        forever = "useForeverStyle",
        foreverActive = "ChatForeverFlag",
        extra = "ChatFvBorderChanged",
    },
    {
        folder = "CludesUIRaidFrames",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        active = "RF_Style",
        extra = "RF_PartyKitChanged",
    },
    {
        folder = "CludesUIBlizzardSkin",
        key = "useBlizzardStyle",
        classic = "useClassicStyle",
        data = "CludesUIDragonRiding",
        retailOnly = true,
        active = "EDR_Style",
    },
}
local function StyleKeyOfFlags(profile, f)
    if type(profile) ~= "table" then return "cui" end
    if profile[f.classic] then return "classic" end
    if profile[f.key] then
        if f.forever and CUI.IS_FOREVER and profile[f.forever] then return "forever" end
        return "blizzard"
    end
    return "cui"
end
-- The style one surface renders this session, from its module ns `mns`: the
-- module's latched key ("forever" where its Forever latch says the variant
-- renders), or Action Bars' live flags. nil with no getter (Action Bars: no
-- profile yet).
local function RenderedStyleOf(f, moduleNames)
    if f.active then
        local func = moduleNames[f.active]
        if not func then return nil end
        local current = func()
        if current ~= "blizzard" and current ~= "classic" then current = "cui" end
        -- The WoW Forever variant renders under a "blizzard" latch.
        if current == "blizzard" and f.foreverActive and CUI.IS_FOREVER then
            local ff = moduleNames[f.foreverActive]
            if ff and ff() then current = "forever" end
        end
        return current
    end
    local ABAR = moduleNames.EAB
    local p = ABAR and ABAR.db and ABAR.db.profile
    if p then return StyleKeyOfFlags(p, f) end
    return nil
end
function CUI.ProfileChangesStyle(profileRec)
    if type(profileRec) ~= "table" or type(profileRec.addons) ~= "table" then return false end
    local registryTbl = CUI._ModuleNS
    if not registryTbl then return false end
    -- Bags' WoW Forever style: the incoming profile's own Bags pick, else the
    -- look most of its modules use (BagsForeverWanted).
    local bags = CUI.IS_FOREVER and registryTbl.CludesUIBags
    if bags and bags.BagsForeverWanted then
        local incoming = profileRec.addons.CludesUIBags
        local wanted =
            bags.BagsForeverWanted(type(incoming) == "table" and incoming or nil, profileRec.addons)
        if bags.BagsForever() ~= wanted then return true end
    end
    for i = 1, #STYLE_FLAGS do
        local f = STYLE_FLAGS[i]
        local moduleNames = registryTbl[f.folder]
        if moduleNames and not (f.retailOnly and CUI.IS_FOREVER) then
            local current = RenderedStyleOf(f, moduleNames)
            if current ~= nil then
                local incoming = profileRec.addons[f.data or f.folder]
                if f.sub and type(incoming) == "table" then incoming = incoming[f.sub] end
                if current ~= StyleKeyOfFlags(incoming, f) then return true end
                -- `extra`: a reload-gated choice under the same style (the
                -- module's own getter compares it; true = it would change).
                local extra = f.extra and moduleNames[f.extra]
                if type(extra) == "function" and extra(type(incoming) == "table" and incoming or nil) then
                    return true
                end
            end
        end
    end
    return false
end

--- The look every loaded styleable surface renders this session: "cui",
--- "blizzard", "classic" or, on WoW Forever, "forever". false when the loaded
--- modules render different looks, nil when none is loaded. A WoW Forever
--- surface with no variant of its own draws Blizzard Style under either
--- Blizzard look, so it fits both; with only such surfaces loaded, the
--- Forever flag the look switch sets beside the Blizzard one tells them apart.
function CUI.RenderedLook()
    local registryTbl = CUI._ModuleNS
    if not registryTbl then return nil end
    local style, eitherBlizz
    for i = 1, #STYLE_FLAGS do
        local f = STYLE_FLAGS[i]
        local moduleNames = registryTbl[f.folder]
        if moduleNames and not (f.retailOnly and CUI.IS_FOREVER) then
            local current = RenderedStyleOf(f, moduleNames)
            if current == "blizzard" and not f.forever and CUI.IS_FOREVER then
                eitherBlizz = f
            elseif current ~= nil then
                if style == nil then
                    style = current
                elseif style ~= current then
                    return false
                end
            end
        end
    end
    if eitherBlizz then
        if style == nil then
            local f = eitherBlizz
            local p = CUI.GetActiveProfileData()
            local tbl = p and type(p.addons) == "table" and p.addons[f.data or f.folder] or nil
            if f.sub and type(tbl) == "table" then tbl = tbl[f.sub] end
            if type(tbl) == "table" and tbl[(f.key:gsub("Blizzard", "Forever", 1))] then return "forever" end
            return "blizzard"
        end
        if style ~= "blizzard" and style ~= "forever" then return false end
    end
    return style
end

--- WoW Forever: true when more than half of the loaded modules' styleable
--- surfaces are on the WoW Forever look in a profile's addons table (nil = the
--- active profile's): the Blizzard flag set with its Forever sibling, which a
--- surface with no variant of its own also carries beside the Blizzard flag (as
--- RenderedLook reads it); the Classic flag wins. Bags' WoW Forever style
--- follows it while the profile has no Bags style picked. false off the Forever
--- client and with no loaded surface. Reads settings only.
function CUI.ForeverLookMajority(addonMap)
    if not CUI.IS_FOREVER then return false end
    if addonMap == nil then
        local p = CUI.GetActiveProfileData()
        addonMap = p and p.addons
    end
    local registryTbl = CUI._ModuleNS
    if type(addonMap) ~= "table" or not registryTbl then return false end
    local sum, forever = 0, 0
    for i = 1, #STYLE_FLAGS do
        local f = STYLE_FLAGS[i]
        if registryTbl[f.folder] and not f.retailOnly then
            sum = sum + 1
            local tbl = addonMap[f.data or f.folder]
            if f.sub and type(tbl) == "table" then tbl = tbl[f.sub] end
            if
                type(tbl) == "table"
                and tbl[f.key]
                and not tbl[f.classic]
                and tbl[f.forever or (f.key:gsub("Blizzard", "Forever", 1))]
            then
                forever = forever + 1
            end
        end
    end
    return forever * 2 > sum
end

-------------------------------------------------------------------------------
--  Export / Import
--  Format: !CUI_<base64 encoded compressed serialized data>
--  The data table contains:
--    { version = 3, type = "full", data = profileData }
--  plus client = "forever" on a string made on WoW Forever (none = retail).
-------------------------------------------------------------------------------
local EXPORT_PREFIX = "!CUI_"

-------------------------------------------------------------------------------
--  Strings in the older export format
--
--  They use the same layout under a different prefix, with older names
--  inside them (addon keys, unlock-element keys, style keys, media paths).
--  Import accepts them and rewrites those names to the current ones on the
--  decoded table, never on the serialized text: strings there are
--  length-prefixed. Export always writes our own prefix.
-------------------------------------------------------------------------------
local FOREIGN_PREFIX = "!E" .. "UI_"
local OLD_UP, OLD_CAP, OLD_LOW = "ELLES" .. "MERE", "Elles" .. "mere", "elles" .. "mere"

local function IsForeignString(importText) return importText:sub(1, #FOREIGN_PREFIX) == FOREIGN_PREFIX end

local function TranslateForeignName(text)
    if
        not (
            text:find("EUI", 1, true)
            or text:find("eui", 1, true)
            or text:find(OLD_LOW, 1, true)
            or text:find(OLD_CAP, 1, true)
            or text:find(OLD_UP, 1, true)
        )
    then
        return text
    end
    text = text:gsub(OLD_UP, "CLUDES"):gsub(OLD_CAP, "Cludes"):gsub(OLD_LOW, "cludes")
    -- "EUI" not after a capital, "eui" not after a letter (so words such as
    -- the French "seuil" in a user's own text stay as they are).
    text = text:gsub("%f[%u]EUI", "CUI"):gsub("%f[%a]eui", "cui")
    return text
end

local function TranslateForeignPayload(v)
    local kind = type(v)
    if kind == "string" then return TranslateForeignName(v) end
    if kind ~= "table" then return v end
    local output = {}
    for key, value in pairs(v) do
        output[TranslateForeignPayload(key)] = TranslateForeignPayload(value)
    end
    return output
end

--- Stamps the client an export string is made on at the payload root:
--- "forever" on WoW Forever, nothing on retail, so every older string reads
--- as retail. Transport only: no import ever stores it in a profile.
function CUI.StampPayloadClient(bundle)
    if CUI.IS_FOREVER then bundle.client = "forever" end
    return bundle
end

--- True when a decoded payload was made on the other client (retail vs WoW
--- Forever). Cooldown Manager spell data from the other client is never
--- imported: the import runs exactly as for a string that carries none.
function CUI.PayloadFromOtherClient(bundle)
    local from = type(bundle) == "table" and bundle.client or nil
    return (from or "retail") ~= (CUI.IS_FOREVER and "forever" or "retail")
end

--- The reload prompt text after an import, plus one line when the string
--- carried the other client's Cooldown Manager spells (not imported).
function CUI.ImportReloadMessage(bundle)
    local msg = CUI.L("Reload to finish importing.")
    local body = type(bundle) == "table" and bundle.data
    local entryKey = CUI.IsFullAccountPayload(bundle) and "spellAssignments" or "cdmSpells"
    if type(body) == "table" and body[entryKey] ~= nil and CUI.PayloadFromOtherClient(bundle) then
        msg = msg .. "\n\n" .. CUI.L("Cooldown Manager spells from the other game client were not imported.")
    end
    return msg
end

--- WoW Forever export: a class whose snapshot holds its Forever spec key
--- (read first on Forever, so the layout the exporter sees) carries it under
--- the class's first retail key, which retail reads and Forever resolves.
--- Modifies the caller's own snapshot table in place. Retail: no-op.
function CUI.ForeverAliasCDMSpecs(layoutSnap)
    if not CUI.IS_FOREVER or type(layoutSnap) ~= "table" then return end
    local classes = CUI.ForeverClasses()
    for c = 1, #classes do
        local nameToken = classes[c]
        local lk = tostring(CUI.FOREVER_CLASS_SPEC[nameToken])
        if layoutSnap[lk] ~= nil then
            layoutSnap[tostring(CUI.ForeverClassSpecIDs(nameToken)[1])] = layoutSnap[lk]
            layoutSnap[lk] = nil
        end
    end
end

--- WoW Forever import: for every class the incoming string carries, drop each
--- INHERITED key the class would read before the string's first key (its
--- Forever spec key, then its retail specs in class order), so the class
--- resolves to the incoming layout instead of a copy of the active profile's.
--- Inherited keys after that one, and classes the string does not carry, are
--- kept. Touches only the new bucket the import is building. Retail: no-op.
function CUI.ForeverDropShadowedLegacy(inherited, incoming)
    if not CUI.IS_FOREVER or type(inherited) ~= "table" or type(incoming) ~= "table" then return end
    local classes = CUI.ForeverClasses()
    for c = 1, #classes do
        local nameToken = classes[c]
        local lk = tostring(CUI.FOREVER_CLASS_SPEC[nameToken])
        -- A string carrying the Forever key overlays it; nothing shadows it.
        if incoming[lk] == nil then
            local ids = CUI.ForeverClassSpecIDs(nameToken)
            local first
            for i = 1, #ids do
                if incoming[tostring(ids[i])] ~= nil then
                    first = i
                    break
                end
            end
            -- Drop every inherited key the class reads before the first carried one.
            if first then
                inherited[lk] = nil
                for i = 1, first - 1 do
                    inherited[tostring(ids[i])] = nil
                end
            end
        end
    end
end

-- Snapshot the per-profile CDM spell allocation (which spells sit on which bars +
-- per-spell settings, per spec) for export. The bar DEFINITIONS already travel in
-- the addon blob; this carries the content that sits on them. Strips the sharer's
-- ghost bar + migration flags so the importer rebuilds ghosting against THEIR own
-- tracked spells. Returns nil when there's nothing to carry, or when the CDM addon
-- itself isn't part of a subset export.
local function SnapshotProfileCDMSpells(profName, includedFolders, cdmSpecs)
    if includedFolders and not includedFolders["CludesUICooldownManager"] then return nil end
    -- Reconcile the ACTIVE spec's default-bar store against the live icons
    -- before snapshotting: untouched base-bar spells render via the
    -- frames-as-truth fallback without being recorded, and an export taken
    -- before the login reseed ran would ship them missing (the importer's
    -- ghost pass then hides them). No-ops when the CDM child is disabled,
    -- when an import's ghosting is pending, or when no live icons exist.
    if CUI.CDMReconcileActiveSpecSpells then CUI.CDMReconcileActiveSpecSpells() end
    local spellAssign = CludesUIDB and CludesUIDB.spellAssignments
    local specBucket = spellAssign and spellAssign.profiles and spellAssign.profiles[profName]
    if not specBucket or type(specBucket.specProfiles) ~= "table" or not next(specBucket.specProfiles) then
        return nil
    end
    -- cdmSpecs (a set keyed by string specKey) limits the export to the chosen
    -- specs; nil = every spec with data.
    local layoutSnap = {}
    for specKey, specProfile in pairs(specBucket.specProfiles) do
        if type(specProfile) == "table" and (not cdmSpecs or cdmSpecs[specKey]) then
            local duplicate = CopyDeep(specProfile)
            if type(duplicate.barSpells) == "table" then duplicate.barSpells.__ghost_cd = nil end
            duplicate._barFilterModelV6 = nil
            duplicate._importGhostMode = nil
            layoutSnap[specKey] = duplicate
        end
    end
    if not next(layoutSnap) then return nil end
    CUI.ForeverAliasCDMSpecs(layoutSnap)
    return layoutSnap
end

-- Collect the spec IDs the account-global spec->profile map currently points at
-- this profile. Embedded in every export as a flat list of spec IDs; the importer
-- only applies them when "Auto Assign to Specs" is enabled. Returns nil when the
-- profile is not assigned to any spec (the common case), so the field is absent.
local function CollectAssignedSpecs(profName)
    local specProfiles = CludesUIDB and CludesUIDB.specProfiles
    if type(specProfiles) ~= "table" then return nil end
    local entries
    for specId, profileTbl in pairs(specProfiles) do
        if profileTbl == profName then
            entries = entries or {}
            entries[#entries + 1] = specId
        end
    end
    return entries
end

-------------------------------------------------------------------------------
-- Blizz UI Enhanced account-global settings ("Window & Tooltip Skins").
-- These keys live at the TOP LEVEL of CludesUIDB (account-wide, shared by
-- every profile) and cover exactly the first two Blizz UI Enhanced tabs:
-- Window Skins and Tooltips, Menus & Popups. The bundle is OPT-IN on export
-- (Include dropdown, default off) and OPT-IN on import (Include Window Skins
-- checkbox + confirmation), because applying it overwrites the recipient's
-- settings across ALL of their profiles.
--
-- The one list of these settings: a new account-global setting on either tab
-- goes here, so it travels in exports AND the Window Skins reset clears it
-- (that reset reads CludesUI.BLIZZ_SKIN_GLOBAL_KEYS).
--
-- Deliberately absent (state, not settings): lfgSavedRoles (the player's saved LFG
-- roles), charSheetCollapsedSections (transient UI state), characterFramePos /
-- friendsFramePos (dragged panel positions, resolution- bound), tooltipFixedPos (stale
-- account key; the live one is per-profile and rides the profile itself),
-- blizzWindowModernBG (dead key, read nowhere), mailAltRoster / mailAltHidden (the
-- player's own characters and which of them the Mail card's Alt List leaves out).
-------------------------------------------------------------------------------
local BLIZZ_SKIN_GLOBAL_KEYS = {}
do
    local keyList = BLIZZ_SKIN_GLOBAL_KEYS
    local function addFn(entries)
        for _, key in ipairs(entries) do
            keyList[#keyList + 1] = key
        end
    end
    -- Tooltips, Menus & Popups tab
    addFn({
        "customTooltips",
        "tooltipFontScale",
        "tooltipPlayerTitles",
        "tooltipItemLevel",
        "tooltipMythicScore",
        "tooltipShowMount",
        "tooltipShowGuildRank",
        "tooltipShowTarget",
        "tooltipShowMode",
        "tooltipShowModifier",
        "tooltipGrowthDirection",
        "tooltipLevelColor",
        "tooltipClassLineColor",
        "tooltipFactionColor",
        "tooltipGuildmateColor",
        "tooltipCompactLevel",
        "tooltipAFKTag",
        "uberTooltips",
        "uberTooltipsManual",
        "tooltipHideHealthStrip",
        "tooltipHealthStripTexture",
        "tooltipHealthStripHeight",
        "tooltipAnchorCursor",
        "tooltipCursorPosition",
        "tooltipCursorOffsetX",
        "tooltipCursorOffsetY",
        "tooltipShowBuffs",
        "tooltipBuffPosition",
        "tooltipBuffSize",
        "tooltipBuffsPerRow",
        "tooltipBuffOffsetX",
        "tooltipBuffOffsetY",
        "tooltipBgColor",
        "tooltipBgOpacity",
        "tooltipBorderSize",
        "showSpellID",
        "spellIDModifier",
        "showIconID",
        "showItemID",
        "showItemMaxStacks",
        "itemStackModifier",
        "reskinPopupsMenus",
        "reskinGameMenu",
        "reskinQueuePopup",
        "showQueueTimer",
        "queueTimerTextColor",
        "queueTimerTextSize",
        "queueTimerBarHeight",
        "queueTimerTextOffsetY",
        "resurrectAcceptGlow",
        "reskinWidgetBars",
        "widgetBarMinSize",
        "reskinExtraActionButton",
        "popupMenuButtonBackgroundColor",
        "popupMenuButtonTextColorMode",
        "popupMenuButtonTextColor",
        "accentReskinElements",
    })
    -- Shared border-editor key sets (tooltip / popup menu / popup menu button)
    for _, prefixText in ipairs({ "tooltip", "popupMenu", "popupMenuButton", "lootWindow", "lootIcon" }) do
        for _, suffix in ipairs({
            "BorderTexture",
            "BorderThickness",
            "BorderThicknessPx",
            "BorderColor",
            "BorderColorMode",
            "BorderOpacity",
            "BorderOffsetX",
            "BorderOffsetY",
            "BorderShiftX",
            "BorderShiftY",
            "BorderBehind",
        }) do
            keyList[#keyList + 1] = prefixText .. suffix
        end
    end
    -- Window Skins tab: per-window enables + skin styles + shared look
    addFn({
        "themedCharacterSheet",
        "themedInspectSheet",
        "reskinLFGMenu",
        "reskinGreatVault",
        "reskinCollections",
        "reskinPlayerSpells",
        "reskinAdventureGuide",
        "reskinProfessionsBook",
        "reskinProfessions",
        "reskinWorldMap",
        "reskinGuild",
        "reskinCalendar",
        "reskinAchievements",
        "reskinMail",
        "reskinCatalyst",
        "reskinSocket",
        "reskinItemUpgrade",
        "reskinLoot",
        "lootIconBorder",
        "lootWindowBorderQualityColor",
        "reskinLootToast",
        "lootToastQualityStrip",
        "lootToastQualityStripMoney",
        "lootToastScale",
        "reskinBNetToast",
        "reskinLootRoll",
        "reskinLootHistory",
        "reskinGroupInvite",
        "reskinReadyCheck",
        "reskinMicroMenu",
        "reskinBagBar",
        "reskinLegacySystem",
        "reskinHousing",
        "reskinDressUp",
        "reskinTransmog",
        "reskinMerchant",
        "reskinAuctionHouse",
        "reskinMacros",
        "reskinSettings",
        "reskinAddonList",
        "reskinCraftOrders",
        "reskinTrainer",
        "reskinGossip",
        "reskinQuest",
        "reskinInspectRecipe",
        "reskinDelves",
        "reskinSocialUI",
        "reskinQueueStatus",
        "reskinDelvePicker",
        "reskinPlayerChoice",
        "reskinTrade",
        "reskinFlagCarriers",
        -- The per-look window slots ride with the enables they describe.
        "windowSkinStyleSlots",
        "blizzWindowSkinStyles",
        "blizzWindowModernDefault",
        "blizzWinAccentBar",
        "blizzWinBarFill",
        "blizzWinLinks",
        "thirdPartySkinsOff",
        "thirdPartySkinAddons",
    })
    -- Window Skins tab: per-window card options
    addFn({
        -- Character Sheet card
        "statCategoryColors",
        "statCategoryUseColor",
        "statSectionsOrder",
        "showMythicRating",
        "showItemLevel",
        "showUpgradeTrack",
        "showGems",
        "showEnchants",
        "showPvpItemLevel",
        "charSheetSocketPanel",
        "charSheetSeasonPanel",
        "charSheetSeasonVault",
        "charSheetHideSlotFlyoutArrows",
        "charSheetIconZoom",
        "charSheetEnchantNames",
        "charSheetEnchantSize",
        "flyoutItemLevels",
        "flyoutItemStats",
        "charSheetItemStats",
        "flyoutItemStatsTertiary",
        "charSheetItemStatsTertiary",
        "charSheetSocketPanelStats",
        "showCharSheetDurability",
        "charSheetDurabilityLocation",
        "charSheetDurabilityShowLabel",
        "showSecondaryRaw",
        "showSecondaryBoth",
        "showTertiaryRaw",
        "showTertiaryBoth",
        "showAdjustedStats",
        "showManaStat",
        "highlightSecondaryItems",
        "highlightTertiaryItems",
        -- Character Sheet stock styles' "Blizzard UI Color" (the style itself
        -- is per profile, on the profile root, and rides the profile)
        "charSheetBlizzColors",
        -- Inspect card
        "inspectShowEnchants",
        "inspectEnchantNames",
        "inspectEnchantSize",
        "inspectShowItemLevel",
        "inspectShowUpgradeTrack",
        -- LFG / Merchant / Mail cards
        "lfgRememberRoles",
        "merchantShowAsList",
        "merchantListRowHeight",
        "merchantShowItemLevel",
        "merchantBulkBuy",
        "merchantExpand",
        "merchantCols",
        "merchantRows",
        "mailAltList",
        "mailAltListMax",
        "mailAltListMinLevel",
        "mailAltListSort",
        -- Friends List card (WoW Forever: the friend tiles and auto-accept)
        "friendsListCard",
    })
end
-- The Window Skins module's reset clears this same list (plus the state
-- above that it leaves out), so a key added here resets too.
CUI.BLIZZ_SKIN_GLOBAL_KEYS = BLIZZ_SKIN_GLOBAL_KEYS

-- Snapshot the bundle for export. nil-valued keys are simply absent from the
-- snapshot; the import side clears keys absent from the bundle, so the
-- recipient lands on the exporter's EXACT two-tab configuration (absent =
-- that setting's default).
local function SnapshotBlizzSkinGlobals()
    if not CludesUIDB then return nil end
    local output = {}
    for _, key in ipairs(BLIZZ_SKIN_GLOBAL_KEYS) do
        local v = CludesUIDB[key]
        if v ~= nil then output[key] = CopyDeep(v) end
    end
    return output
end

-- Apply an imported bundle: every allowlisted key takes the bundle's value,
-- INCLUDING nil (absent = exporter default), so mixed old/new state can't
-- linger. Keys outside the allowlist are ignored, so a string can never write
-- other account data (saved profiles, click casting, the per-character
-- records). Callers reload right after -- these settings install at load, so
-- no live re-apply is needed or attempted.
function CUI.ApplyBlizzSkinGlobals(bundle)
    if type(bundle) ~= "table" or not CludesUIDB then return end
    for _, key in ipairs(BLIZZ_SKIN_GLOBAL_KEYS) do
        CludesUIDB[key] = CopyDeep(bundle[key])
    end
end

function CUI.ExportProfile(
    profName,
    includedFolders,
    includeLayout,
    includeCDM,
    cdmSpecs,
    includeGlobals,
    includeOverrides,
    includeBlizzSkin
)
    if includeLayout == nil then includeLayout = true end -- default ON
    -- Overrides (value stores + groups + unlock-layer forks + BM forks)
    -- default ON: headless full calls (Wago, partner installers) keep
    -- carrying the complete override system exactly as classic full exports
    -- always did; the export UI passes the user's explicit Include choice.
    if includeOverrides == nil then includeOverrides = true end
    -- CDM spell layouts default ON with every spec included (cdmSpecs nil =
    -- all specs with data). Headless callers -- the Wago UI Packs creator
    -- export and partner installers -- call this bare and must receive a
    -- COMPLETE profile; the opt-in + spec-picker experience belongs to the
    -- options UI, which always passes includeCDM and cdmSpecs explicitly.
    -- (The old nil=OFF default silently shipped every Wago pack without its
    -- CDM spell layouts: the exporter never saw it because the in-game export
    -- flow passes explicit values.)
    if includeCDM == nil then includeCDM = true end
    if includeGlobals == nil then includeGlobals = true end -- default ON ("Include Core Settings")
    -- Blizz UI Enhanced account-global bundle: headless full calls (the Wago
    -- creator export, partner installers) default ON so a pack delivers the
    -- creator's complete look -- there is no UI in that path to opt in. The
    -- export UI always passes its explicit "Window Skins" Include choice
    -- (default off there: manual sharers opt in deliberately).
    if includeBlizzSkin == nil then includeBlizzSkin = true end
    local saved = GetProfilesDB()
    local profileRec = saved.profiles[profName]
    if not profileRec then return nil end
    -- If exporting the active profile, ensure fonts/colors/layout are current
    if profName == (saved.activeProfile or "Default") then
        profileRec.fonts = CopyDeep(CUI.GetFontsDB())
        profileRec.customColors = CopyDeep(CUI.GetCustomColorsDB())
        profileRec.darkMode = CopyDeep(CUI.GetDarkModeDB())
        profileRec.unlockLayout = SnapshotUnlockLayout()
    end
    local exportCopy = CopyDeep(profileRec)
    -- Import-window guard flag (see ImportProfile) is recipient-local state;
    -- never let it ride an export string. The import-flow stamps below it are
    -- payload metadata, never profile data -- strip any stale copies too (the
    -- export re-stamps them deliberately further down).
    exportCopy._importEstablishPending = nil
    exportCopy.overridesIncluded = nil
    exportCopy.overridesExcluded = nil
    exportCopy.partialImport = nil
    exportCopy.layoutExcluded = nil
    exportCopy.blizzSkinGlobals = nil
    exportCopy.applyBlizzSkinGlobals = nil
    exportCopy.applyUIScale = nil
    -- UI accent color (per-profile): serialize the RESOLVED accent for THIS profile
    -- (works for active and non-active profiles; never mutates the stored profile, and
    -- is rename-immune since it is a data-root field, not an addons[] folder key).
    do
        local u, red, green, blue = CUI.ResolveProfileAccent(profileRec)
        -- Serialize useClass explicitly (see SnapshotAllAddons).
        exportCopy.cuiAccent = { useClass = u, custom = (not u) and { r = red, g = green, b = blue } or nil }
    end
    -- UI scale (account-wide) rides with a FULL profile so an importer can opt
    -- to match the scale the profile was designed at. Concrete number; absent
    -- when never set (old profiles carry no scale to exclude). Dropped on a
    -- subset export below alongside the other profile-global appearance.
    exportCopy.uiScale = (CludesUIDB and type(CludesUIDB.ppUIScale) == "number") and CludesUIDB.ppUIScale
        or nil
    -- Only export addons that are actually loaded (supports standalone installs)
    -- When includedFolders is provided, further filter to user's selection
    if exportCopy.addons then
        for moduleFolder in pairs(exportCopy.addons) do
            if not CUI.IsModuleAddonLoaded(moduleFolder) then
                exportCopy.addons[moduleFolder] = nil
            elseif includedFolders and not includedFolders[moduleFolder] then
                exportCopy.addons[moduleFolder] = nil
            end
        end
    end
    -- Exclude spec-specific data from export
    exportCopy.trackedBuffBars = nil
    exportCopy.tbbPositions = nil
    -- Legacy account-wide spell store never travels (the per-profile snapshot below
    -- carries CDM content instead).
    exportCopy.spellAssignments = nil
    -- CDM spell allocation travels WITH the profile: which spells sit on which bars
    -- + per-spell settings, per spec. Bar definitions already ride in the addon blob.
    if includeCDM then
        exportCopy.cdmSpells = SnapshotProfileCDMSpells(profName, includedFolders, cdmSpecs)
    end
    -- Spec->profile assignments (which specs auto-load this profile) ride along as
    -- a flat spec-ID list. Always embedded; the importer only applies it when the
    -- recipient enables "Auto Assign to Specs". nil when unassigned.
    exportCopy.assignedSpecs = CollectAssignedSpecs(profName)
    -- HoverCast (click-cast) bindings are account-global, not per-profile. They
    -- live at CludesUIDB.clickCast (top-level, parallel to spellAssignments),
    -- so importing someone else's profile must never overwrite the user's own
    -- click-cast setup. Strip defensively in case a payload ever carries it.
    exportCopy.clickCast = nil
    -- fonts/customColors/darkMode/cuiAccent are profile-GLOBAL appearance and are
    -- not separable per-addon, so a subset export must not carry them (they'd
    -- clobber the recipient's). Only a full-profile export carries them.
    -- Profile-global appearance (fonts, custom colours, dark mode, accent,
    -- number format) and the account UI scale ride only when "Global Settings" is included
    -- (default ON) -- full and subset exports alike, since the unified export
    -- flow offers the toggle for both (2026-07-20 redesign; the old subset
    -- path dropped uiScale unconditionally, which would have regressed scale
    -- transfer once the separate full-export button was removed). Off = the
    -- recipient keeps their own look and scale.
    if not includeGlobals then
        exportCopy.fonts = nil
        exportCopy.customColors = nil
        exportCopy.darkMode = nil
        exportCopy.numberFormat = nil
        exportCopy.cuiAccent = nil
        exportCopy.uiScale = nil
    end
    -- Blizz UI Enhanced account-global bundle ("Window & Tooltip Skins"):
    -- rides when includeBlizzSkin resolves true -- explicit opt-in from the export UI's
    -- "Window Skins" Include item, or the headless default (see the nil-default above:
    -- Wago packs deliver the creator's complete look). Gated on the module being loaded
    -- so a build without Blizz UI Enhanced never ships an empty bundle. Bundle presence
    -- in a string is therefore always deliberate, which is what lets the importer treat
    -- presence as the apply signal (the import dialog's checkbox strips the bundle for
    -- recipient-side opt-out).
    if includeBlizzSkin and CUI.IsModuleAddonLoaded("CludesUIBlizzardSkin") then
        exportCopy.blizzSkinGlobals = SnapshotBlizzSkinGlobals()
    end
    -- Layout relationships (unlockLayout) are governed by the "Include layout"
    -- toggle and FILTERED per-module: only relationships whose both endpoints are
    -- in the selected modules survive (subset export), and no-checkbox-module
    -- (Dragon Riding) + stale (deleted-bar) edges are always dropped. A canonical
    -- keyToFolder meta rides along so the importer can attribute each edge. Full
    -- export (no includedFolders) keeps all checkbox-module relationships.
    local fLayout, layoutMeta =
        CUI.BuildExportUnlockLayout(exportCopy.unlockLayout, includeLayout, includedFolders)
    exportCopy.unlockLayout = fLayout -- nil when includeLayout is off
    exportCopy.unlockLayoutMeta = layoutMeta -- nil when includeLayout is off
    -- Override system (2026-07-20 redesign): ALL-OR-NOTHING under the single
    -- "Overrides" include. Value stores, group definitions, the spec/cond unlock-layer
    -- FORKS, and the BM forks travel together or not at all -- there is no per-module
    -- override merging anymore (and forks were never per-module separable anyway).
    -- Excluded -> strip everything and stamp overridesExcluded so the importer KEEPS
    -- the recipient's stores instead of reading the stripped nils as "exporter had
    -- none, wipe yours". Included on a SUBSET export -> stamp overridesIncluded: subset
    -- strings default to keep-recipient at import (matching legacy subset behavior), so
    -- carrying overrides needs the positive marker.
    if includeOverrides then
        if includedFolders then exportCopy.overridesIncluded = true end
    else
        exportCopy.specOverrides = nil
        exportCopy.specOverrideGroups = nil
        exportCopy.specOverrideNextId = nil
        exportCopy.condOverrides = nil
        exportCopy.condOverrideGroups = nil
        exportCopy.condOverrideNextId = nil
        exportCopy.specUnlockOverrides = nil
        exportCopy.condUnlockOverrides = nil
        exportCopy.specBmOverrides = nil
        exportCopy.condBmOverrides = nil
        exportCopy.specDmOverrides = nil
        exportCopy.condDmOverrides = nil
        exportCopy.unlockOverrideAnchors = nil
        exportCopy.overridesExcluded = true
    end
    -- Layout deliberately excluded: stamped for the importer's baseline
    -- layout handling (kept for compatibility; fork keep/take is governed by
    -- the overrides stamps above since the 2026-07-20 redesign).
    if not includeLayout then exportCopy.layoutExcluded = true end
    -- A subset export IS a partial import regardless of what the recipient
    -- checks: stamp it at the source so the store merge takes the same
    -- keep-existing subset path the import dialog stamps on deselection.
    if includedFolders then exportCopy.partialImport = true end
    -- Per-character account data (gold ledger, upgrade-calc caches) never rides
    -- a shared string -- see PRIVATE_ADDON_KEYS. exportData is already a deep
    -- copy, so this strips the payload without touching the stored profile.
    StripPrivateAddonData(exportCopy.addons)
    -- Normalize local db.folder keys -> canonical (suite) keys so the string
    -- imports correctly into any build. No-op in the suite (canon == folder).
    exportCopy.addons = AddonsToCanon(exportCopy.addons)
    local bundle = { version = CUI.LayoutExportVersion(exportCopy), type = "full", data = exportCopy }
    CUI.StampPayloadClient(bundle)
    local serialized = Serializer.Serialize(bundle)
    if not LibDeflate then return nil end
    local deflated = LibDeflate:CompressDeflate(serialized)
    local packed = LibDeflate:EncodeForPrint(deflated)
    return EXPORT_PREFIX .. packed
end

-- Public: re-encode a decoded payload back to an import string.
function CUI.EncodePayload(bundle)
    if not bundle then return nil end
    if CUI.LayoutExportVersion(bundle.data) == 4 then bundle.version = 4 end
    local serialized = Serializer.Serialize(bundle)
    if not LibDeflate then return nil end
    local deflated = LibDeflate:CompressDeflate(serialized)
    local packed = LibDeflate:EncodeForPrint(deflated)
    return EXPORT_PREFIX .. packed
end

-------------------------------------------------------------------------------
--  FULL ACCOUNT EXPORT  (separate format, purely additive)
--
--  A string that carries the WHOLE central store: every account-global key
--  plus the ACTIVE profile. The recipient ends up with the exporter's account
--  setup, including everything a normal profile string deliberately refuses
--  to carry -- HoverCast bindings, CDM spell assignments, Quality of Life
--  account settings, unlock anchors and size matches, UI scale, spec
--  assignments, first-install state. Stores keyed by the recipient's own
--  profiles keep the recipient's entries and take only the carried
--  profile's from the string (FULL_IMPORT_MERGE: profile keybinds, sync
--  groups, last-spec records, color pull-from pointers, the other
--  profiles' CDM spell layouts).
--
--  It shares NOTHING with ExportProfile / ImportProfile: no include toggles,
--  no per-module filtering, no canonical re-keying, no store merging, no
--  partial/override stamps. Those functions are untouched and never see a
--  full-account payload -- the import UI routes on the `fullExport` stamp
--  before the normal flow is reached.
--
--  The builder copies the store WHOLESALE and subtracts, rather than listing
--  what to include: any account key added in a future version rides
--  automatically instead of being silently missed.
--
--  Excluded by design -- per-character data that is nobody else's:
--    goldLedger           cross-character and warband gold record
--    qolUpgradeCalcChars  Upgrade Calculator per-character cache
--    xpBarChars           XP bar session clock, XP rate and time this level
--    timePlayedChars      Time Played block: each character's total played time
--    travelHearths        Travel block's Show Other Characters: each character's
--                         hearthstone bind and ready time
--    questWatchChars      WoW Forever quest tools: quests each character's
--                         filters and auto-track moved
--    questTrackerChars    WoW Forever Custom Quest Tracker: each character's
--                         untracked, collapsed, opened and pinned quests
--    mailAltRoster        the Mail card's Alt List: every character recorded
--    mailAltHidden        and the ones its Shown Characters leaves out
--    raidHoroscope        Party Mode's Should I Raid Tonight?: each
--                         character's birthday
--    cdmCachedBarSizes    Cooldown Manager bar sizes cached per character
--    bagCurrencyByChar    Bags' tracked currencies per character
--    bagPinnedByChar      Bags' pinned items per character
--    mageArmorByChar      AuraBuff Reminders (WoW Forever): the mage armor
--                         each character last had up
--    classBuffByChar      and the class buff lines each character last had up
--    spellUprankChars     Forever Essentials' Auto Uprank Spells on Bars: the
--                         highest spell ranks each character and pet has had
--    global               friend groups: the groups, their order and colours,
--                         and each friend's group by BattleTag
--  (The upgrade-calc and gold blobs are what PRIVATE_ADDON_KEYS strips from
--  normal strings, at their current top-level homes. The three legacy gold
--  keys stay listed: until Bags or DataBars loads and absorbs them they are
--  still on disk.) And the game settings this client had
--  before CludesUI, which Uninstall CUI puts back, with the values modules
--  hand back to this client's CVars later:
--    restoreOnUninstall     (CludesUI_Uninstall.lua)
--    gfxBackup              Optimize My FPS and Graphics' Restore values
--    friendlyPlateVisSaved  friendly plates hidden in a follower dungeon
--    chatTellMuted          the whisper sound Chat muted
--  And the inline cogs this user has opened (cogSeen: their notification dots
--  stay for whoever imports the string).
-------------------------------------------------------------------------------
local FULL_EXPORT_TYPE = "fullaccount"
local FULL_EXPORT_EXCLUDED = {
    goldLedger = true,
    dataBarsGold = true,
    characterGold = true,
    warbandGold = true,
    qolUpgradeCalcChars = true,
    xpBarChars = true,
    timePlayedChars = true,
    travelHearths = true,
    restoreOnUninstall = true,
    gfxBackup = true,
    friendlyPlateVisSaved = true,
    chatTellMuted = true,
    groupFinderApps = true,
    questWatchChars = true,
    questTrackerChars = true,
    cdmRepopulatePending = true,
    cdmRepopulateDone = true,
    mailAltRoster = true,
    mailAltHidden = true,
    raidHoroscope = true,
    cdmCachedBarSizes = true,
    bagCurrencyByChar = true,
    bagPinnedByChar = true,
    mageArmorByChar = true,
    classBuffByChar = true,
    spellUprankChars = true,
    global = true,
    cogSeen = true,
}

-- Root stores keyed by profile name (or character) describe the recipient's
-- own profiles. A full import keeps them and takes from the string only the
-- carried profile's entry: fn(own, fromString, carriedName) -> new value.
local function KeepOwn(ownValue) return ownValue end
-- A pointer to one profile: the recipient's stands; the string's is taken only
-- when the recipient has none and it names the carried profile.
local function OwnOrCarried(ownValue, packed, label)
    if ownValue == nil and packed == label then return packed end
    return ownValue
end
local FULL_IMPORT_MERGE = {
    syncedModules = KeepOwn,
    lastSpecByChar = KeepOwn,
    lastNonSpecProfile = OwnOrCarried,
    colorsPullFrom = OwnOrCarried,
    colorsSectionPullFrom = function(ownValue, packed, label)
        if type(ownValue) ~= "table" then ownValue = {} end
        if type(packed) == "table" then
            for section, p in pairs(packed) do
                if p == label and ownValue[section] == nil then ownValue[section] = p end
            end
        end
        return ownValue
    end,
    profileKeybinds = function(ownValue, packed, label)
        if type(ownValue) ~= "table" then ownValue = {} end
        local entryKey = type(packed) == "table" and packed[label]
        if entryKey then
            for num, key in pairs(ownValue) do
                if key == entryKey and num ~= label then return ownValue end
            end
            ownValue[label] = entryKey
        end
        return ownValue
    end,
    spellAssignments = function(ownValue, packed, label)
        if type(packed) ~= "table" then return ownValue end
        if type(ownValue) ~= "table" then ownValue = {} end
        local profileNames = type(ownValue.profiles) == "table" and ownValue.profiles or {}
        for key, val in pairs(packed) do
            if key ~= "profiles" then ownValue[key] = val end
        end
        profileNames[label] = type(packed.profiles) == "table" and packed.profiles[label] or nil
        ownValue.profiles = profileNames
        return ownValue
    end,
}

--- Builds a full-account export string, or nil.
function CUI.ExportFullAccountData()
    if not CludesUIDB then return nil end
    if not LibDeflate then return nil end
    -- Same freshness boundary the profile export uses: bank live override
    -- edits into their stores before snapshotting.
    if CUI.SpecOverrides_HarvestCurrent then CUI.SpecOverrides_HarvestCurrent() end
    local saved = GetProfilesDB()
    local activeProfileName = saved.activeProfile or "Default"
    local output = {}
    for key, val in pairs(CludesUIDB) do
        if key ~= "profiles" and not FULL_EXPORT_EXCLUDED[key] then output[key] = CopyDeep(val) end
    end
    -- ONLY the active profile travels; the exporter's other profiles are
    -- their own business and would overwrite same-named profiles on import.
    output.profiles = {}
    local profileTbl = saved.profiles and saved.profiles[activeProfileName]
    if profileTbl then
        local duplicate = CopyDeep(profileTbl)
        -- Freshen profile-global appearance and the unlock layout from live,
        -- mirroring what ExportProfile does for the active profile -- but on
        -- the COPY. A full export never mutates stored data.
        duplicate.fonts = CopyDeep(CUI.GetFontsDB())
        duplicate.customColors = CopyDeep(CUI.GetCustomColorsDB())
        duplicate.darkMode = CopyDeep(CUI.GetDarkModeDB())
        duplicate.unlockLayout = SnapshotUnlockLayout()
        -- Recipient-local import bookkeeping never rides a string.
        duplicate._importEstablishPending = nil
        -- The gold ledger and Upgrade Calculator cache also have LEGACY homes
        -- inside the module profile blobs (see PRIVATE_ADDON_KEYS); an older
        -- profile can still carry them there, and they are excluded from a
        -- full export at every address they have ever lived at.
        StripPrivateAddonData(duplicate.addons)
        output.profiles[activeProfileName] = duplicate
    end
    output.activeProfile = activeProfileName
    output.profileOrder = { activeProfileName }
    local bundle = {
        version = CUI.LayoutExportVersion(output),
        type = FULL_EXPORT_TYPE,
        fullExport = true, -- the routing stamp the import flow reads
        profileName = activeProfileName,
        data = output,
    }
    CUI.StampPayloadClient(bundle)
    local serialized = Serializer.Serialize(bundle)
    local deflated = LibDeflate:CompressDeflate(serialized)
    return EXPORT_PREFIX .. LibDeflate:EncodeForPrint(deflated)
end

--- True for a decoded payload produced by ExportFullAccountData. The import
--- UI checks this BEFORE handing anything to the normal profile flow.
function CUI.IsFullAccountPayload(bundle)
    return type(bundle) == "table" and (bundle.fullExport == true or bundle.type == FULL_EXPORT_TYPE)
end

--- Applies a full-account payload and reloads. Replaces every account-global
--- key the string carries and installs its profile, then reloads so every
--- module rebuilds from the new store. Caller owns the confirmation.
function CUI.ImportFullAccountData(bundle)
    if not CUI.IsFullAccountPayload(bundle) then return false end
    local body = bundle.data
    if type(body) ~= "table" or not CludesUIDB then return false end
    -- The reload is asked for first in the click (RequestReload); the client
    -- reloads only once this function has finished, so everything below lands.
    CUI.RequestReload(CUI.L("Profile Imported"), CUI.ImportReloadMessage(bundle))
    -- Close any edit session or Default view and bank live edits while the stores
    -- are still the recipient's: a later exit would bank live into the import.
    if CUI.SpecOverrides_CloseEditSessions then CUI.SpecOverrides_CloseEditSessions() end
    if CUI.SpecOverrides_HarvestCurrent then CUI.SpecOverrides_HarvestCurrent() end
    local activeProfileName = body.activeProfile or bundle.profileName or "Default"

    -- 1) Account globals, wholesale. profiles/profileOrder/activeProfile are
    --    handled below; the excluded per-character blobs are refused on the
    --    way IN as well, so a hand-edited string cannot plant a gold ledger.
    --    The other client's Cooldown Manager spell store never imports: the
    --    recipient's stands, as for a string that carries none. Its Tracking
    --    Bars link owner is dropped too (the recipient's own one no longer
    --    describes the live links), so the next bar build swaps the
    --    recipient's own links in instead of banking the string's into a
    --    spell store.
    local otherClient = CUI.PayloadFromOtherClient(bundle)
    -- WoW Forever: the recipient's one-time buff sweep stamp survives the
    -- wholesale _migrations copy below, so that sweep never runs twice
    -- (CludesUI_Migration.lua). FvBW is nil on retail.
    local fvSweep = CUI.FvBW
        and type(CludesUIDB._migrations) == "table"
        and CludesUIDB._migrations.forever_buff_wipe_sweep_v1
    -- Likewise the snapshot switch's one-time legacy check: its mark stays, so
    -- the recipient's own profiles are never re-read as the old layout's. Only
    -- WoW Forever ever writes it.
    local fvSnapKey = CUI._FvSnapFlag
    local fvSnap = fvSnapKey and type(CludesUIDB._migrations) == "table" and CludesUIDB._migrations[fvSnapKey]
    local ownValue = {}
    for key in pairs(FULL_IMPORT_MERGE) do
        ownValue[key] = CludesUIDB[key]
    end
    for key, val in pairs(body) do
        if
            key ~= "profiles"
            and key ~= "profileOrder"
            and key ~= "activeProfile"
            and not FULL_EXPORT_EXCLUDED[key]
            and not (otherClient and (key == "spellAssignments" or key == "_tbbLinkOwner"))
        then
            CludesUIDB[key] = CopyDeep(val)
        end
    end
    for key, merge in pairs(FULL_IMPORT_MERGE) do
        local packed = CludesUIDB[key]
        if packed == ownValue[key] then packed = nil end -- not carried, or refused above
        CludesUIDB[key] = merge(ownValue[key], packed, activeProfileName)
    end
    if fvSweep then
        if type(CludesUIDB._migrations) ~= "table" then CludesUIDB._migrations = {} end
        CludesUIDB._migrations.forever_buff_wipe_sweep_v1 = fvSweep
    end
    if fvSnap then
        if type(CludesUIDB._migrations) ~= "table" then CludesUIDB._migrations = {} end
        CludesUIDB._migrations[fvSnapKey] = fvSnap
    end
    if otherClient then CludesUIDB._tbbLinkOwner = nil end
    -- Match extras ride with their links: a string that carries links but no
    -- extras installs none, never the recipient's leftovers on its links.
    if body.unlockWidthMatch ~= nil and body.unlockWidthMatchExtra == nil then
        CludesUIDB.unlockWidthMatchExtra = nil
    end
    if body.unlockHeightMatch ~= nil and body.unlockHeightMatchExtra == nil then
        CludesUIDB.unlockHeightMatchExtra = nil
    end
    -- WoW Forever: the imported account carries its own look, so an import
    -- also settles the first-install style picker (a carried stamp included).
    if CUI.IS_FOREVER then CludesUIDB.styleChoicePending = nil end

    -- 2) The carried profile. The recipient's OTHER profiles survive; a
    --    same-named profile is replaced (that is the import).
    if type(CludesUIDB.profiles) ~= "table" then CludesUIDB.profiles = {} end
    if type(body.profiles) == "table" then
        for label, pdata in pairs(body.profiles) do
            local duplicate = CopyDeep(pdata)
            -- Legacy per-profile homes of the excluded blobs (see the export
            -- side): refused on the way in too.
            StripPrivateAddonData(duplicate.addons)
            -- WoW Forever: the one-time buff clear, before the profile is
            -- installed (CludesUI_Migration.lua).
            if CUI.FvBW then CUI.FvBW.ProcessProfile(duplicate, "import") end
            CludesUIDB.profiles[label] = duplicate
        end
    end
    if type(CludesUIDB.profiles[activeProfileName]) ~= "table" then
        CludesUIDB.profiles[activeProfileName] = {}
    end

    -- 3) Order list: keep the recipient's and append, never replace -- a
    --    wholesale copy would drop their own profiles out of the picker.
    local sequence = CludesUIDB.profileOrder
    if type(sequence) ~= "table" then
        sequence = {}
        CludesUIDB.profileOrder = sequence
    end
    local listed = false
    for _, num in ipairs(sequence) do
        if num == activeProfileName then
            listed = true
            break
        end
    end
    if not listed then sequence[#sequence + 1] = activeProfileName end
    CludesUIDB.activeProfile = activeProfileName

    -- 4) Re-point the live db objects at the imported profile's tables before
    --    reloading. Lite's PLAYER_LOGOUT write-back copies every db.profile
    --    into profiles[activeProfile].addons[folder]; still pointing at the
    --    OLD tables it would overwrite the freshly imported blobs with the
    --    recipient's current values on the way out. Pointer swap ONLY -- no
    --    defaults merge, no sync handoff, no module refresh: the reload
    --    rebuilds all of that from the imported store.
    local registryTbl = CUI.Lite and CUI.Lite._dbRegistry
    if registryTbl then
        local pdata = CludesUIDB.profiles[activeProfileName]
        if type(pdata.addons) ~= "table" then pdata.addons = {} end
        for _, dbObject in ipairs(registryTbl) do
            if dbObject.folder then
                if type(pdata.addons[dbObject.folder]) ~= "table" then pdata.addons[dbObject.folder] = {} end
                dbObject.profile = pdata.addons[dbObject.folder]
                dbObject._profileName = activeProfileName
            end
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  CDM spec profile helpers for export/import spec picker
-------------------------------------------------------------------------------

--- Get info about which specs have data in the CDM specProfiles table.
--- Returns: { { key="250", name="Blood", icon=..., hasData=true }, ... }
--- Includes ALL specs for the player's class, with hasData indicating
--- whether specProfiles contains data for that spec.
function CUI.GetCDMSpecInfo()
    local spellAssign = CludesUIDB and CludesUIDB.spellAssignments
    local specProfiles = spellAssign and spellAssign.specProfiles or {}
    local output = {}
    local numSpecs = GetNumSpecializations and GetNumSpecializations() or 0
    for i = 1, numSpecs do
        local specId, sName, _, sIcon = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then
            local entryKey = tostring(specId)
            output[#output + 1] = {
                key = entryKey,
                name = sName or ("Spec " .. entryKey),
                icon = sIcon,
                hasData = specProfiles[entryKey] ~= nil,
            }
        end
    end
    return output
end

-------------------------------------------------------------------------------
--  CDM Spec Picker Popup
--  Thin wrapper around ShowSpecAssignPopup for CDM export/import.
--
--  opts = {
--      title    = string,
--      subtitle = string,
--      confirmText = string (button label),
--      specs    = { { key, name, icon, hasData, checked }, ... },
--      onConfirm = function(selectedSpecs)  -- { ["250"]=true, ... }
--      onCancel  = function() (optional)
--  }
--  specs[i].hasData = false grays out the row and shows disabled tooltip.
--  specs[i].checked = initial checked state (only for hasData=true rows).
--  WoW Forever only (ignored on retail, see ForeverCDMSelection):
--      foreverAllKeys   = true: a ticked class = every key the store holds for it
--      foreverActiveKey = string: the key the player's class runs on
-------------------------------------------------------------------------------

--- WoW Forever: CDM spec-picker selection (numeric IDs from the class grid)
--- -> store keys, written into out. opts.foreverAllKeys: a ticked class =
--- every key the active store holds for it. Otherwise a class that stays
--- ticked keeps the keys the picker was opened with, and a newly ticked class
--- = its resolved key (the player's class: opts.foreverActiveKey). Specs of
--- classes Forever lacks pass through.
function CUI.ForeverCDMSelection(assignments, options, output)
    local spellAssign = CludesUIDB and CludesUIDB.spellAssignments
    local b = spellAssign
        and spellAssign.profiles
        and spellAssign.profiles[CludesUIDB.activeProfile or "Default"]
    local specProfiles = (b and b.specProfiles) or {}
    local player = select(2, UnitClass("player"))
    local isOpen = {}
    local function Opened(entryKey)
        local t = CUI.SpecClassOf(tonumber(entryKey))
        if t and CUI.ForeverClassSpecIDs(t) then
            isOpen[t] = isOpen[t] or {}
            isOpen[t][#isOpen[t] + 1] = entryKey
        end
    end
    for _, spec in ipairs(options.specs or {}) do
        if spec.checked then Opened(spec.key) end
    end
    for key, val in pairs(options.lockedSpecs or {}) do
        if val then Opened(key) end
    end
    local done = {}
    for ident in pairs(assignments) do
        local nameToken = CUI.SpecClassOf(ident)
        local ids = CUI.ForeverClassSpecIDs(nameToken)
        if not ids then
            output[tostring(ident)] = true
        elseif not done[nameToken] then
            done[nameToken] = true
            local any = false
            if options.foreverAllKeys then
                for i = 1, #ids do
                    local k = tostring(ids[i])
                    if specProfiles[k] ~= nil then
                        output[k] = true
                        any = true
                    end
                end
                local lk = tostring(CUI.FOREVER_CLASS_SPEC[nameToken])
                if specProfiles[lk] ~= nil then
                    output[lk] = true
                    any = true
                end
            elseif isOpen[nameToken] then
                for _, key in ipairs(isOpen[nameToken]) do
                    output[key] = true
                end
                any = true
            end
            if not any then
                local k = (nameToken == player) and options.foreverActiveKey
                    or tostring(CUI.ForeverClassSpec(nameToken, CUI.SpecHasStringEntry, specProfiles, true))
                output[k] = true
            end
        end
    end
end

do
    -- Dummy db/dbKey/presetKey for the assignments table
    local dummyDB = { _cdmPick = { _cdm = {} } }

    function CUI:ShowCDMSpecPickerPopup(options)
        local specs = options.specs or {}

        -- Reset assignments
        dummyDB._cdmPick._cdm = {}

        -- Pre-check specs that have data; all specs remain selectable
        local prechecked = {}
        for _, sp in ipairs(specs) do
            local numID = tonumber(sp.key)
            if numID and sp.checked then prechecked[numID] = true end
        end

        -- Optional: specs that are forced ON and cannot be toggled (numeric IDs).
        -- opts.lockedSpecs is a set keyed by string specKey; value may be a
        -- tooltip string (or true). opts.disabledSpecs likewise grays specs out.
        local lockedOnSpecs, disabledSpecs = {}, {}
        if options.lockedSpecs then
            for key, val in pairs(options.lockedSpecs) do
                local numID = tonumber(key)
                if numID and val then lockedOnSpecs[numID] = val end
            end
        end
        if options.disabledSpecs then
            for key, val in pairs(options.disabledSpecs) do
                local numID = tonumber(key)
                if numID and val then disabledSpecs[numID] = val end
            end
        end
        -- WoW Forever: the grid has one row per class, so a key saved under a
        -- class's Forever spec ID ticks, locks or disables that class's row.
        if CUI.IS_FOREVER then
            prechecked = CUI.ForeverExpandSpecSet(prechecked)
            lockedOnSpecs = CUI.ForeverExpandSpecSet(lockedOnSpecs)
            disabledSpecs = CUI.ForeverExpandSpecSet(disabledSpecs)
        end

        CUI:ShowSpecAssignPopup({
            db = dummyDB,
            dbKey = "_cdmPick",
            presetKey = "_cdm",
            title = options.title,
            subtitle = options.subtitle,
            subtitleColor = options.subtitleColor,
            subtitleAtBottom = options.subtitleAtBottom,
            buttonText = options.confirmText or "Confirm",
            disabledSpecs = disabledSpecs,
            lockedOnSpecs = lockedOnSpecs,
            preCheckedSpecs = prechecked,
            onConfirm = options.onConfirm and function(assignments)
                -- Convert numeric specID assignments back to string keys
                local selected = {}
                for specId in pairs(assignments) do
                    selected[tostring(specId)] = true
                end
                -- WoW Forever: class rows -> the store keys each class uses.
                if CUI.IS_FOREVER then
                    wipe(selected)
                    CUI.ForeverCDMSelection(assignments, options, selected)
                end
                options.onConfirm(selected)
            end,
            onCancel = options.onCancel,
        })
    end
end

function CUI.ExportCurrentProfile(includeLayout, includeCDM, cdmSpecs)
    if includeLayout == nil then includeLayout = true end -- default ON
    -- Same nil-default as ExportProfile: bare (headless/API) calls get the
    -- complete profile including CDM spell layouts for every spec; the
    -- options export flow always passes the user's explicit choice.
    if includeCDM == nil then includeCDM = true end
    local profileRec = CUI.SnapshotAllAddons()
    -- Legacy account-wide spell store never travels (the per-profile snapshot below
    -- carries CDM content instead).
    profileRec.spellAssignments = nil
    -- CDM spell allocation travels WITH the profile (see SnapshotProfileCDMSpells).
    local activeProfileName = (CludesUIDB and CludesUIDB.activeProfile) or "Default"
    if includeCDM then profileRec.cdmSpells = SnapshotProfileCDMSpells(activeProfileName, nil, cdmSpecs) end
    -- Spec->profile assignments ride along; applied on import only via "Auto
    -- Assign to Specs". nil when this profile is not assigned to any spec.
    profileRec.assignedSpecs = CollectAssignedSpecs(activeProfileName)
    -- HoverCast (click-cast) bindings are account-global, not per-profile; never export.
    profileRec.clickCast = nil
    -- Per-character account data (gold ledger, upgrade-calc caches) likewise
    -- never rides a shared string -- see PRIVATE_ADDON_KEYS. SnapshotAllAddons
    -- deep-copies each module's live profile blob, so a profile still holding
    -- the legacy keys (any profile other than the one cleaned at login) would
    -- otherwise ship its character list through this path.
    StripPrivateAddonData(profileRec.addons)
    -- UI scale (account-wide) rides with the full profile (see ExportProfile).
    profileRec.uiScale = (CludesUIDB and type(CludesUIDB.ppUIScale) == "number") and CludesUIDB.ppUIScale
        or nil
    -- Layout: honor the "Include layout" toggle, and even on a full export drop the
    -- no-checkbox-module (Dragon Riding) + stale (deleted-bar) edges. folderSet=nil
    -- keeps all checkbox modules. Attach the canonical keyToFolder meta.
    local fLayout, layoutMeta = CUI.BuildExportUnlockLayout(profileRec.unlockLayout, includeLayout, nil)
    profileRec.unlockLayout = fLayout
    profileRec.unlockLayoutMeta = layoutMeta
    local sw, sh = GetPhysicalScreenSize()
    -- Use CludesUI's own stored scale (UIParent scale), not Blizzard's CVar
    local cuiScale = CludesUIDB and CludesUIDB.ppUIScale or (UIParent and UIParent:GetScale()) or 1
    local meta = {
        cuiScale = cuiScale,
        screenW = sw and math.floor(sw) or 0,
        screenH = sh and math.floor(sh) or 0,
    }
    -- Normalize local db.folder keys -> canonical (suite) keys (no-op in suite).
    profileRec.addons = AddonsToCanon(profileRec.addons)
    local bundle = {
        version = CUI.LayoutExportVersion(profileRec),
        type = "full",
        data = profileRec,
        meta = meta,
    }
    CUI.StampPayloadClient(bundle)
    local serialized = Serializer.Serialize(bundle)
    if not LibDeflate then return nil end
    local deflated = LibDeflate:CompressDeflate(serialized)
    local packed = LibDeflate:EncodeForPrint(deflated)
    return EXPORT_PREFIX .. packed
end

function CUI.DecodeImportString(importText)
    if not importText or #importText < 5 then return nil, "Invalid string" end
    -- Detect old CDM bar layout strings (format removed in 5.1.2)
    if importText:sub(1, 8) == "!CUICDM_" then
        return nil,
            "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead."
    end
    if importText:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX and not IsForeignString(importText) then
        return nil, "Not a valid CludesUI string. Make sure you copied the entire string."
    end
    if not LibDeflate then return nil, "LibDeflate not available" end
    local packed = importText:sub(#EXPORT_PREFIX + 1)
    local decoded = LibDeflate:DecodeForPrint(packed)
    if not decoded then return nil, "Failed to decode string" end
    local inflated = LibDeflate:DecompressDeflate(decoded)
    if not inflated then return nil, "Failed to decompress data" end
    local bundle = Serializer.Deserialize(inflated)
    if not bundle or type(bundle) ~= "table" then return nil, "Failed to deserialize data" end
    if IsForeignString(importText) then bundle = TranslateForeignPayload(bundle) end
    if not bundle.version or bundle.version < 3 then
        return nil,
            "This profile was created before the beta wipe and is no longer compatible. Please create a new export."
    end
    if bundle.version > 4 then
        return nil, "This profile was created with a newer version of CludesUI. Please update your addon."
    end
    -- Drop account data an older exporter left in the string, before any
    -- consumer (preview UI, ImportProfile, Wago) can write it to a profile.
    -- Type-checked, not just truthy: a corrupt string can deserialize to a
    -- non-table data field, and indexing that would raise instead of letting
    -- the caller report its own decode failure.
    if type(bundle.data) == "table" then StripPrivateAddonData(bundle.data.addons) end
    return bundle, nil
end

-------------------------------------------------------------------------------
--  Async import decode
--
--  DecodeImportString runs decode -> decompress -> deserialize in one
--  synchronous call; on very large strings that stalls the client for
--  seconds. DecodeImportStringAsync produces the identical payload but
--  spreads the work across frames on a small per-frame time budget:
--    - the printable decode runs in fixed-size slices (the codec is
--      block-based, so slicing on 4-char boundaries is lossless),
--    - decompression uses the client's native inflate when available
--      (LibDeflate fallback otherwise -- both read the same deflate stream),
--    - deserialization yields through the Serializer hook above.
--
--  onDone(payload, err) fires exactly once -- on a later frame, or
--  immediately for the cheap validation failures. onProgress(fraction) is
--  optional and approximate, for UI feedback. Returns a handle with
--  :Cancel() (drops the run; onDone never fires), or nil when onDone was
--  already called synchronously. Starting a new run cancels an active one.
-------------------------------------------------------------------------------
do
    local BUDGET_MS = 8 -- per-frame work slice
    local SLICE_LEN = 65536 -- printable-decode slice (multiple of 4)

    local driverFrame -- shared OnUpdate frame, hidden while idle
    local isActive -- state table of the in-flight run, or nil

    local function StopRun(runText)
        if isActive == runText then
            isActive = nil
            Serializer.SetYieldHook(nil)
            if driverFrame then driverFrame:Hide() end
        end
    end

    function CUI.DecodeImportStringAsync(importText, onDone, onProgress)
        -- Cheap validations first (same messages as DecodeImportString).
        if not importText or #importText < 5 then
            onDone(nil, "Invalid string")
            return nil
        end
        if importText:sub(1, 8) == "!CUICDM_" then
            onDone(
                nil,
                "This is an old CDM Bar Layout string. This format is no longer supported. Use the standard profile import instead."
            )
            return nil
        end
        if importText:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX and not IsForeignString(importText) then
            onDone(nil, "Not a valid CludesUI string. Make sure you copied the entire string.")
            return nil
        end
        if not LibDeflate then
            onDone(nil, "LibDeflate not available")
            return nil
        end

        if isActive then StopRun(isActive) end
        local runText = {}
        isActive = runText

        local sliceStart = 0
        local function Yield(frac)
            if onProgress and frac then onProgress(frac) end
            -- Only ever yield our own coroutine: the Serializer hook stays
            -- installed while this run is parked, and a synchronous
            -- Deserialize from elsewhere must never be yielded.
            if coroutine.running() ~= runText.co then return end
            if debugprofilestop() - sliceStart > BUDGET_MS then coroutine.yield() end
        end

        runText.co = coroutine.create(function()
            local packed = importText:sub(#EXPORT_PREFIX + 1)

            -- Printable decode in slices (block codec: 4 chars -> 3 bytes,
            -- so any 4-char boundary is a clean cut; the tail of the final
            -- slice is handled by the codec itself).
            local sum = #packed
            local pieces, pn = {}, 0
            local i = 1
            while i <= sum do
                local jdx = i + SLICE_LEN - 1
                if jdx > sum then jdx = sum end
                local piece = LibDeflate:DecodeForPrint(packed:sub(i, jdx))
                if not piece then return nil, "Failed to decode string" end
                pn = pn + 1
                pieces[pn] = piece
                i = jdx + 1
                Yield((i / sum) * 0.4)
            end
            local decoded = table.concat(pieces)
            pieces = nil
            Yield(0.42)

            -- Decompress: native inflate when the client provides it, else
            -- LibDeflate (single call). A native failure of any kind just
            -- falls through to the library path.
            local inflated
            if
                C_EncodingUtil
                and C_EncodingUtil.DecompressString
                and Enum
                and Enum.CompressionMethod
                and Enum.CompressionMethod.Deflate
            then
                local success, res =
                    pcall(C_EncodingUtil.DecompressString, decoded, Enum.CompressionMethod.Deflate)
                if success and type(res) == "string" and #res > 0 then inflated = res end
            end
            if not inflated then inflated = LibDeflate:DecompressDeflate(decoded) end
            if not inflated then return nil, "Failed to decompress data" end
            decoded = nil
            Yield(0.5)

            -- Deserialize with the cooperative hook installed.
            local dtotal = #inflated
            Serializer.SetYieldHook(function(place) Yield(0.5 + (place / dtotal) * 0.5) end)
            local bundle = Serializer.Deserialize(inflated)
            Serializer.SetYieldHook(nil)

            if not bundle or type(bundle) ~= "table" then return nil, "Failed to deserialize data" end
            if IsForeignString(importText) then bundle = TranslateForeignPayload(bundle) end
            if not bundle.version or bundle.version < 3 then
                return nil,
                    "This profile was created before the beta wipe and is no longer compatible. Please create a new export."
            end
            if bundle.version > 4 then
                return nil,
                    "This profile was created with a newer version of CludesUI. Please update your addon."
            end
            -- Same strip as the sync path: account data never reaches a profile.
            if type(bundle.data) == "table" then StripPrivateAddonData(bundle.data.addons) end
            return bundle, nil
        end)

        local function Step()
            if isActive ~= runText then
                if driverFrame then driverFrame:Hide() end
                return
            end
            sliceStart = debugprofilestop()
            local success, bundle, perr = coroutine.resume(runText.co)
            if not success then
                StopRun(runText)
                onDone(nil, "Failed to read import data")
                return
            end
            if coroutine.status(runText.co) == "dead" then
                StopRun(runText)
                onDone(bundle, perr)
            end
        end

        if not driverFrame then
            driverFrame = CreateFrame("Frame")
            driverFrame:Hide()
        end
        driverFrame:SetScript("OnUpdate", Step)
        driverFrame:Show()

        runText.Cancel = function() StopRun(runText) end
        return runText
    end
end

-------------------------------------------------------------------------------
--  Imported media reconciliation
--
--  A profile string can reference SharedMedia statusbar textures that are
--  not installed on the importing client. LSM silently substitutes its
--  default texture in that case, so the import renders with swapped-in bars
--  and no visible cue that files are missing. For media families known to
--  ship as their own separate install, pin any dangling references to the
--  "Texture Not Found" placeholder texture at import time instead: the
--  affected bars render empty and the selection reads as exactly what
--  happened (clearly missing rather than subtly wrong), and the user can
--  pick any texture from the normal dropdowns afterwards.
--
--  One-shot by design: this rewrites only the incoming payload inside
--  ImportProfile, before it is merged or stored. Existing profiles, presets,
--  exports, profile sync and runtime media resolution are never touched.
--  Media families are matched by signature; per repo convention third-party
--  addon/pack names are not embedded in source.
-------------------------------------------------------------------------------
local RECONCILE_TEX_NAME = "Texture Not Found"
local RECONCILE_TEX_PATH = [[Interface\AddOns\CludesUI\media\textures\blank.tga]]

-- Register the placeholder through the same channel real media uses (LSM),
-- so pinned values resolve everywhere -- every texture lookup table and
-- dropdown picks it up -- with no special cases downstream.
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then LSM:Register(LSM.MediaType.STATUSBAR, RECONCILE_TEX_NAME, RECONCILE_TEX_PATH) end
end

-- Signatures (djb2) of texture names known to ship as separate installs.
local RECONCILE_BAR_SIGS = {
    [3860001264] = true,
    [1502800144] = true,
    [1922316589] = true,
    [3302863399] = true,
    [2397640933] = true,
    [3314165376] = true,
    [2062452265] = true,
}

local function ReconcileImportedMedia(body)
    if type(body) ~= "table" then return end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then return end

    local function Signature(text)
        local hgt = 5381
        for i = 1, #text do
            hgt = (hgt * 33 + text:byte(i)) % 4294967296
        end
        return hgt
    end

    local function Walk(tbl, depth)
        if depth > 40 then return end
        for key, val in pairs(tbl) do
            if type(val) == "table" then
                Walk(val, depth + 1)
            elseif type(val) == "string" and #val >= 9 and #val <= 26 then
                -- Saved texture values are either plain names or carry the
                -- "sm:" dropdown key prefix.
                local baseTbl = val:match("^sm:(.+)") or val
                if RECONCILE_BAR_SIGS[Signature(baseTbl)] then
                    if not LSM:Fetch("statusbar", baseTbl, true) then
                        tbl[key] = "sm:" .. RECONCILE_TEX_NAME
                    end
                end
            end
        end
    end

    Walk(body, 1)
end

--- Reset class-dependent fill colors in Resource Bars after a profile import.
--- The exporter's class color may be baked into fillR/fillG/fillB; this
--- resets them to the importer's own class/power colors and clears
--- customColored so the bars use runtime class color lookup.
local function FixupImportedClassColors()
    local rbEntry
    for _, entry in ipairs(ADDON_DB_MAP) do
        if entry.folder == "CludesUIResourceBars" then
            rbEntry = entry
            break
        end
    end
    if not rbEntry or not IsAddonLoaded(rbEntry.folder) then return end
    local activeProfile = GetAddonProfile(rbEntry)
    if not activeProfile then return end

    local _, class = UnitClass("player")
    -- CLASS_COLORS and POWER_COLORS are local to ResourceBars, so we
    -- use the same lookup the addon uses at init time.
    local classColors = CUI.CLASS_COLOR_MAP
    local cc = classColors and classColors[class]

    -- Health bar: reset to importer's class color
    if activeProfile.health then
        activeProfile.health.customColored = false
        if cc then
            activeProfile.health.fillR = cc.r
            activeProfile.health.fillG = cc.g
            activeProfile.health.fillB = cc.b
        end
    end
end

-- Build an imported profile's per-profile CDM spell bucket on the same
-- merge-base-on-active contract as the addon blobs: START from a copy of the ACTIVE
-- profile's spell store, so specs the incoming string does not carry keep the current
-- profile's layouts VERBATIM (they are the user's own current data -- no import flags
-- or migrations touch them), THEN overlay the incoming specs and arm
-- import-authoritative ghosting on THOSE ONLY, so the importer's tracked-but-unplaced
-- spells get hidden (not spilled onto a default bar) once the profile is active. Runs
-- even with no incoming specs (inherit-only): an imported profile must never pair
-- inherited CDM bar definitions with an empty spell store. Existing bucket keys other
-- than specProfiles are preserved on overwrite, and the active bucket may BE the target
-- bucket (overwriting the active profile): inheritance copies into a fresh table before
-- specProfiles is replaced, so that case is a clean self-copy plus incoming overlay.
local function BuildImportedCDMSpellBucket(profName, activeProfileName, incomingSpecs, importedBarsCfg)
    if not CludesUIDB then return end
    CludesUIDB.spellAssignments = CludesUIDB.spellAssignments or { profiles = {} }
    local spellAssign = CludesUIDB.spellAssignments
    spellAssign.profiles = spellAssign.profiles or {}
    local specBucket = spellAssign.profiles[profName] or {}
    spellAssign.profiles[profName] = specBucket
    local inherited = {}
    local activeBucket = spellAssign.profiles[activeProfileName]
    if activeBucket and type(activeBucket.specProfiles) == "table" then
        for specKey, sp in pairs(activeBucket.specProfiles) do
            if type(sp) == "table" then inherited[specKey] = CopyDeep(sp) end
        end
    end
    specBucket.specProfiles = inherited
    if type(incomingSpecs) ~= "table" then return end
    -- WoW Forever: a class the string carries resolves to the incoming layout,
    -- not to an inherited copy under a key the class would read first.
    CUI.ForeverDropShadowedLegacy(specBucket.specProfiles, incomingSpecs)
    -- Import-authoritative ghosting is computed against the player's LIVE Blizzard CDM
    -- tracked set (viewer pools + category API). That set is only guaranteed settled
    -- after a reload, and the ghost pass is a ONE-SHOT that stamps _barFilterModelV6
    -- the first time it succeeds -- so a pass that runs against a mid-change tracked
    -- set writes a permanently wrong ghost list. Runtime-only flag (dies with the
    -- session) telling the pass to wait for a later session. The interactive import
    -- flow never noticed because its caller ReloadUI()s in the same frame ImportProfile
    -- returns, which kills the queued reanchor that would have run the pass; a caller
    -- that defers its reload (installer wizards) gets the pass mid-session instead.
    if CUI then CUI._cdmImportGhostDeferred = true end
    for specKey, specProfile in pairs(CopyDeep(incomingSpecs)) do
        specBucket.specProfiles[specKey] = specProfile
        if type(specProfile) == "table" then
            if type(specProfile.barSpells) == "table" then specProfile.barSpells.__ghost_cd = nil end
            specProfile._barFilterModelV6 = nil -- re-run the migration on activate
            specProfile._importGhostMode = true -- ghost tracked-but-unplaced spells
            specProfile._dormantMerged = true -- imported data is already current-model
            -- Old-format strings (pre tiered-settings) carry per-bar
            -- spellSettings; transform NOW so the live session reads the
            -- new shape (the registered migration also covers it on the
            -- next reload -- both idempotent, flag lives in the bucket).
            CUI.MigrateCdmSpellSettingsShape(specProfile, importedBarsCfg)
            -- Hosted-buff settings moved family stores (CD -> BUFF);
            -- relocate old-format imports the same way (idempotent).
            CUI.MigrateCdmHostedBuffSettings(specProfile)
            -- Collided-buff cooldownID claims moved from the
            -- assignedBuffCdIDs side-table to cd-claim markers inside
            -- assignedSpells; convert old-format imports too (idempotent),
            -- or their claims sit unread and the slots silently unclaim.
            CUI.MigrateCdmBuffCdClaims(specProfile)
            -- Strings exported before _buffDisplayOrderUserModified existed carry a
            -- drag-arranged buffDisplayOrder without the flag; stamp it or the first
            -- live reconcile resyncs the imported order to Blizzard order (idempotent).
            CUI.MigrateCdmBuffOrderUserFlag(specProfile)
        end
    end
end

--- Drop applied Visibility override MARKERS (store.visibilityOverride) from imported
--- addon data. Every other applied override value is an ordinary setting and stays, as it
--- always has; this one key is different because it REPLACES an element's whole Visibility
--- setting and has no control of its own outside an editing session. Arriving without the
--- override store that owns it, it would pin that element on Never/Always/Mouseover with
--- nothing able to write it back. A marker the recipient's OWN override still owns is
--- restored by that override's next apply, so stripping is safe in both directions.
local function StripStrandedVisOverrides(addonMap)
    if type(addonMap) ~= "table" then return end
    local seen = {}
    local function walk(tbl)
        if seen[tbl] then return end
        seen[tbl] = true
        tbl.visibilityOverride = nil
        for _, val in pairs(tbl) do
            if type(val) == "table" then walk(val) end
        end
    end
    for _, layoutSnap in pairs(addonMap) do
        if type(layoutSnap) == "table" then walk(layoutSnap) end
    end
end

--- Import a profile string. Returns: success, errorMsg
--- The caller must provide a name for the new profile.
function CUI.ImportProfile(importText, profName)
    -- A concurrent silent import (e.g. the Wago path) invalidates any pending
    -- INTERACTIVE import session: its selection UI is stale against the
    -- profile data this call is about to change. The interactive flow's own
    -- commit sets `committing` around this call, so it never cancels itself.
    do
        local cfg = CUI._apiImportSession
        if cfg and cfg.state ~= "done" and not cfg.committing then
            CUI._FinishApiImportSession(false)
            if CUI._ProfilesResetToMain then pcall(CUI._ProfilesResetToMain) end
        end
    end
    -- Accepts either an encoded string or an already-decoded payload table.
    -- The options import page decodes asynchronously and passes the table,
    -- which skips a full re-encode/re-decode of the data at commit time.
    local bundle, err
    if type(importText) == "table" then
        bundle = importText
    else
        bundle, err = CUI.DecodeImportString(importText)
    end
    if not bundle then return false, err end

    -- Normalize canonical (suite) addon keys -> this build's local db.folder
    -- keys, so a suite string imports into a standalone (and vice versa). Runs
    -- before all downstream addon-key handling. No-op in the suite.
    if bundle.data and bundle.data.addons then bundle.data.addons = CanonToLocal(bundle.data.addons) end

    -- Reconcile media references against locally installed SharedMedia before
    -- the payload is merged or stored (see Imported media reconciliation above).
    ReconcileImportedMedia(bundle.data)

    local saved = GetProfilesDB()

    if bundle.type == "cdm_spells" then
        return false, "This is a CDM Bar Layout string, not a profile string."
    end

    -- Resolve the current spec so we can (a) honor "Auto Assign to Specs" if the
    -- payload carries spec assignments and (b) decide whether the freshly imported
    -- profile may auto-apply. The auto-apply gate (specLocked) is finalized AFTER
    -- any auto-assign below, since assigning the current spec to this profile makes
    -- activating it correct rather than locked.
    local curSpecID
    do
        local si = C_SpecializationInfo.GetSpecialization() or 0
        curSpecID = si and si > 0 and C_SpecializationInfo.GetSpecializationInfo(si) or nil
    end

    if bundle.type == "full" then
        -- Spec Overrides: close any edit session or Default view and sync the
        -- current-spec values with live edits before current/merged are built
        -- (as SwitchProfile does), so an import over the active profile's own
        -- name never banks live state into the imported stores.
        if CUI.SpecOverrides_CloseEditSessions then CUI.SpecOverrides_CloseEditSessions() end
        if CUI.SpecOverrides_HarvestCurrent then CUI.SpecOverrides_HarvestCurrent() end
        -- WoW Forever: the one-time buff clear runs on the payload itself, before
        -- the merge copy and the raw re-apply below (CludesUI_Migration.lua).
        if CUI.FvBW then CUI.FvBW.ProcessProfile(bundle.data, "import") end
        -- Merge import: start from the current profile and overlay imported
        -- addon data on top. This preserves settings for addons not present
        -- in the import (e.g. importing from a standalone install).
        local incoming = CopyDeep(bundle.data)
        -- Strip spell assignment data from imported profile (lives in dedicated store)
        if incoming.addons and incoming.addons["CludesUICooldownManager"] then
            incoming.addons["CludesUICooldownManager"].specProfiles = nil
            incoming.addons["CludesUICooldownManager"].barGlows = nil
        end
        incoming.spellAssignments = nil
        -- HoverCast (click-cast) bindings live at CludesUIDB.clickCast (account-
        -- global), never inside a profile. Strip any stray clickCast from the
        -- payload so an import can never overwrite the user's own click-cast setup.
        incoming.clickCast = nil
        -- The Blizz UI Enhanced bundle + its opt-in marker are payload-root
        -- transport, never profile data -- strip so they can't ride into the
        -- stored profile (applied separately below).
        incoming.blizzSkinGlobals = nil
        incoming.applyBlizzSkinGlobals = nil

        -- UI scale (account-wide): PRESENCE IS CONSENT (2026-07-20, matching Window
        -- Skins). The import dialog's scale-mismatch popup runs before its commit and
        -- STRIPS uiScale from the payload when the user picks Keep Mine (or the
        -- scales already match), so a value still present is either the dialog's
        -- accepted Match Scale choice or a headless (Wago / partner / silent API)
        -- full-string import -- which applies the creator's scale by default,
        -- matching overrides, CDM spell layouts, and window skins. Writing the
        -- account keys here lets the caller's imminent reload apply the new scale
        -- (CludesUI_Startup reads ppUIScale). Range matches PP.PixelBestSize's
        -- clamp; out-of-range values are ignored.
        if type(bundle.data.uiScale) == "number" and CludesUIDB then
            local s = bundle.data.uiScale
            if s >= 0.40 and s <= 1.15 then
                CludesUIDB.ppUIScale = s
                CludesUIDB.ppUIScaleAuto = false
            end
        end

        -- Blizz UI Enhanced account-global bundle ("Window & Tooltip Skins"):
        -- applied whenever the string CARRIES it -- presence is consent (2026-07-20):
        -- a bundle only ever rides via the exporter's explicit "Window Skins" Include
        -- choice or the headless full-export default, and the import dialog's
        -- "Include Window Skins" checkbox STRIPS the bundle when unchecked (after its
        -- overwrite confirmation), so the recipient-side opt-out still holds.
        -- Headless (Wago / partner / silent API) full-string imports therefore apply
        -- the creator's window skins by default, matching overrides and CDM spell
        -- layouts. Writes the account-wide keys now; the caller's imminent reload
        -- applies them (these skins install at load).
        if type(bundle.data.blizzSkinGlobals) == "table" then
            CUI.ApplyBlizzSkinGlobals(bundle.data.blizzSkinGlobals)
        end

        -- Base: deep-copy current active profile, then overlay imported addons
        local current = saved.profiles[saved.activeProfile or "Default"]
        local combined = current and CopyDeep(current) or {}
        if not combined.addons then combined.addons = {} end
        if incoming.addons then
            for moduleFolder, layoutSnap in pairs(incoming.addons) do
                combined.addons[moduleFolder] = CopyDeep(layoutSnap)
            end
        end
        -- Per-profile migration stamps must reflect the PAYLOAD's data vintage, not the
        -- base profile's. On a fresh install the base (active) profile carries no
        -- stamps yet, so without this the next load would run every profile-scope
        -- migration over the just-imported data as if it were legacy. A current-version
        -- export carries its own stamps; a genuinely old string carries none and still
        -- gets migrated, which is the intended behavior for old data.
        if type(incoming._migrations) == "table" then
            combined._migrations = CopyDeep(incoming._migrations)
        end
        -- Take fonts/colors from import if present. A string exported without
        -- "Global Settings" lacks these keys entirely, so the base copy's
        -- (recipient's) appearance stands; presence means the exporter chose
        -- to share the look, and it applies regardless of module selection.
        if incoming.fonts then combined.fonts = CopyDeep(incoming.fonts) end
        if incoming.customColors then combined.customColors = CopyDeep(incoming.customColors) end
        if incoming.darkMode then combined.darkMode = CopyDeep(incoming.darkMode) end
        -- numberFormat only exists once its owner changed something, so a string
        -- with the other global settings but none comes from the defaults.
        if incoming.numberFormat then
            combined.numberFormat = CopyDeep(incoming.numberFormat)
        elseif incoming.fonts then
            combined.numberFormat = nil
        end
        -- Override stores: ALL-OR-NOTHING (2026-07-20 redesign; the old per-folder
        -- value merge in SpecOverrides_MergeImportedStores is retired and must not be
        -- re-wired). Taking -> the exporter's complete override system (values + groups
        -- + unlock-layer forks + BM forks) replaces the recipient's wholesale, ids
        -- verbatim: an incoming store is internally consistent, and with nothing
        -- merging there is nothing to remap or dedupe. Not taking -> the base copy's
        -- (recipient's) stores stand untouched. Gate: the explicit overridesIncluded
        -- stamp (new subset exports / the import dialog's Include Overrides checkbox),
        -- or a FULL string without an exclusion stamp (classic full-import semantics).
        -- Legacy subset strings (partialImport, no positive stamp) keep the recipient's
        -- stores, preserving their old keep-mine behavior.
        do
            local takeOverrides = incoming.overridesIncluded == true
                or (incoming.partialImport ~= true and incoming.overridesExcluded ~= true)
            if takeOverrides then
                local OV_KEYS = {
                    "specOverrides",
                    "specOverrideGroups",
                    "specOverrideNextId",
                    "condOverrides",
                    "condOverrideGroups",
                    "condOverrideNextId",
                    "specUnlockOverrides",
                    "condUnlockOverrides",
                    "specBmOverrides",
                    "condBmOverrides",
                    "specDmOverrides",
                    "condDmOverrides",
                    "unlockOverrideAnchors",
                }
                for _, key in ipairs(OV_KEYS) do
                    combined[key] = incoming[key]
                end
            else
                -- The recipient's stores stand, so nothing in the incoming addon data
                -- owns an applied Visibility override marker it carries.
                StripStrandedVisOverrides(combined.addons)
            end
        end
        -- Layout: the new profile's unlockLayout is the active profile's CURRENT
        -- layout, with the imported relationships merged in PER MODULE.
        --
        -- Build the base UNCONDITIONALLY (even when the import carries no layout):
        -- the user's anchors frequently live ONLY in the live CludesUIDB.unlock*
        -- tables -- the stored profile.unlockLayout snapshot lags until a switch/
        -- export, and CludesUIDB.unlockAnchors itself can be absent. So fold the
        -- live tables onto the stored copy here; otherwise a "Include layout = off"
        -- (or layout-less) import would drop the current profile's live anchors.
        do
            local baseLayout = combined.unlockLayout or {}
            baseLayout.anchors = baseLayout.anchors or {}
            baseLayout.widthMatch = baseLayout.widthMatch or {}
            baseLayout.heightMatch = baseLayout.heightMatch or {}
            baseLayout.phantomBounds = baseLayout.phantomBounds or {}
            baseLayout.widthMatchExtra = baseLayout.widthMatchExtra or {}
            baseLayout.heightMatchExtra = baseLayout.heightMatchExtra or {}
            local function overlayLive(destination, live)
                if type(live) == "table" then
                    for key, val in pairs(live) do
                        destination[key] = CopyDeep(val)
                    end
                end
            end
            if CludesUIDB then
                -- CONTRACT (see SnapshotUnlockLayout): while a spec/cond group's unlock
                -- layer is LIVE, the raw globals hold that FORK's links -- overlaying
                -- them raw stamped the fork as the new profile's baseline (the one
                -- snapshot writer the Cluster-A hardening missed: importing while
                -- playing a forked spec leaked its geometry onto every spec of the new
                -- profile). Source through the same baseline-resolved snapshot every
                -- other writer uses; TBB child entries are carried from live inside it.
                local liveSnap = SnapshotUnlockLayout()
                if liveSnap then
                    overlayLive(baseLayout.anchors, liveSnap.anchors)
                    overlayLive(baseLayout.widthMatch, liveSnap.widthMatch)
                    overlayLive(baseLayout.heightMatch, liveSnap.heightMatch)
                    -- Each live link overlaid above brings its live extra, or
                    -- clears the stored extra of the link it replaced.
                    OverlayLinkedExtras(
                        baseLayout.widthMatchExtra,
                        liveSnap.widthMatch,
                        liveSnap.widthMatchExtra
                    )
                    OverlayLinkedExtras(
                        baseLayout.heightMatchExtra,
                        liveSnap.heightMatch,
                        liveSnap.heightMatchExtra
                    )
                end
            end
            combined.unlockLayout = baseLayout -- current full layout (kept when no import layout)

            -- Per-module merge of the imported relationships: keep base for modules
            -- NOT imported (e.g. ActionBars self-anchors); take imported for those
            -- that ARE. imported.addons keys = imported modules (LOCAL).
            if incoming.unlockLayout then
                local importedFolders = {}
                if incoming.addons then
                    for moduleFolder in pairs(incoming.addons) do
                        importedFolders[moduleFolder] = true
                    end
                end
                combined.unlockLayout =
                    CUI.MergeImportedLayout(baseLayout, incoming.unlockLayout, importedFolders)
            end
        end
        -- BASELINE-LINKS == PROFILE-LINKS contract (imported-profile DM
        -- window snap, 2026-07-20): whichever override store this profile ends up
        -- with (kept from the recipient on a partial import, or taken from the
        -- exporter), its baselineLayout link tables must mirror the freshly merged
        -- unlockLayout above -- a kept store's baseline predates the merge, and a
        -- taken store's mirrors the exporter's layout rather than the per-module
        -- mix. The import-establish forced converge applies baseline LINKS over the
        -- live tables at the first post-import login, so stale ones silently wiped
        -- the recipient's just-merged anchors there. Links only: elems stay
        -- untouched (elems of anchored children are additionally inert via the
        -- FlushUnlock anchor-owned guard).
        do
            local s2 = combined.specUnlockOverrides
            local ul2 = combined.unlockLayout
            if type(s2) == "table" and type(s2.baselineLayout) == "table" and type(ul2) == "table" then
                s2.baselineLayout.anchors = CopyDeep(ul2.anchors or {})
                s2.baselineLayout.widthMatch = CopyDeep(ul2.widthMatch or {})
                s2.baselineLayout.heightMatch = CopyDeep(ul2.heightMatch or {})
                s2.baselineLayout.widthMatchExtra = CopyDeep(ul2.widthMatchExtra or {})
                s2.baselineLayout.heightMatchExtra = CopyDeep(ul2.heightMatchExtra or {})
            end
        end
        -- UI accent color travels with the profile. A new-format string always
        -- carries cuiAccent, so the imported value wins; an old string leaves
        -- merged.cuiAccent inherited from the current profile (correct fallback).
        if incoming.cuiAccent then combined.cuiAccent = CopyDeep(incoming.cuiAccent) end
        -- The whole-UI window look is a profile-root key: take the exporter's
        -- value, never the recipient's (an absent key reads as the
        -- CludesUI look).
        combined.windowSkinLook = incoming.windowSkinLook

        -- Snap all positions to the physical pixel grid (imported profiles
        -- may come from a different version without pixel snapping)
        CUI.SnapProfilePositions(combined)
        saved.profiles[profName] = combined
        -- Add to order if not present
        local found = false
        for _, num in ipairs(saved.profileOrder) do
            if num == profName then
                found = true
                break
            end
        end
        if not found then table.insert(saved.profileOrder, 1, profName) end
        -- CDM spell allocation: inherit-then-overlay via the shared builder
        -- (BuildImportedCDMSpellBucket above): specs missing from the string
        -- keep the ACTIVE profile's spell layouts -- the same
        -- merge-base-on-active contract the addon blobs use -- and incoming
        -- specs arm ghosting + the old-format migrations. Runs for strings
        -- with no cdmSpells too (inherit-only), so an imported profile never
        -- pairs inherited bar definitions with an empty spell store. Note:
        -- db.activeProfile still names the PRE-import active profile here
        -- (activation happens further down), which is exactly the inheritance
        -- source the contract wants.
        do
            local importedBarsCfg = bundle.data.addons
                and bundle.data.addons["CludesUICooldownManager"]
                and bundle.data.addons["CludesUICooldownManager"].cdmBars
                and bundle.data.addons["CludesUICooldownManager"].cdmBars.bars
            -- Spell layouts import only from a string made on this client:
            -- another client's are ignored, exactly as if the string carried
            -- none (inherit-only: no overlay, no ghosting, no re-keying).
            local incomingSpells = bundle.data.cdmSpells
            if CUI.PayloadFromOtherClient(bundle) then incomingSpells = nil end
            BuildImportedCDMSpellBucket(
                profName,
                saved.activeProfile or "Default",
                incomingSpells,
                importedBarsCfg
            )
        end
        -- Old-format strings can carry the per-bar Custom Active State Decimals
        -- keys (bd.faDecimals*); convert them to the per-spell Threshold Text
        -- stamps the same way the login migration does (the old keys are
        -- consumed, so this is idempotent). Runs outside the cdmSpells guard:
        -- even a string without a spell store must have its bar keys retired.
        if CUI.MigrateCdmThresholdText then
            local importedCdm = combined.addons and combined.addons["CludesUICooldownManager"]
            if type(importedCdm) == "table" then
                local sa2 = CludesUIDB and CludesUIDB.spellAssignments
                local bucket2 = sa2 and sa2.profiles and sa2.profiles[profName]
                local sp2 = type(bucket2) == "table" and bucket2.specProfiles or nil
                CUI.MigrateCdmThresholdText(importedCdm, sp2)
            end
        end
        -- Remove the new profile from all sync targets so the pre-logout
        -- sync doesn't overwrite it. Other profiles' sync relationships
        -- are preserved (per-profile sync system).
        if CludesUIDB and CludesUIDB.syncedModules then
            for moduleFolder, syncTargets in pairs(CludesUIDB.syncedModules) do
                if type(syncTargets) == "table" then syncTargets[profName] = nil end
            end
        end

        -- "Auto Assign to Specs": the exporter's spec->profile assignments ride in
        -- payload.data.assignedSpecs (a flat list of spec IDs). The import UI strips
        -- this field unless the recipient enabled the toggle, so its mere presence
        -- means "apply": point each listed spec at the newly imported profile.
        if type(bundle.data.assignedSpecs) == "table" then
            for _, specId in ipairs(bundle.data.assignedSpecs) do
                if type(specId) == "number" then saved.specProfiles[specId] = profName end
            end
        end

        -- Finalize the auto-apply gate. If the current spec is assigned to a
        -- DIFFERENT profile (a pre-existing assignment, or an auto-assign just
        -- applied to other specs), the spec auto-switch would immediately pull us
        -- off this profile, so save it but don't activate. If the current spec is
        -- unassigned -- or was just auto-assigned to THIS profile -- activate.
        local assignedNow = curSpecID
            and saved.specProfiles[CUI.SpecFor(curSpecID, CUI.SpecHasEntry, saved.specProfiles)]
        if assignedNow and assignedNow ~= profName then
            -- Stored but not activated: migrate legacy Resource Bars Advanced
            -- data now (the runner's flag was inherited from the base profile,
            -- so it would never run for this import otherwise).
            CUI.MigrateRBAdvancedProfile(saved.profiles[profName])
            -- Import window guard, spec_locked flavor: the merged profile was built on
            -- the dirty active profile all the same, so its first ACTIVATION (e.g. a
            -- later login preseeding onto an auto-assigned spec) hits the same
            -- unguarded pre-apply harvest as a direct import. The flag sits inert while
            -- the profile is stored; whichever session first activates it clears it at
            -- its first apply. Runtime armed flag deliberately NOT set here: this
            -- session keeps its own active profile.
            saved.profiles[profName]._importEstablishPending = true
            -- First-install captures: an imported profile is a chosen layout.
            -- Stamp the one-shot capture flags so a capture that has not
            -- fired yet cannot overwrite this stored profile's layout data
            -- once a later session activates it.
            saved._capturedOnce_EAB = true
            saved._capturedOnce_CDM = true
            saved._capturedOnce_RF = true
            return true, nil, "spec_locked"
        end
        -- Flush the OUTGOING (currently active) profile's LIVE unlock data into its
        -- snapshot BEFORE switching to the imported profile. The live
        -- CludesUIDB.unlock* tables are the source of truth; a profile's stored
        -- unlockLayout only LAGS them (it is refreshed on switch-away/export, not
        -- continuously). SwitchProfile does this flush (~2326); import did NOT -- so
        -- importing, switching back to the old profile (which then restored its STALE
        -- snapshot over the live anchors), then deleting the import silently dropped
        -- every anchor / width-match the user had set on the old profile since it was
        -- last saved (they survived only inside the imported profile, so deleting it
        -- lost them for good). This is the reported "bars lose their anchors and width
        -- match after import" bug. Importing over the active profile's own name:
        -- merged is already installed under it, so the snapshot would bank the
        -- live layout over the imported one.
        local outgoingName = saved.activeProfile or "Default"
        local outbound = outgoingName ~= profName and saved.profiles[outgoingName]
        if outbound and CludesUIDB then outbound.unlockLayout = SnapshotUnlockLayout() end
        -- Make it the active profile and re-point db references (stamp a
        -- missing unlockLayout before the flip -- see StampUnlockLayoutIfMissing)
        StampUnlockLayoutIfMissing(saved.profiles[profName])
        saved.activeProfile = profName
        RepointAllDBs(profName)
        -- Import window guard: suppress unlock/BM LAYOUT banks from now until the first
        -- apply of a later session. The imported store already holds the exporter's
        -- layers verbatim; live geometry in this window is mid-import residue
        -- (inherited link tables, unconverged anchors), and any boundary harvest -- the
        -- import-tail Conditions recheck, the caller's ReloadUI firing PLAYER_LOGOUT,
        -- the first post-login spec transition -- would wholesale-replace a pristine
        -- bucket with it. Persisted on the profile root so it survives the reload; the
        -- companion runtime flag stops THIS session's applies (the SpecOverrides_Apply
        -- below) from closing the window early. Cleared unconditionally at the first
        -- apply of any later session; value harvests are never suppressed.
        saved.profiles[profName]._importEstablishPending = true
        CUI._importGuardArmedNow = true
        -- Custom colours resolve live via GetCustomColorsDB. A GLOBAL-mode colour
        -- section takes its palette from its Pull Colors From (or the first profile); a
        -- recipient who pinned a specific source would store the imported palette but
        -- keep seeing their own. When the import actually carries colours, point every
        -- global-mode section at the imported profile so its palette is what shows.
        -- Getter-redirect only -- never wipes or restores a live colour table (that is
        -- banned). Per-profile sections read the active (now imported) profile already.
        if incoming.customColors and CludesUIDB then CUI.PointColorSectionsAt(profName) end
        -- Apply imported data into the live db.profile tables. We MUST pass
        -- payload.data here (a SEPARATE table) and NOT merged: RepointAllDBs already
        -- pointed db.profile INTO merged.addons, and ApplyProfileData clears db.profile
        -- before copying the snapshot in -- passing merged would clear-then-copy the
        -- same table and wipe every addon. payload.data.addons only holds the imported
        -- modules, so non-imported modules keep their (base) live data untouched.
        -- BUT the live unlock layout must be the per-module-MERGED one, otherwise the
        -- filtered import wipes the live anchors of non-imported modules (e.g.
        -- ActionBars self-anchors). Override it before applying.
        bundle.data.unlockLayout = combined.unlockLayout
        CUI.ApplyProfileData(bundle.data)
        FixupImportedClassColors()
        -- Resource Bars: migrate legacy Advanced/per-spec-enable data carried
        -- by old export strings (ApplyProfileData refilled the live RB table
        -- from the raw payload, so this must run after it). Idempotent.
        CUI.MigrateRBAdvancedProfile(saved.profiles[profName])
        -- NO default re-bank here. The imported entries carry the EXPORTER's recorded
        -- values.default, consistent with the imported addon blobs by construction
        -- (MergeImportedStores partitions per folder). The old
        -- SpecOverrides_RebaselineDefaults pass overwrote those recorded defaults with
        -- the imported LIVE blob -- which holds the exporter's CURRENT SPEC's override
        -- values (SnapshotAllAddons restores canonical spec values, not defaults) --
        -- permanently destroying the exporter's true defaults and bleeding one spec's
        -- values into every unassigned spec on the recipient. Spec Overrides: apply the
        -- imported profile's stored values for the current spec on top of the
        -- just-applied addon data.
        if CUI.SpecOverrides_Apply then CUI.SpecOverrides_Apply(curSpecID) end
        -- First-install captures: an imported profile is a chosen layout. Stamp the
        -- one-shot capture flags (central-store root keys; the capture handlers
        -- re-check them at fire time) so a capture that has not fired yet -- deferred
        -- past login, spec-gated, or armed by a module first enabled in a later session
        -- -- can never overwrite the imported data with live-captured layout state.
        saved._capturedOnce_EAB = true
        saved._capturedOnce_CDM = true
        saved._capturedOnce_RF = true
        -- The minimap capture flag is per-profile. Stamp the imported profile's minimap
        -- table (after ApplyProfileData, so the write sticks) in case the payload
        -- predates the flag or came from an install that never ran the Minimap module.
        do
            if not combined.addons then combined.addons = {} end
            local minimapCfg = combined.addons.CludesUIMinimap
            if type(minimapCfg) ~= "table" then
                minimapCfg = {}
                combined.addons.CludesUIMinimap = minimapCfg
            end
            if type(minimapCfg.minimap) ~= "table" then minimapCfg.minimap = {} end
            minimapCfg.minimap._capturedOnce = true
        end
        -- A successful import means real user data exists: close the first-install
        -- window now instead of at the next login's data-detection pass, so first-run
        -- popups and capture paths stay quiet from here on.
        saved.firstInstallPopupShown = true
        CUI._firstInstallPending = nil
        -- WoW Forever: the imported profile carries its own look, so an
        -- import also settles the first-install style picker.
        if CUI.IS_FOREVER then saved.styleChoicePending = nil end
        -- Don't ReloadUI() here: the caller (options panel import flow)
        -- reloads unconditionally right after this returns. (The old CDM
        -- spec-picker popup flow is gone -- CDM spells import as-is.)
        return true, nil
    end

    return false, "Unknown profile type"
end

-------------------------------------------------------------------------------
--  Profile management
-------------------------------------------------------------------------------
function CUI.SaveCurrentAsProfile(label)
    local saved = GetProfilesDB()
    local current = saved.activeProfile or "Default"
    -- Freshen the override stores from live before snapshotting (same as the
    -- export path): the whole-profile DeepCopy below carries every override
    -- store with it, and without this bank the current spec's most recent
    -- override edits could lag one harvest boundary behind.
    if CUI.SpecOverrides_HarvestCurrent then CUI.SpecOverrides_HarvestCurrent() end
    local src = saved.profiles[current]

    -- Count existing profiles BEFORE adding the new one
    local profileCountBefore = 0
    for _ in pairs(saved.profiles) do
        profileCountBefore = profileCountBefore + 1
    end

    -- Count existing profiles BEFORE adding the new one
    -- Deep-copy the current profile into the new name
    local duplicate = src and CopyDeep(src) or {}
    -- Never inherit the import-window guard flag (see ImportProfile).
    duplicate._importEstablishPending = nil
    -- Ensure fonts/colors/unlock layout are current
    duplicate.fonts = CopyDeep(CUI.GetFontsDB())
    duplicate.customColors = CopyDeep(CUI.GetCustomColorsDB())
    duplicate.darkMode = CopyDeep(CUI.GetDarkModeDB())
    duplicate.unlockLayout = SnapshotUnlockLayout()
    saved.profiles[label] = duplicate

    -- CDM spell content lives in the per-profile spell store at
    -- CludesUIDB.spellAssignments.profiles[<name>], OUTSIDE the profile blob.
    -- DeepCopy(src) above carried only the bar DEFINITIONS (in the addon blob),
    -- NOT the spell allocations / per-icon settings / RPT-sync specs / TBB
    -- broadcast set that ride on this bucket. Fork the whole bucket so the new
    -- profile is a true 1:1 of the source's CDM (which spells sit on which bars,
    -- etc). Without this the copy renders bars with no spells on them.
    local spellAssign = CludesUIDB and CludesUIDB.spellAssignments
    if
        spellAssign
        and type(spellAssign.profiles) == "table"
        and type(spellAssign.profiles[current]) == "table"
    then
        spellAssign.profiles[label] = CopyDeep(spellAssign.profiles[current])
    end

    local found = false
    for _, num in ipairs(saved.profileOrder) do
        if num == label then
            found = true
            break
        end
    end
    if not found then table.insert(saved.profileOrder, 1, label) end

    -- Bags is the ONE module that auto-syncs: bag settings should match
    -- across profiles. Every other module is strictly opt-in via the sync
    -- popup, and new profiles never inherit its group membership.
    if not CludesUIDB.syncedModules then CludesUIDB.syncedModules = {} end
    local bagGroup = CludesUIDB.syncedModules.CludesUIBags
    if profileCountBefore == 1 then
        -- First second profile: create the default Bags group
        if type(bagGroup) ~= "table" then
            bagGroup = {}
            CludesUIDB.syncedModules.CludesUIBags = bagGroup
        end
        bagGroup[current] = true
        bagGroup[label] = true
    elseif type(bagGroup) == "table" and bagGroup[current] then
        -- A copy of a bags-synced profile joins the group. Copies of a
        -- profile the user deliberately removed from it stay out.
        bagGroup[label] = true
    end

    -- Switch to the new profile using the standard path so the outgoing
    -- profile's state is properly saved before repointing.
    CUI.SwitchProfile(label)
end

function CUI.DeleteProfile(label)
    local saved = GetProfilesDB()
    saved.profiles[label] = nil
    for i, num in ipairs(saved.profileOrder) do
        if num == label then
            table.remove(saved.profileOrder, i)
            break
        end
    end
    -- Clean up spec assignments
    for specId, pName in pairs(saved.specProfiles) do
        if pName == label then saved.specProfiles[specId] = nil end
    end
    -- CDM spell content lives in the per-profile spell store at
    -- CludesUIDB.spellAssignments.profiles[<name>] (OUTSIDE the profile blob).
    -- Drop it alongside the profile so no orphaned bucket lingers (and so a future
    -- profile created with the same name never inherits this profile's stale CDM).
    local spellAssign = CludesUIDB and CludesUIDB.spellAssignments
    if spellAssign and type(spellAssign.profiles) == "table" then spellAssign.profiles[label] = nil end
    -- Clean up sync targets: remove deleted profile from every module's list
    if CludesUIDB.syncedModules then
        for moduleFolder, syncTargets in pairs(CludesUIDB.syncedModules) do
            if type(syncTargets) == "table" then syncTargets[label] = nil end
        end
    end
    -- Colour sources: deleting a source profile must not leave a dangling pointer
    -- (the stale name showed in Pull Colors From, the shared palette silently fell
    -- back, and colour editing locked because the user could never be "on" the
    -- deleted source). nil = default (first profile), per section too.
    if CUI.ColorSourcesProfileRemoved(label) then CUI.ApplyColorsToOUF() end
    -- Clean up keybind
    CUI.OnProfileDeleted(label)
    -- If deleted profile was active, fall back to Default. A freshly
    -- auto-created Default gets the current baseline links STAMPED (the
    -- deleted profile is gone -- inheriting unrecorded would resurrect the
    -- mutating-links bug, and wiping would be unrecoverable).
    if saved.activeProfile == label then
        StampUnlockLayoutIfMissing(saved.profiles["Default"])
        saved.activeProfile = "Default"
        RepointAllDBs("Default")
    end
    -- Refresh all sync buttons (hide them if down to 1 profile)
    if CUI._syncRefreshFns then
        for _, func in pairs(CUI._syncRefreshFns) do
            func()
        end
    end
end

function CUI.RenameProfile(previousName, nextName)
    local saved = GetProfilesDB()
    if not saved.profiles[previousName] then return end
    saved.profiles[nextName] = saved.profiles[previousName]
    saved.profiles[previousName] = nil
    -- CDM spell content lives in the per-profile spell store at
    -- CludesUIDB.spellAssignments.profiles[<name>] (OUTSIDE the profile blob),
    -- keyed by profile name. Move the bucket to the new name so the renamed
    -- profile keeps its CDM spell allocations (otherwise they vanish on rename).
    local spellAssign = CludesUIDB and CludesUIDB.spellAssignments
    if
        spellAssign
        and type(spellAssign.profiles) == "table"
        and spellAssign.profiles[previousName] ~= nil
    then
        spellAssign.profiles[nextName] = spellAssign.profiles[previousName]
        spellAssign.profiles[previousName] = nil
    end
    for i, num in ipairs(saved.profileOrder) do
        if num == previousName then
            saved.profileOrder[i] = nextName
            break
        end
    end
    for specId, pName in pairs(saved.specProfiles) do
        if pName == previousName then saved.specProfiles[specId] = nextName end
    end
    -- Move sync group membership to the new name so the renamed profile
    -- keeps syncing and no dead entry lingers in any module's group
    if CludesUIDB.syncedModules then
        for _, syncTargets in pairs(CludesUIDB.syncedModules) do
            if type(syncTargets) == "table" and syncTargets[previousName] then
                syncTargets[previousName] = nil
                syncTargets[nextName] = true
            end
        end
    end
    -- Keep every colour source following the renamed profile (same palette
    -- tables, so no colour refresh is needed).
    CUI.ColorSourcesProfileRenamed(previousName, nextName)
    if saved.activeProfile == previousName then
        -- Rename repoints the SAME profile table: unlockLayout rides it, so
        -- the stamp is a no-op unless the table never had one.
        StampUnlockLayoutIfMissing(saved.profiles[nextName])
        saved.activeProfile = nextName
        RepointAllDBs(nextName)
    end
    -- Update keybind reference
    CUI.OnProfileRenamed(previousName, nextName)
end

function CUI.SwitchProfile(label)
    local saved = GetProfilesDB()
    if not saved.profiles[label] then return end

    -- An open unlock session cannot survive a profile switch (same rule as spec changes
    -- and condition flips): its movers, snapshots, and pending edits all belong to the
    -- OUTGOING profile's stores -- committing or harvesting them after the swap would
    -- write them into the WRONG profile's layers and snapshots. Discard-close first.
    if CUI._unlockModeSessionActive and CUI.ForceCloseUnlockDiscard then CUI.ForceCloseUnlockDiscard() end

    -- Close any editing-as session against the OUTGOING profile first (the
    -- exits bank their edits), so the harvest below runs unguarded and the
    -- post-switch establish never finds a live session.
    if CUI.SpecOverrides_CloseEditSessions then CUI.SpecOverrides_CloseEditSessions() end

    -- Spec Overrides: sync the current spec's stored values with any live
    -- edits before leaving the outgoing profile (suppressed while a spec
    -- transition is mid-flight -- the spec handler already harvested).
    if CUI.SpecOverrides_HarvestCurrent then CUI.SpecOverrides_HarvestCurrent() end

    -- Save current fonts into the outgoing profile before switching. Custom
    -- colors are GLOBAL (not per-profile) and are deliberately NOT saved here --
    -- snapshotting them per profile let a combat-end spec switch restore a stale
    -- snapshot and reset the user's custom power / class-resource colors.
    local outbound = saved.profiles[saved.activeProfile or "Default"]
    if outbound then
        outbound.fonts = CopyDeep(CUI.GetFontsDB())
        -- Save unlock layout into outgoing profile (baseline-sourced while
        -- a group layer is live -- see SnapshotUnlockLayout).
        outbound.unlockLayout = SnapshotUnlockLayout()
    end

    -- If settings were changed this session and any synced modules have
    -- targets, a live re-point won't fully apply cached addon state.
    -- Prompt the user to reload so every addon starts clean.
    if CUI._settingsChanged and label ~= (saved.activeProfile or "Default") then
        local sm = CludesUIDB.syncedModules
        if sm then
            -- Mirror group: only flush groups the OUTGOING profile belongs
            -- to. A profile outside a group never pushes into it.
            local outName = saved.activeProfile or "Default"
            local hasSyncTargets = false
            for moduleFolder, syncTargets in pairs(sm) do
                if type(syncTargets) == "table" and syncTargets[outName] then
                    hasSyncTargets = true
                    break
                end
            end
            if hasSyncTargets then
                -- Flush sync so the other group members have the latest data
                for moduleFolder, syncTargets in pairs(sm) do
                    if type(syncTargets) == "table" and syncTargets[outName] then
                        CUI.SyncModuleToProfiles(moduleFolder, syncTargets)
                    end
                end
                -- Switch the active profile immediately (persisted on logout)
                StampUnlockLayoutIfMissing(saved.profiles[label])
                saved.activeProfile = label
                RepointAllDBs(label)
                -- Prompt for reload
                CUI:ShowConfirmPopup({
                    title = "Reload Recommended",
                    message = "You changed settings while profile sync is active. Please reload your UI for sync changes to take effect.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
                return
            end
        end
    end

    StampUnlockLayoutIfMissing(saved.profiles[label])
    saved.activeProfile = label
    RepointAllDBs(label)
end

function CUI.GetActiveProfileName()
    local saved = GetProfilesDB()
    return saved.activeProfile or "Default"
end

function CUI.GetProfileList()
    local saved = GetProfilesDB()
    return saved.profileOrder, saved.profiles
end

function CUI.GetSpecProfile(specId)
    local saved = GetProfilesDB()
    return saved.specProfiles[CUI.SpecFor(specId, CUI.SpecHasEntry, saved.specProfiles)]
end

-------------------------------------------------------------------------------
--  AutoSaveActiveProfile: no-op in single-storage mode.
--  Addons write directly to CludesUIDB.profiles[active].addons[folder],
--  so there is nothing to snapshot. Kept as a stub so existing call sites
--  (keybind buttons, options panel hooks) do not error.
-------------------------------------------------------------------------------
function CUI.AutoSaveActiveProfile()
    -- Intentionally empty: single-storage means data is always in sync.
end

-------------------------------------------------------------------------------
--  Spec auto-switch handler
--
--  Single authoritative runtime handler for spec-based profile switching.
--  Uses ResolveSpecProfile() for all resolution. Defers the entire switch
--  during combat via pendingSpecSwitch / PLAYER_REGEN_ENABLED.
-------------------------------------------------------------------------------
do
    local specFrame = CreateFrame("Frame")
    local lastSpecId = nil
    local lastKnownCharKey = nil
    local pendingSpecSwitch = false -- true when a switch was deferred by combat
    local pendingOldSpec = nil -- outgoing spec for a combat-deferred Spec Overrides transition
    local specRetry = nil -- retry handle for new characters

    specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    specFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    specFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    specFrame:SetScript("OnEvent", function(_, evt, unitToken)
        ---------------------------------------------------------------
        --  PLAYER_REGEN_ENABLED: handle deferred spec switch
        ---------------------------------------------------------------
        if evt == "PLAYER_REGEN_ENABLED" then
            if pendingSpecSwitch then
                pendingSpecSwitch = false
                -- Spec Overrides: run the combat-deferred leave/enter
                -- transition (harvest old spec, apply below).
                local overrideTransition = pendingOldSpec ~= nil and pendingOldSpec ~= lastSpecId
                if overrideTransition and CUI.SpecOverrides_OnSpecChanged then
                    CUI.SpecOverrides_OnSpecChanged(pendingOldSpec, lastSpecId)
                end
                pendingOldSpec = nil
                -- Re-resolve after combat ends (spec may have changed again)
                local destProfile = ResolveSpecProfile()
                if destProfile then
                    local current = CludesUIDB and CludesUIDB.activeProfile or "Default"
                    if current ~= destProfile then
                        local fontWillChange = CUI.ProfileChangesFont(CludesUIDB.profiles[destProfile])
                        local skinsWillChange =
                            CUI.ProfileChangesWindowSkins(CludesUIDB.profiles[destProfile])
                        local styleWillChange = CUI.ProfileChangesStyle(CludesUIDB.profiles[destProfile])
                        -- _specProfileSwitching disabled (see doSwitch comment)
                        CUI.SwitchProfile(destProfile)
                        CUI.RefreshAllAddons()
                        if fontWillChange or skinsWillChange or styleWillChange then
                            CUI:ShowConfirmPopup({
                                title = "Reload Required",
                                message = fontWillChange
                                        and "Font changed. A UI reload is needed to apply the new font."
                                    or skinsWillChange and "Window skins changed for this profile. A UI reload is needed to apply them."
                                    or "Style changed for this profile. A UI reload is needed to apply it.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload = true,
                            })
                        end
                    end
                end
                -- Spec Overrides: apply the (possibly re-resolved) current
                -- spec's stored values. No-op when a profile switch above
                -- already applied them.
                if overrideTransition and CUI.SpecOverrides_Apply then CUI.SpecOverrides_Apply(lastSpecId) end
            end
            return
        end

        ---------------------------------------------------------------
        --  Filter: only handle "player" for PLAYER_SPECIALIZATION_CHANGED
        ---------------------------------------------------------------
        if evt == "PLAYER_SPECIALIZATION_CHANGED" and unitToken ~= "player" then return end

        ---------------------------------------------------------------
        --  Resolve the current spec via live API
        ---------------------------------------------------------------
        local specIndex = C_SpecializationInfo.GetSpecialization() or 0
        local specId = specIndex and specIndex > 0 and C_SpecializationInfo.GetSpecializationInfo(specIndex)
            or nil

        if not specId then
            -- Spec info not available yet (common on brand new characters).
            -- Start a short polling retry so we can assign the correct
            -- profile once the server sends spec data.
            if not specRetry and (lastSpecId == nil) then
                local attempts = 0
                specRetry = C_Timer.NewTicker(1, function(ticker)
                    attempts = attempts + 1
                    local position = C_SpecializationInfo.GetSpecialization() or 0
                    local spellRef = position
                            and position > 0
                            and C_SpecializationInfo.GetSpecializationInfo(position)
                        or nil
                    if spellRef then
                        ticker:Cancel()
                        specRetry = nil
                        -- Record the spec so future events use the fast path
                        lastSpecId = spellRef
                        local ck = CUI.CharKey(" - ")
                        lastKnownCharKey = ck
                        if not CludesUIDB then CludesUIDB = {} end
                        if not CludesUIDB.lastSpecByChar then CludesUIDB.lastSpecByChar = {} end
                        CludesUIDB.lastSpecByChar[ck] = spellRef
                        CUI._profileSaveLocked = false
                        -- Resolve via the unified function
                        local target = ResolveSpecProfile()
                        if target then
                            local current = (CludesUIDB and CludesUIDB.activeProfile) or "Default"
                            if current ~= target then
                                local fontChange = CUI.ProfileChangesFont(CludesUIDB.profiles[target])
                                local skinsChange = CUI.ProfileChangesWindowSkins(CludesUIDB.profiles[target])
                                local styleChange = CUI.ProfileChangesStyle(CludesUIDB.profiles[target])
                                -- _specProfileSwitching disabled (see doSwitch comment)
                                CUI.SwitchProfile(target)
                                CUI.RefreshAllAddons()
                                if fontChange or skinsChange or styleChange then
                                    CUI:ShowConfirmPopup({
                                        title = "Reload Required",
                                        message = fontChange
                                                and "Font changed. A UI reload is needed to apply the new font."
                                            or skinsChange and "Window skins changed for this profile. A UI reload is needed to apply them."
                                            or "Style changed for this profile. A UI reload is needed to apply it.",
                                        confirmText = "Reload Now",
                                        cancelText = "Later",
                                        reload = true,
                                    })
                                end
                            end
                        end
                    elseif attempts >= 10 then
                        ticker:Cancel()
                        specRetry = nil
                    end
                end)
            end
            return
        end

        -- Spec resolved -- cancel any pending retry
        if specRetry then
            specRetry:Cancel()
            specRetry = nil
        end

        local characterKey = CUI.CharKey(" - ")
        local isFirstLogin = (lastSpecId == nil)
        -- charChanged is true when the active character is different from the
        -- last session (alt-swap). On a plain /reload the charKey stays the same.
        local charChanged = (lastKnownCharKey ~= nil) and (lastKnownCharKey ~= characterKey)

        -- On PLAYER_ENTERING_WORLD (reload/zone-in), skip if same character
        -- and same spec -- a plain /reload should not override the user's
        -- active profile selection.
        if evt == "PLAYER_ENTERING_WORLD" then
            if not isFirstLogin and not charChanged and specId == lastSpecId then
                return -- same char, same spec, nothing to do
            end
        end
        local prevSpecID = lastSpecId
        -- True whenever Spec Overrides must run a leave/enter transition.
        local specTransition = isFirstLogin or charChanged or prevSpecID ~= specId
        lastSpecId = specId
        lastKnownCharKey = characterKey

        -- Persist the current spec so PreSeedSpecProfile can guarantee the
        -- correct profile is loaded on next login via ResolveSpecProfile().
        if not CludesUIDB then CludesUIDB = {} end
        if not CludesUIDB.lastSpecByChar then CludesUIDB.lastSpecByChar = {} end
        CludesUIDB.lastSpecByChar[characterKey] = specId

        -- Spec resolved successfully -- unlock auto-save if it was locked
        -- during PreSeedSpecProfile when spec was unavailable.
        CUI._profileSaveLocked = false

        ---------------------------------------------------------------
        --  Defer entire switch during combat
        ---------------------------------------------------------------
        if InCombatLockdown() then
            pendingSpecSwitch = true
            -- Remember the outgoing spec so the deferred Spec Overrides
            -- transition can harvest it after combat.
            if specTransition and not charChanged then pendingOldSpec = prevSpecID end
            return
        end

        -- Unlock mode cannot survive a spec transition: movers, session snapshots, and
        -- pending edits all belong to the OUTGOING spec's layout (unlock mode always
        -- displays the current spec), so a stale save would corrupt both baseline and
        -- spec-override data. Force- close DISCARDING the session before any harvest or
        -- apply runs. Combat parity is free: the whole handler defers to REGEN above.
        if specTransition and CUI.ForceCloseUnlockDiscard then CUI.ForceCloseUnlockDiscard() end

        -- Spec Overrides: harvest the outgoing spec's live values into the still-active
        -- profile BEFORE any spec-profile switch below, and mark the transition so
        -- mid-swap harvests can't mis-key values. Cross-char re-entries pass no old
        -- spec (live values may belong to another character's spec).
        if specTransition and CUI.SpecOverrides_OnSpecChanged then
            CUI.SpecOverrides_OnSpecChanged(
                (not charChanged and prevSpecID ~= specId) and prevSpecID or nil,
                specId
            )
        end

        ---------------------------------------------------------------
        --  Resolve target profile via the unified function
        ---------------------------------------------------------------
        local saved = GetProfilesDB()
        local destProfile = ResolveSpecProfile()
        if destProfile then
            local current = saved.activeProfile or "Default"
            if current ~= destProfile then
                local function doSwitch()
                    -- _specProfileSwitching disabled: was causing width/height
                    -- matches to never re-apply because SPELLS_CHANGED fires
                    -- before PLAYER_SPECIALIZATION_CHANGED (CDM completes
                    -- before the flag is set, flag stuck true forever).
                    -- CludesUI._specProfileSwitching = true
                    local fontWillChange = CUI.ProfileChangesFont(saved.profiles[destProfile])
                    local skinsWillChange = CUI.ProfileChangesWindowSkins(saved.profiles[destProfile])
                    local styleWillChange = CUI.ProfileChangesStyle(saved.profiles[destProfile])
                    CUI.SwitchProfile(destProfile)
                    CUI.RefreshAllAddons()
                    if not isFirstLogin and (fontWillChange or skinsWillChange or styleWillChange) then
                        CUI:ShowConfirmPopup({
                            title = "Reload Required",
                            message = fontWillChange
                                    and "Font changed. A UI reload is needed to apply the new font."
                                or skinsWillChange and "Window skins changed for this profile. A UI reload is needed to apply them."
                                or "Style changed for this profile. A UI reload is needed to apply it.",
                            confirmText = "Reload Now",
                            cancelText = "Later",
                            reload = true,
                        })
                    end
                end
                if isFirstLogin then
                    -- Defer two frames: one frame lets child addon OnEnable
                    -- callbacks run, a second frame lets any deferred
                    -- registrations inside OnEnable (e.g. SetupOptionsPanel)
                    -- complete before SwitchProfile tries to rebuild frames.
                    C_Timer.After(0, function() C_Timer.After(0, doSwitch) end)
                else
                    doSwitch()
                end
            elseif isFirstLogin or charChanged then
                -- activeProfile already matches the target. If the pre-seed
                -- already injected the correct data into each child SV, the
                -- addons built with the right values and no further action is
                -- needed. Only call SwitchProfile if the pre-seed did not run
                -- (e.g. first session after update, no lastSpecByChar entry).
                if not CUI._preSeedComplete then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function() CUI.SwitchProfile(destProfile) end)
                    end)
                end
            end
        elseif charChanged then
            -- No spec assignment for this character and character changed (alt swap).
            -- If the current activeProfile is spec-assigned (left over from the
            -- previous character), switch to the last non-spec profile so this
            -- character doesn't inherit another character's spec layout. Skip on plain
            -- /reload (same char) to respect the user's intentional profile choice.
            local current = saved.activeProfile or "Default"
            local currentIsSpecAssigned = false
            if saved.specProfiles then
                for _, pName in pairs(saved.specProfiles) do
                    if pName == current then
                        currentIsSpecAssigned = true
                        break
                    end
                end
            end
            if currentIsSpecAssigned then
                -- Find the best fallback: lastNonSpecProfile, or any profile
                -- that isn't spec-assigned, or Default as last resort.
                local fallbackName = saved.lastNonSpecProfile
                if not fallbackName or not saved.profiles[fallbackName] then
                    -- Walk profileOrder to find first non-spec-assigned profile
                    local specAssignedSet = {}
                    if saved.specProfiles then
                        for _, pName in pairs(saved.specProfiles) do
                            specAssignedSet[pName] = true
                        end
                    end
                    for _, pName in ipairs(saved.profileOrder or {}) do
                        if not specAssignedSet[pName] and saved.profiles[pName] then
                            fallbackName = pName
                            break
                        end
                    end
                end
                fallbackName = fallbackName or "Default"
                if fallbackName ~= current and saved.profiles[fallbackName] then
                    C_Timer.After(0, function()
                        C_Timer.After(0, function() CUI.SwitchProfile(fallbackName) end)
                    end)
                end
            end
        end

        -- Spec Overrides: apply the incoming spec's stored values. Any spec-profile
        -- switch above already applied values inside its RefreshAllAddons pass, so this
        -- duplicate is a value-equal no-op there; it is the ONLY apply for same-profile
        -- spec changes and plain first logins.
        if specTransition and CUI.SpecOverrides_Apply then CUI.SpecOverrides_Apply(specId, isFirstLogin) end
    end)
end

-------------------------------------------------------------------------------
--  Initialize profile system on first login
--  Creates the "Default" profile from current settings if none exists.
--  Also saves the active profile on logout (via Lite pre-logout callback)
--  so SavedVariables are current before StripDefaults runs.
-------------------------------------------------------------------------------
do
    -- Register pre-logout callback to persist fonts, colors, and unlock layout
    -- into the active profile, and track the last non-spec profile.
    -- All addons use _dbRegistry (NewDB), so no manual snapshot is needed --
    -- they write directly to the central store.
    CUI.Lite.RegisterPreLogout(function()
        if not CUI._profileSaveLocked then
            local saved = GetProfilesDB()
            local label = saved.activeProfile or "Default"
            local profileRec = saved.profiles[label]
            if profileRec then
                profileRec.fonts = CopyDeep(CUI.GetFontsDB())
                profileRec.customColors = CopyDeep(CUI.GetCustomColorsDB())
                profileRec.darkMode = CopyDeep(CUI.GetDarkModeDB())
                profileRec.unlockLayout = SnapshotUnlockLayout()
            end
            -- Track the last active profile that was NOT spec-assigned so
            -- characters without a spec assignment can fall back to it.
            local isSpecAssigned = false
            if saved.specProfiles then
                for _, pName in pairs(saved.specProfiles) do
                    if pName == label then
                        isSpecAssigned = true
                        break
                    end
                end
            end
            if not isSpecAssigned then saved.lastNonSpecProfile = label end
        end
    end)

    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")

        local saved = GetProfilesDB()

        -- On first install, create "Default" from current (default) settings.
        -- If activeProfile is already set (user deleted Default intentionally),
        -- don't recreate it.
        if not saved.activeProfile then
            saved.activeProfile = "Default"
            if not saved.profiles["Default"] then saved.profiles["Default"] = {} end
            local hasDefault = false
            for _, num in ipairs(saved.profileOrder) do
                if num == "Default" then
                    hasDefault = true
                    break
                end
            end
            if not hasDefault then table.insert(saved.profileOrder, "Default") end
        end
        -- Safety: if the active profile doesn't exist, fall back to the first
        -- available profile or create Default as a last resort.
        if not saved.profiles[saved.activeProfile] then
            local fallbackName
            for _, num in ipairs(saved.profileOrder) do
                if saved.profiles[num] then
                    fallbackName = num
                    break
                end
            end
            if not fallbackName then
                fallbackName = "Default"
                saved.profiles["Default"] = {}
                if not saved.profileOrder[1] then saved.profileOrder[1] = "Default" end
            end
            saved.activeProfile = fallbackName
        end

        ---------------------------------------------------------------
        --  Note: multiple specs may intentionally point to the same
        --  profile. No deduplication is performed here.
        ---------------------------------------------------------------

        -- Restore saved profile keybinds
        C_Timer.After(1, function() CUI.RestoreProfileKeybinds() end)
    end)
end

-------------------------------------------------------------------------------
--  Shared popup builder for Export and Import
--  Matches the info popup look: dark bg, thin scrollbar, smooth scroll.
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--  Paste absorber for import edit boxes
--
--  Multiline edit boxes process pasted text one character at a time and
--  re-layout after every one, so pasting a large profile string stalls the
--  client for seconds -- and anything past the box's own cap is silently
--  lost. The absorber keeps the visible box capped small while collecting
--  the complete paste through OnChar into a plain Lua buffer: the box stays
--  cheap to lay out, nothing is truncated, and once the paste settles the
--  box shows a short summary line instead of the raw string.
--
--  local absorber = CludesUI.AttachImportPasteAbsorber(editBox, onRetry)
--  absorber.GetText() -> the captured string, or the box's own (trimmed)
--  text when nothing was absorbed. A manual user edit after a capture drops
--  the capture (the user is starting over). onRetry (optional) is called if
--  a paste overflowed the box without reaching the buffer; the cap is
--  lifted so pasting again lands fully in the box.
-------------------------------------------------------------------------------
function CUI.AttachImportPasteAbsorber(inputBox, onRetry)
    local CAP = 2048
    inputBox:SetMaxLetters(0)
    inputBox:SetMaxBytes(CAP)

    local buf, bufferCount, lastN = {}, 0, 0
    local capturedState
    local settingLabel = false

    local function Finalize()
        inputBox:SetScript("OnUpdate", nil)
        local text = strtrim(table.concat(buf, "", 1, bufferCount))
        wipe(buf)
        bufferCount, lastN = 0, 0
        local boxText = inputBox:GetText() or ""
        if #text > #boxText then
            -- The box rejected part of the paste; the buffer holds all of it.
            capturedState = text
            settingLabel = true
            inputBox:SetText(CUI.Lf("[ Import string captured (%1$s characters) ]", tostring(#text)))
            inputBox:SetCursorPosition(0)
            settingLabel = false
        elseif #boxText >= CAP then
            -- The box filled to its cap but the buffer saw nothing beyond
            -- it: the paste could not be absorbed. Lift the cap so a second
            -- paste lands fully in the box (slower, but complete).
            capturedState = nil
            inputBox:SetMaxBytes(0)
            settingLabel = true
            inputBox:SetText("")
            settingLabel = false
            if onRetry then onRetry() end
        else
            capturedState = nil
        end
    end

    inputBox:HookScript("OnChar", function(_, c)
        bufferCount = bufferCount + 1
        buf[bufferCount] = c
        if bufferCount == 1 then
            lastN = 0
            -- Finalize on the first frame where no further characters
            -- arrived (a paste delivers its whole burst before then).
            inputBox:SetScript("OnUpdate", function()
                if bufferCount == lastN then
                    Finalize()
                else
                    lastN = bufferCount
                end
            end)
        end
    end)

    inputBox:HookScript("OnTextChanged", function(_, userInput)
        if userInput and not settingLabel and capturedState then capturedState = nil end
    end)

    return {
        GetText = function() return capturedState or strtrim(inputBox:GetText() or "") end,
    }
end

local function BuildStringPopup(title, subtitle, readOnly, onConfirm, confirmLabel)
    local POPUP_W, POPUP_H = 520, 310
    local FONT = CUI.EXPRESSWAY

    -- Dimmer
    local shade = CreateFrame("Frame", nil, UIParent)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:SetAllPoints(UIParent)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    local dimTex = shade:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.25)

    -- Popup
    local dialog = CreateFrame("Frame", nil, shade)
    dialog:SetSize(POPUP_W, POPUP_H)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
    dialog:EnableMouse(true)
    local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
    CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)

    -- Title
    local titleFS = CUI.MakeFont(dialog, 15, "", 1, 1, 1)
    titleFS:SetPoint("TOP", dialog, "TOP", 0, -20)
    titleFS:SetText(title)

    -- Subtitle
    local subFS = CUI.MakeFont(dialog, 11, "", 1, 1, 1)
    subFS:SetAlpha(0.45)
    subFS:SetPoint("TOP", titleFS, "BOTTOM", 0, -4)
    subFS:SetText(subtitle)

    -- ScrollFrame containing the EditBox
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog)
    scrollFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 52)
    scrollFrame:SetFrameLevel(dialog:GetFrameLevel() + 1)
    scrollFrame:EnableMouseWheel(true)

    local sc = CreateFrame("Frame", nil, scrollFrame)
    sc:SetWidth(scrollFrame:GetWidth() or (POPUP_W - 40))
    sc:SetHeight(1)
    scrollFrame:SetScrollChild(sc)

    local inputBox = CreateFrame("EditBox", nil, sc)
    inputBox:SetMultiLine(true)
    inputBox:SetAutoFocus(false)
    inputBox:SetFont(FONT, 11, "")
    inputBox:SetTextColor(1, 1, 1, 0.75)
    inputBox:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)
    inputBox:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -14, 0)
    inputBox:SetHeight(1) -- grows with content

    local UpdateThumb, scrollTo = CUI.AttachSmoothScrollbar(scrollFrame)

    -- Reset on hide
    shade:HookScript("OnHide", function()
        scrollTo(0)
        inputBox:ClearFocus()
    end)

    -- Auto-select for export (read-only): click selects all for easy copy.
    -- For import (editable): just re-focus so the user can paste immediately.
    if readOnly then
        inputBox:SetScript("OnMouseUp", function(self)
            C_Timer.After(0, function()
                self:SetFocus()
                self:HighlightText()
            end)
        end)
        inputBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    else
        inputBox:SetScript("OnMouseUp", function(self) self:SetFocus() end)
        -- Click anywhere in the scroll area should also focus the editbox
        scrollFrame:SetScript("OnMouseDown", function() inputBox:SetFocus() end)
    end

    if readOnly then
        inputBox:SetScript("OnChar", function(self)
            self:SetText(self._readOnly or "")
            self:HighlightText()
        end)
    end

    -- Resize scroll child to fit editbox content
    local function SyncListHeight()
        C_Timer.After(0.01, function()
            local lineH = (inputBox.GetLineHeight and inputBox:GetLineHeight()) or 14
            local hgt = inputBox:GetNumLines() * lineH
            local sfH = scrollFrame:GetHeight() or 100
            -- Only grow scroll child beyond the visible area when content is taller
            if hgt <= sfH then
                sc:SetHeight(sfH)
                inputBox:SetHeight(sfH)
            else
                sc:SetHeight(hgt + 4)
                inputBox:SetHeight(hgt + 4)
            end
            UpdateThumb()
        end)
    end
    inputBox:SetScript("OnTextChanged", function(self, userInput)
        if readOnly and userInput then
            self:SetText(self._readOnly or "")
            self:HighlightText()
        end
        SyncListHeight()
    end)

    -- Absorb large pastes so the box never has to lay out a huge string
    -- (import mode only; export boxes are read-only and set text directly).
    -- Attached after the OnTextChanged SetScript above so the hook survives.
    local absorber
    if not readOnly then absorber = CUI.AttachImportPasteAbsorber(inputBox) end

    -- Buttons
    if onConfirm then
        local confirmBtn = CreateFrame("Button", nil, dialog)
        confirmBtn:SetSize(120, 26)
        confirmBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 14)
        confirmBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        CUI.MakeStyledButton(confirmBtn, confirmLabel or "Import", 11, CUI.WB_COLOURS, function()
            local packed = absorber and absorber.GetText() or inputBox:GetText()
            if packed and #packed > 0 then
                shade:Hide()
                onConfirm(packed)
            end
        end)

        local cancelBtn = CreateFrame("Button", nil, dialog)
        cancelBtn:SetSize(120, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 14)
        cancelBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        CUI.MakeStyledButton(cancelBtn, "Cancel", 11, CUI.RB_COLOURS, function() shade:Hide() end)
    else
        local closeBtn = CreateFrame("Button", nil, dialog)
        closeBtn:SetSize(120, 26)
        closeBtn:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 14)
        closeBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        CUI.MakeStyledButton(closeBtn, "Close", 11, CUI.RB_COLOURS, function() shade:Hide() end)
    end

    -- Dimmer click to close
    shade:SetScript("OnMouseDown", function()
        if not dialog:IsMouseOver() then shade:Hide() end
    end)

    -- Escape to close
    CUI.PopupTakeKeys(dialog, shade)
    dialog:SetScript("OnKeyDown", function(self, entryKey)
        if InCombatLockdown() then return end
        if entryKey == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            shade:Hide()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    return shade, inputBox, SyncListHeight
end

-------------------------------------------------------------------------------
--  Export Popup
-------------------------------------------------------------------------------
function CUI:ShowExportPopup(exportStr)
    local shade, inputBox, SyncListHeight =
        BuildStringPopup("Export Profile", "Copy the string below and share it", true, nil, nil)

    inputBox._readOnly = exportStr
    inputBox:SetText(exportStr)
    SyncListHeight()

    shade:Show()
    C_Timer.After(0.05, function()
        inputBox:SetFocus()
        inputBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Copy Popup (read-only string with a custom title/subtitle)
--  Same auto-highlight behavior as ShowExportPopup, but the caller supplies the
--  title and subtitle (e.g. for the preset "Copy Blizz Edit Mode" string).
-------------------------------------------------------------------------------
function CUI:ShowCopyPopup(title, subtitle, packed)
    local shade, inputBox, SyncListHeight = BuildStringPopup(title or "Copy", subtitle or "", true, nil, nil)

    inputBox._readOnly = packed or ""
    inputBox:SetText(packed or "")
    SyncListHeight()

    shade:Show()
    C_Timer.After(0.05, function()
        inputBox:SetFocus()
        inputBox:HighlightText()
    end)
end

-------------------------------------------------------------------------------
--  Apply a Blizzard Edit Mode layout from a preset's export string.
--  Decodes the string with C_EditMode.ConvertStringToLayoutInfo, writes it into
--  the saved-layout list, then persists with C_EditMode.SaveLayouts +
--  SetActiveLayout. We deliberately do NOT use EditModeManagerFrame:ImportLayout:
--  its MakeNewLayout indexes self.highestLayoutIndexByType, which is nil until the
--  player has opened Blizzard Edit Mode at least once this session, so it errors
--  out of the box. The low-level C_EditMode path has no such dependency (this is
--  how the layout list is managed internally). The CALLER must ReloadUI()
--  immediately after a successful import so both land together and the addon taint
--  introduced into Edit Mode is wiped. Must be out of combat. Returns true if a
--  layout was applied.
-------------------------------------------------------------------------------
function CUI.ApplyPresetEditMode(layoutString, layoutName)
    if type(layoutString) ~= "string" or layoutString == "" then return false end
    if not layoutName or layoutName == "" then return false end
    if InCombatLockdown() then return false end
    local mgr = EditModeManagerFrame
    if
        not (
            C_EditMode
            and C_EditMode.ConvertStringToLayoutInfo
            and C_EditMode.GetLayouts
            and C_EditMode.SaveLayouts
            and C_EditMode.SetActiveLayout
        )
    then
        return false
    end
    -- Edit Mode account settings populate on EDIT_MODE_LAYOUTS_UPDATED (login);
    -- once present, C_EditMode.GetLayouts is usable without opening the UI.
    if not (mgr and mgr.accountSettings) then return false end

    local incoming = C_EditMode.ConvertStringToLayoutInfo(layoutString)
    if not incoming then return false end -- malformed or version-incompatible string
    incoming.layoutType = Enum.EditModeLayoutType.Account
    incoming.layoutName = layoutName

    -- Bring the imported layout up to THIS client's Edit Mode schema. A string
    -- exported from an older build carries only the systems/settings that existed
    -- then, so newer per-system options (e.g. the Tracked Bars "Display Mode",
    -- "Bar Width", "Show Timer", and crucially "Hide When Inactive") would be
    -- absent and never appear in Edit Mode. Reconciling adds them with their modern
    -- defaults so the imported layout behaves like a natively-created one. WoW
    -- Forever's Gamepad interface style layouts reconcile with that style's own
    -- systems: the modern list removes every system only it has (retail has
    -- neither the style nor its enum).
    local styles = Enum.InputDeviceInterfaceType
    local gamepad = styles and styles.Gamepad
    local function Reconcile(layout)
        if gamepad and layout.interfaceStyle == gamepad then
            if mgr.ReconcileWithGamepad then mgr:ReconcileWithGamepad(layout) end
        elseif mgr.ReconcileWithModern then
            mgr:ReconcileWithModern(layout)
        end
    end
    Reconcile(incoming)

    -- C_EditMode.GetLayouts returns only the saved layouts; the live game keeps
    -- Blizzard's built-in presets ahead of them, and SaveLayouts / SetActiveLayout
    -- index into that combined view: presets first, then the saved layouts, so
    -- the active index we hand back lines up with what the game uses.
    local details, presetCount = CUI.EditModeLayoutsForSave()
    if not details then return false end
    local layoutList = details.layouts
    for i = presetCount + 1, #layoutList do
        Reconcile(layoutList[i])
    end

    -- Re-importing a preset should refresh, not duplicate: drop any earlier copy of
    -- our layout. Only the editable (post-preset) range can hold one.
    for i = #layoutList, presetCount + 1, -1 do
        if layoutList[i].layoutName == layoutName then table.remove(layoutList, i) end
    end

    -- The game lists layouts as presets, then Account, then Character. Slot ours in
    -- just before the first Character layout (or at the end when there is none) so
    -- it stays grouped with the Account layouts.
    local slot = #layoutList + 1
    for i = presetCount + 1, #layoutList do
        if layoutList[i].layoutType == Enum.EditModeLayoutType.Character then
            slot = i
            break
        end
    end
    table.insert(layoutList, slot, incoming)

    details.layouts = layoutList
    details.activeLayout = slot
    C_EditMode.SaveLayouts(details)
    C_EditMode.SetActiveLayout(slot)
    return true
end

-------------------------------------------------------------------------------
--  Import Popup
-------------------------------------------------------------------------------
function CUI:ShowImportPopup(onImport, title, subtitle)
    local shade, inputBox = BuildStringPopup(
        title or "Import Profile",
        subtitle or "Paste an CludesUI profile string below",
        false,
        function(packed)
            if onImport then onImport(packed) end
        end,
        "Import"
    )

    shade:Show()
    C_Timer.After(0.05, function() inputBox:SetFocus() end)
end

-------------------------------------------------------------------------------
--  Wago UI Packs API
--  ExportProfile and ImportProfile already exist above with the right
--  signatures. The functions below fill in the rest of the spec:
--  https://github.com/methodgg/Wago-Creator-UI/blob/main/
--  WagoUI_Libraries/LibAddonProfiles/ImplementationGuide.lua
-------------------------------------------------------------------------------
function CUI.DecodeProfileString(profileString)
    local bundle = CUI.DecodeImportString(profileString)
    return bundle and bundle.data or nil
end

function CUI.SetProfile(profileKey) CUI.SwitchProfile(profileKey) end

function CUI.GetProfileKeys()
    local _, profileNames = CUI.GetProfileList()
    local keyList = {}
    if profileNames then
        for key in pairs(profileNames) do
            keyList[key] = true
        end
    end
    return keyList
end

function CUI.GetProfileAssignments() return nil end

function CUI.GetCurrentProfileKey() return CUI.GetActiveProfileName() end

function CUI.OpenConfig()
    if not InCombatLockdown() then CUI:Show() end
end

function CUI.CloseConfig() CUI:Hide() end

-------------------------------------------------------------------------------
--  Interactive Import API (separate from the silent ImportProfile above; the
--  Wago path keeps calling ImportProfile unchanged).
--
--  A partner addon hands over an import string and the USER completes the
--  import through the normal options import flow: UI-scale prompt, per-module
--  selection page, profile name, final Import click. Contract:
--    * callback(true)  -- the user completed the final Import step. The forced
--      reload is SUPPRESSED and the options panel closes: the CALLER now owns
--      the ReloadUI() at the end of its own install flow. (The imported-but-
--      not-yet-reloaded state is the same one the silent Wago path has always
--      produced.)
--    * callback(false) -- the user closed the options panel without importing,
--      the string failed to decode, or a silent ImportProfile call replaced
--      the session. Tab switches inside the panel do NOT decline (the user
--      can navigate back and resume), and a combat auto-close keeps the
--      session alive to resume when the panel reopens.
--    * The callback may never fire if the player reloads or logs out with the
--      session open -- callers must not hard-block waiting on it.
--  One session at a time: a second call while one is live fails fast.
--
--  opts: importString (required), profileName (optional prefill for the name
--  box), source (optional display name of the caller), callback (optional).
--  Returns true, or false + reason when the call could not start a session.
-------------------------------------------------------------------------------
function CUI.ImportProfileInteractive(options)
    if type(options) ~= "table" or type(options.importString) ~= "string" or options.importString == "" then
        return false, "invalid arguments"
    end
    if InCombatLockdown() then return false, "in combat" end
    local existing = CUI._apiImportSession
    if existing and existing.state ~= "done" then return false, "an interactive import is already pending" end

    -- First-open split (see _SplitFirstOpen): on the session's first open the
    -- navigation below only LOADS and the panel builds next frame, so the
    -- Profiles page -- and with it _ProfilesConsumeApiImport -- does not exist
    -- yet. Re-run the whole call next frame instead; the session is not created
    -- until then, so the re-entry is not blocked as "already pending".
    if CUI:_SplitFirstOpen(function() CUI.ImportProfileInteractive(options) end) then return true end

    CUI._apiImportSession = {
        str = options.importString,
        name = type(options.profileName) == "string" and options.profileName or nil,
        source = type(options.source) == "string" and options.source or nil,
        callback = type(options.callback) == "function" and options.callback or nil,
        state = "pending", -- pending -> active (import page up) -> done
    }
    -- Land on the Profiles page (opens the panel if needed). The page builder registers
    -- _ProfilesConsumeApiImport when it builds -- either during this navigation or from
    -- an earlier cached visit -- so after navigating, enter the import flow through the
    -- CURRENT build's registered entry. Never force a rebuild here: a rebuild
    -- mid-consume orphans the async decode's continuation on destroyed page frames.
    CUI:NavigateToElementSettings("_CUIProfiles", "Profiles")
    CUI._EnsureApiImportCloseHook()
    if CUI._ProfilesConsumeApiImport then CUI._ProfilesConsumeApiImport() end
    return true
end

--- Fire the session callback exactly once and clear the session. pcall'd so a
--- partner error can never break the import flow that invoked it.
function CUI._FinishApiImportSession(accepted)
    local cfg = CUI._apiImportSession
    if not cfg or cfg.state == "done" then return end
    cfg.state = "done"
    CUI._apiImportSession = nil
    if cfg.callback then pcall(cfg.callback, accepted and true or false) end
end

--- Decline-on-close: closing the options panel with a live session counts as
--- "no". Installed once on the main frame (ours, so HookScript is safe); the
--- success path finishes the session BEFORE hiding the panel, so this handler
--- only ever fires for genuine user closes.
do
    local hooked = false
    function CUI._EnsureApiImportCloseHook()
        if hooked then return end
        local mf = CUI._mainFrame
        if not mf then return end -- panel not built yet; consumer retries
        hooked = true
        mf:HookScript("OnHide", function()
            local cfg = CUI._apiImportSession
            if not cfg or cfg.state == "done" then return end
            -- Combat auto-close is not a decision: keep the session so it
            -- resumes when the panel reopens out of combat.
            if InCombatLockdown() then return end
            CUI._FinishApiImportSession(false)
            -- Clear the stale import page out of the cached Profiles wrapper
            -- so reopening the panel shows the normal Profiles view.
            if CUI._ProfilesResetToMain then pcall(CUI._ProfilesResetToMain) end
        end)
    end
end

-------------------------------------------------------------------------------
--  Silent partner-installer import (public API, additive)
--
--  Ports a creator's export string EXACTLY for installer addons that own the
--  whole setup (no CUI dialogs); the interactive dialog flow is untouched.
--  Fonts, custom colors, accent, CDM spell layouts, overrides, the
--  window/tooltip skin bundle and UI scale all apply as carried (presence is
--  consent), so the recipient lands on the creator's complete look.
--
--  opts:
--    importString  (required) the creator's export string.
--    profileName   (required) target profile name.
--    disableAddons (optional) suite child FOLDER names the pack replaces with
--                  external addons. Strips them from the payload (addon blobs
--                  incl. hosted sub-modules; CDM spell layouts if the CDM
--                  module is listed; the window/tooltip skin bundle if the skin
--                  module is listed); filters cross-module layout relationships
--                  down to kept modules so no anchor or size-match edge can
--                  reference a module that will have no frames; after a
--                  successful import disables those folders and ENABLES every
--                  other suite child (authoritative list -- children added after
--                  a pack shipped enable by default), recording the bags choice
--                  so the bag-addon auto-disable respects the pack's
--                  composition. The shared-services shim and the parent addon
--                  are load-bearing for every child and are never disabled.
--    cleanSlate    (default true) delete an existing profile of the same name
--                  first: importing onto an existing name inherits its
--                  name-keyed external buckets (CDM spell store, spec
--                  assignments, sync targets), and DeleteProfile is the one
--                  path that purges them all.
--    applyUIScale  (default true) false strips the string's UI scale so the
--                  user keeps their own.
--    autoAssignSpecs (default false) true keeps the exporter's spec->profile
--                  assignments; headless presence would apply them, so
--                  installers opt in deliberately.
--
--  Returns ok, err. NEVER reloads: the caller owns the ReloadUI at the end of
--  its own flow (addon enable/disable state also only applies then).
-------------------------------------------------------------------------------
function CUI.ImportProfileSilent(options)
    if type(options) ~= "table" or type(options.importString) ~= "string" or options.importString == "" then
        return false, "invalid arguments"
    end
    if type(options.profileName) ~= "string" or options.profileName == "" then
        return false, "profileName is required"
    end
    if InCombatLockdown() then return false, "in combat" end
    local profName = options.profileName

    -- Decode once and hand ImportProfile the TABLE. Never re-encode a decoded
    -- payload: a serializer round trip is not identity on decoded content.
    local bundle = CUI.DecodeImportString(options.importString)
    if type(bundle) ~= "table" or type(bundle.data) ~= "table" then
        return false, "could not decode import string"
    end

    -- Normalize + guard the disable set.
    local disabled
    if type(options.disableAddons) == "table" then
        disabled = {}
        for _, moduleFolder in ipairs(options.disableAddons) do
            if type(moduleFolder) == "string" then disabled[moduleFolder] = true end
        end
        disabled["CludesUI"] = nil
    end

    if disabled then
        -- Partition profile-data modules into stripped vs kept (canonical keys,
        -- matching the payload), resolving hosted sub-modules through their host addon.
        local keepCanon, stripCanon = {}, {}
        for _, entry in ipairs(ADDON_DB_MAP) do
            local canon = FOLDER_TO_CANON[entry.folder] or entry.folder
            if disabled[entry.folder] or (entry.hostAddon and disabled[entry.hostAddon]) then
                stripCanon[canon] = true
            else
                keepCanon[canon] = true
            end
        end
        if bundle.data.addons then
            for canon in pairs(stripCanon) do
                bundle.data.addons[canon] = nil
            end
        end
        -- CDM spell layouts live outside the addon blob.
        if disabled["CludesUICooldownManager"] then bundle.data.cdmSpells = nil end
        -- The account-global window/tooltip skin bundle belongs to the skin
        -- module; a pack that replaces it must not apply the bundle.
        if disabled["CludesUIBlizzardSkin"] then
            bundle.data.blizzSkinGlobals = nil
            bundle.data.applyBlizzSkinGlobals = nil
        end
        -- Keep only layout relationships whose endpoints both survive: the
        -- same per-element filter the import dialog applies on deselection.
        local layout = bundle.data.unlockLayout
        if layout then
            local meta = bundle.data.unlockLayoutMeta
            local keyToFolder = CUI.BuildImportKeyToFolder(layout, meta and meta.keyToFolder)
            bundle.data.unlockLayout = CUI.FilterLayoutToFolders(layout, keepCanon, keyToFolder)
        end
    end
    -- Meta is transport-only; never let it persist into the profile.
    bundle.data.unlockLayoutMeta = nil

    if options.applyUIScale == false then
        bundle.data.uiScale = nil
        bundle.data.applyUIScale = nil
    end
    if not options.autoAssignSpecs then bundle.data.assignedSpecs = nil end

    -- Clean slate (see doc block above).
    if options.cleanSlate ~= false then
        local saved = GetProfilesDB()
        if saved.profiles and saved.profiles[profName] then CUI.DeleteProfile(profName) end
    end

    local success, err, status = CUI.ImportProfile(bundle, profName)
    if not success then return false, err end

    -- Apply the pack's folder composition (takes effect at the caller's
    -- reload). Enabling sweeps the whole suite so children added after a
    -- pack shipped default ON instead of ending up in neither set.
    if disabled and C_AddOns and C_AddOns.EnableAddOn then
        local exists = C_AddOns.DoesAddOnExist
        local seen = {}
        local function apply(moduleFolder)
            if seen[moduleFolder] then return end
            seen[moduleFolder] = true
            if exists and not exists(moduleFolder) then return end
            if disabled[moduleFolder] then
                C_AddOns.DisableAddOn(moduleFolder)
            else
                C_AddOns.EnableAddOn(moduleFolder)
            end
        end
        for _, entry in ipairs(ADDON_DB_MAP) do
            apply(entry.hostAddon or entry.folder)
        end
        -- The pack made the bags decision; keep the bag-addon auto-disable
        -- from overriding it later.
        if CludesUIDB then CludesUIDB.bagsUserChosen = true end
    end

    return true, nil, status
end

-------------------------------------------------------------------------------
--  External installer registration
--  A partner installer that owns the whole first-run experience calls this at
--  its ADDON_LOADED (every session). While registered, the suite's own
--  first-install picker stays silent -- the picker's reload-handshake flag
--  still arms, so first-run popups stay quiet until the installer's import
--  completes (the import stamps first-install state). Fail-open: if the
--  installer never imports, the picker returns on a later login without a
--  registration.
-------------------------------------------------------------------------------
function CUI.RegisterExternalInstaller(displayName)
    CUI._externalInstaller = (type(displayName) == "string" and displayName ~= "") and displayName or true
end
