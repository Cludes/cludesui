if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CludesUI_Lite.lua
--  Lightweight replacement for AceAddon-3.0, AceEvent-3.0, and AceDB-3.0
--  Zero-overhead event dispatch (direct frame handlers, no CallbackHandler)
--  Reads existing AceDB SavedVariables format -- no migration needed
--------------------------------------------------------------------------------
local ADDON_NAME, mod = ...

local LiteKit = {}
CludesUI = CludesUI or {}
CludesUI.Lite = LiteKit

-- WoW Forever (game type "camelot"): the 12.1 engine reporting a 1.60+ toc.
-- Stamped by CludesUI_ClientGate.lua before any other file runs. Content
-- that vanilla lacks gates on this, never on WOW_PROJECT_ID (the gate reads
-- the toc number, the one signal every Forever build reports the same way).
CludesUI.IS_FOREVER = (CUI_CLIENT_FOREVER == true)
-- Global cooldown reference spell: Forever reports nothing on 61304 and uses
-- Classic's 29515.
CludesUI.GCD_SPELL = CludesUI.IS_FOREVER and 29515 or 61304

-- The options-panel scale moves in 5% steps from 75% to 200% (the Window Scale
-- slider in the panel header). Every seeder rounds onto those steps, so the
-- slider always reads exactly what the panel renders at.
--
-- Lives here (first file in the TOC) so the Startup seed, the migration and the panel
-- itself share ONE range -- copies of these literals is how they drift apart.
CludesUI.PANEL_SCALE_MIN, CludesUI.PANEL_SCALE_MAX = 0.75, 2.00

-- Nearest 5% step to v, inside the range. Ties round up (harmless: the panel reads
-- large rather than small, which is the direction this whole seed exists to fix).
function CludesUI.SnapPanelScale(val)
    if type(val) ~= "number" or val ~= val then return 1.00 end
    val = math.floor(val * 20 + 0.5) / 20
    return math.max(CludesUI.PANEL_SCALE_MIN, math.min(CludesUI.PANEL_SCALE_MAX, val))
end

-- Lua APIs
local pairs, type, next, rawset, rawget, setmetatable, wipe =
    pairs, type, next, rawset, rawget, setmetatable, wipe
local tinsert, tremove = table.insert, table.remove
local xpcall, geterrorhandler = xpcall, geterrorhandler

local function errorhandler(err) return geterrorhandler()(err) end
local function safecall(func, ...)
    if type(func) == "function" then return xpcall(func, errorhandler, ...) end
end

--------------------------------------------------------------------------------
--  Addon Registry + Lifecycle
--------------------------------------------------------------------------------
local addons = {} -- name -> addon table
local initQueue = {} -- addons waiting for OnInitialize
local enableQueue = {} -- addons waiting for OnEnable
local statuses = {} -- name -> true if enabled

-- Per-addon event frame. Defined ABOVE NewAddon because NewAddon creates it EAGERLY,
-- and that timing is load-bearing for CPU attribution: the engine bills an event
-- handler's entire call tree to the addon whose execution context called CreateFrame
-- for the frame (probe-verified 2026-07-26; see CludesUI_Ticker.lua). NewAddon runs
-- in the child's MAIN CHUNK, so the frame is stamped to the child and its event work
-- bills that addon. The old lazy creation happened at first RegisterEvent -- usually
-- inside OnInitialize/OnEnable, which run under the parent's lifecycle dispatch -- so
-- every mixin event frame in the suite was parent-stamped and the whole suite's event
-- handling was billed to the parent addon.
local function GetOrCreateEventFrame(addon)
    if addon._eventFrame then return addon._eventFrame end
    local frame = CreateFrame("Frame")
    frame._handlers = {}
    frame:SetScript("OnEvent", function(self, evt, ...)
        local handler = self._handlers[evt]
        if handler then handler(addon, evt, ...) end
    end)
    addon._eventFrame = frame
    return frame
end

--- Create a new addon object. Replaces AceAddon:NewAddon().
-- Returns a table with :RegisterEvent / :UnregisterEvent mixed in.
function LiteKit.NewAddon(name)
    if addons[name] then return addons[name] end
    local addon = { name = name, enabledState = true }
    addons[name] = addon
    tinsert(initQueue, addon)

    -- Eager, on purpose -- see the attribution note on GetOrCreateEventFrame.
    GetOrCreateEventFrame(addon)

    -- Mix in event methods
    addon.RegisterEvent = LiteKit._RegisterEvent
    addon.UnregisterEvent = LiteKit._UnregisterEvent

    return addon
end

--- Retrieve an addon by name (for cross-addon access).
-- Replaces LibStub("AceAddon-3.0"):GetAddon(name).
function LiteKit.GetAddon(name, silent)
    if not addons[name] and not silent then
        error("CUILite.GetAddon: addon '" .. name .. "' not found.", 2)
    end
    return addons[name]
end

--------------------------------------------------------------------------------
--  Event System (direct frame handlers, no CallbackHandler overhead)
--------------------------------------------------------------------------------
-- Each addon gets its own hidden frame for events. When RegisterEvent is
-- called with a function callback, we store it and route through a single
-- OnEvent script. No securecallfunction dispatch loop, no registry tables.
--------------------------------------------------------------------------------

-- (GetOrCreateEventFrame lives above NewAddon -- creation is eager at
-- NewAddon time for CPU-attribution reasons documented there.)

--- Register for a Blizzard event. Compatible with AceEvent calling conventions:
--   addon:RegisterEvent("EVENT_NAME", function(self, event, ...) end)
--   addon:RegisterEvent("EVENT_NAME", "MethodName")
--   addon:RegisterEvent("EVENT_NAME")  -- calls self:EVENT_NAME(event, ...)
function LiteKit._RegisterEvent(self, eventname, callback)
    local frame = GetOrCreateEventFrame(self)
    local handler
    if type(callback) == "function" then
        -- Stored directly. The dispatcher calls handler(addon, event, ...),
        -- which is already the callback's own signature, so wrapping it only
        -- added a second function call to every event the suite receives --
        -- and put an anonymous frame between the callback and any traceback.
        -- The string and no-callback forms below still need a closure, because
        -- they resolve the method on the addon at dispatch time.
        handler = callback
    elseif type(callback) == "string" then
        handler = function(addon, evt, ...)
            if addon[callback] then addon[callback](addon, evt, ...) end
        end
    else
        -- No callback: look for self:EVENT_NAME
        handler = function(addon, evt, ...)
            if addon[eventname] then addon[eventname](addon, evt, ...) end
        end
    end
    frame._handlers[eventname] = handler
    frame:RegisterEvent(eventname)
end

--- Unregister a Blizzard event.
function LiteKit._UnregisterEvent(self, eventname)
    local frame = self._eventFrame
    if not frame then return end
    frame._handlers[eventname] = nil
    frame:UnregisterEvent(eventname)
end

--------------------------------------------------------------------------------
--  Database (reads existing AceDB format, zero-dependency)
--------------------------------------------------------------------------------
-- AceDB stores data as:
--   GlobalSVName = {
--       profileKeys = { ["CharName - RealmName"] = "Default" },
--       profiles = { Default = { ... } }
--   }
-- We read from that same structure so existing settings carry over.
--------------------------------------------------------------------------------

local function DeepMergeDefaults(dest, source)
    -- Merge src into dest, only filling in keys that don't exist yet
    for key, val in pairs(source) do
        if type(val) == "table" then
            if type(dest[key]) ~= "table" then dest[key] = {} end
            DeepMergeDefaults(dest[key], val)
        else
            if dest[key] == nil then dest[key] = val end
        end
    end
end

-- Expose for use by the profile system when applying old snapshots
LiteKit.DeepMergeDefaults = DeepMergeDefaults

local function StripDefaults(saved, defaultSet)
    -- Remove values that match defaults (for clean SavedVariables on logout)
    for key, val in pairs(defaultSet) do
        if type(val) == "table" and type(saved[key]) == "table" then
            StripDefaults(saved[key], val)
            -- Keep empty array entries; DeepMergeDefaults fills them on login.
            if not next(saved[key]) and type(key) ~= "number" then saved[key] = nil end
        elseif saved[key] == val then
            saved[key] = nil
        end
    end
end

local function DeepCopy(source)
    if type(source) ~= "table" then return source end
    return CopyTable(source)
end

LiteKit.DeepCopy = DeepCopy

local dbRegistry = {} -- all db objects, for logout cleanup

-- Expose so the profile system can update db.profile in-place after injection
LiteKit._dbRegistry = dbRegistry

-- Pre-SavedVariables db tracking. A NewDB call at FILE SCOPE in the addon that OWNS the
-- central store runs before WoW loads that addon's SavedVariables: it builds its
-- profile inside a fresh table, and the real saved table then replaces the global right
-- after, orphaning the db -- session writes go to the orphan and are never serialized
-- (settings silently stop saving). In the suite this can't happen (children's files
-- execute long after the parent's SVs loaded), but in a STANDALONE build everything is
-- one addon, so a file-scope NewDB (Bags) hit exactly this. Any db created before the
-- owning addon's ADDON_LOADED is recorded here and re-rooted in place against the real
-- loaded store at that moment. STANDALONE-GATED: the suite has no pre-SV NewDB callers
-- (children init after the parent's SVs load), so the queue is provably empty there;
-- the gate makes that a hard guarantee instead of a convention. The folder-name test is
-- rename-immune (the standalone build never renames "Standalone").
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil
local _svLoaded = false -- true once ADDON_NAME's SavedVariables are live
local _preSVDBs = {} -- dbs created before that, awaiting re-root
--- True once db.profile can be trusted to be the real saved table.
--
-- A pre-SavedVariables db is built inside an orphan table and re-rooted in
-- place at ADDON_LOADED (see _preSVDBs above), which silently invalidates
-- anything a consumer CACHED from it. A cache that is only READ shows stale
-- values; one written BACK to the profile destroys real saved data -- Bags'
-- category list did exactly that. Consumers test this before trusting, or
-- persisting, anything derived from db.profile.
--
-- Always true in the suite, where no db is ever created pre-SavedVariables.
function LiteKit.IsDBReady() return (not IS_STANDALONE) or _svLoaded end

--- Create or open a database backed by the central CludesUIDB store.
-- Returns a db object with .profile pointing to the active profile table
-- inside CludesUIDB.profiles[name].addons[folder].
-- @param svName  Global SavedVariables name (string), e.g. "CludesUIActionBarsDB"
-- @param defaults  Table with a .profile sub-table of default values
-- @param defaultToCharKey  (ignored, kept for call-site compat)
function LiteKit.NewDB(svName, defaultSet, defaultToCharKey)
    -- Derive the addon folder name from the SV name (strip trailing "DB")
    local folder = svName:match("^(.+)DB$") or svName

    -- Resolve the active profile name from the central DB
    local profileName = "Default"
    if CludesUIDB and CludesUIDB.activeProfile then profileName = CludesUIDB.activeProfile end

    -- Ensure the profile and addons tables exist in the central DB
    if not CludesUIDB then CludesUIDB = {} end
    if not CludesUIDB.profiles then CludesUIDB.profiles = {} end
    if type(CludesUIDB.profiles[profileName]) ~= "table" then CludesUIDB.profiles[profileName] = {} end
    local profileData = CludesUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end
    if type(profileData.addons[folder]) ~= "table" then profileData.addons[folder] = {} end
    local profile = profileData.addons[folder]

    -- Child SV globals are vestigial (all data lives in CludesUIDB).
    -- Wipe in-place (not replace) so WoW's SV serializer, which holds
    -- the original table reference from load time, saves the empty table.
    if _G[svName] and type(_G[svName]) == "table" then
        wipe(_G[svName])
    else
        _G[svName] = {}
    end

    -- Merge defaults into profile (fills missing keys only)
    local profileDefaults = defaultSet and defaultSet.profile
    if profileDefaults then
        DeepMergeDefaults(profile, profileDefaults)
        -- Validate: if any top-level default sub-table is missing or wrong
        -- type after merge, the profile is corrupt. Wipe and re-merge.
        local corrupt = false
        for key, val in pairs(profileDefaults) do
            if type(val) == "table" and type(profile[key]) ~= "table" then
                corrupt = true
                break
            end
        end
        if corrupt then
            wipe(profile)
            DeepMergeDefaults(profile, profileDefaults)
            -- One-time warning per session
            if not LiteKit._corruptionWarned then
                LiteKit._corruptionWarned = true
                C_Timer.After(
                    5,
                    function()
                        CludesUI.Print(
                            "|cffff6600CludesUI:|r Profile data for "
                                .. folder
                                .. " was corrupted and has been repaired. Your settings may have been reset to defaults."
                        )
                    end
                )
            end
        end
    end

    -- Build the db object
    local saved = {
        sv = CludesUIDB,
        svName = svName,
        folder = folder,
        profile = profile,
        _profileName = profileName,
        _defaults = defaultSet,
        _profileDefaults = profileDefaults,
    }

    --- Reset the current profile to defaults.
    function saved:ResetProfile()
        wipe(self.profile)
        if self._profileDefaults then DeepMergeDefaults(self.profile, self._profileDefaults) end
    end

    -- Register for logout cleanup
    tinsert(dbRegistry, saved)

    -- Created before the owning addon's SavedVariables loaded: the real
    -- saved table will replace CludesUIDB momentarily, so queue this db
    -- for the in-place re-root at ADDON_LOADED (see _preSVDBs above).
    if IS_STANDALONE and not _svLoaded then tinsert(_preSVDBs, saved) end

    return saved
end

--------------------------------------------------------------------------------
--  Logout handler: strip defaults so SavedVariables stay clean
--  Fires pre-logout callbacks first so systems like Profiles can snapshot
--  the full profile data before defaults are stripped.
--------------------------------------------------------------------------------
local preLogoutCallbacks = {}

--- Register a function to run before StripDefaults on logout.
--- Used by the profile system to save a complete snapshot.
function LiteKit.RegisterPreLogout(fn) tinsert(preLogoutCallbacks, fn) end

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    -- Fire pre-logout callbacks while data is still intact
    for _, fn in ipairs(preLogoutCallbacks) do
        safecall(fn)
    end

    -- Strip defaults from a COPY of each profile table, then write the stripped copy
    -- back into the central store. This keeps the live db.profile references untouched
    -- (important if any pre-logout callback still reads from them after this point).
    local activeProfile = CludesUIDB and CludesUIDB.activeProfile or "Default"
    local profileData = CludesUIDB and CludesUIDB.profiles and CludesUIDB.profiles[activeProfile]
    if profileData and profileData.addons then
        for _, saved in pairs(dbRegistry) do
            if saved._profileDefaults and saved.profile then
                local stripped = DeepCopy(saved.profile)
                StripDefaults(stripped, saved._profileDefaults)
                profileData.addons[saved.folder] = stripped
            end
        end
    end
end)

--------------------------------------------------------------------------------
--  Lifecycle driver (replaces AceAddon's ADDON_LOADED / PLAYER_LOGIN handler)
--------------------------------------------------------------------------------
-- OnInitialize fires on ADDON_LOADED (SavedVariables are available). OnEnable fires on
-- PLAYER_LOGIN (game data is available). This matches AceAddon's exact timing.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
--  Stale central-DB guard
--------------------------------------------------------------------------------
-- WoW executes a child addon's ENTIRE WTF SavedVariables file when the child loads --
-- including variables its TOC no longer declares (the TOC only controls what gets
-- WRITTEN at logout). A child TOC that ever declared "## SavedVariables: CludesUIDB"
-- left a full copy of the central DB in that child's WTF file; if the child was then
-- disabled, the copy froze. Re-enabling the child executes the frozen copy AFTER the
-- parent loaded the real DB, replacing it -- and the next logout persists the stale
-- data over the real file (all profiles wiped).
--
-- The guard captures the authoritative table at the parent's own ADDON_LOADED
-- (the only moment it is guaranteed to be the freshly-loaded real data) and
-- re-points the global at it if any later load in the startup batch swapped
-- the table. It runs before the init queue below, so a poisoned child's own
-- OnInitialize never sees the stale table. Armed only until PLAYER_LOGIN:
-- every SV-bearing suite child is a hard dependency (never LoadOnDemand), so
-- all of them -- and any possible stale file -- load before then. The one
-- LoadOnDemand member, CludesUIOptions, declares NO SavedVariables by
-- design: WoW never writes a WTF file for it, so its post-login load executes
-- no SV file and can never swap the global. Keep it SV-less. Post-login
-- ADDON_LOADEDs (Blizzard on-demand addons) and intentional table swaps
-- (full reset + ReloadUI) are never touched. If the parent DB failed to
-- load (nil), the guard stays unarmed and behavior is unchanged.
local _parentDBRef -- the table the parent's own SV file produced
local _dbGuardArmed = true -- true from load until PLAYER_LOGIN

-- Re-root dbs created before the owning addon's SavedVariables loaded (see _preSVDBs
-- above): resolve the profile inside the REAL loaded central store, merge defaults, and
-- update the db object IN PLACE so every closure holding it reads and writes the table
-- WoW will serialize at logout. The vestigial child SV global is re-wiped in place (its
-- saved copy loaded after NewDB's file-scope wipe and would otherwise persist junk).
local function RerootPreSVDBs()
    if #_preSVDBs == 0 then return end
    local profileName = (CludesUIDB and CludesUIDB.activeProfile) or "Default"
    if not CludesUIDB then CludesUIDB = {} end
    if type(CludesUIDB.profiles) ~= "table" then CludesUIDB.profiles = {} end
    if type(CludesUIDB.profiles[profileName]) ~= "table" then CludesUIDB.profiles[profileName] = {} end
    local profileData = CludesUIDB.profiles[profileName]
    if not profileData.addons then profileData.addons = {} end
    for _, saved in ipairs(_preSVDBs) do
        if type(profileData.addons[saved.folder]) ~= "table" then profileData.addons[saved.folder] = {} end
        local profile = profileData.addons[saved.folder]
        if saved._profileDefaults then DeepMergeDefaults(profile, saved._profileDefaults) end
        saved.sv = CludesUIDB
        saved._profileName = profileName
        saved.profile = profile
        if _G[saved.svName] and type(_G[saved.svName]) == "table" then
            wipe(_G[saved.svName])
        else
            _G[saved.svName] = {}
        end
    end
    wipe(_preSVDBs)
end

-- Drain the OnEnable queue. The pre-steps (PP.mult refresh, spec-profile
-- pre-seed) run once, before any OnEnable body. The dispatch site decides
-- whether to call this synchronously or one tick deferred -- see the big
-- comment there for why the triggering event makes that choice.
local function FlushEnableQueue()
    -- Ensure PP.mult is current before any addon's OnEnable runs. PP is
    -- defined in CludesUI.lua (loaded after this file) so it exists by the
    -- time PLAYER_LOGIN fires.
    if CludesUI and CludesUI.PP and CludesUI.PP.UpdateMult then CludesUI.PP.UpdateMult() end
    -- Apply spec-assigned profile data into each child SV before any OnEnable
    -- runs. The spec API is available here (after OnInitialize, before
    -- OnEnable) so we can resolve the current spec and inject the correct
    -- profile snapshot. ADDON_LOADED is too early (spec API not ready yet).
    if CludesUI and CludesUI.PreSeedSpecProfile then CludesUI.PreSeedSpecProfile() end
    while #enableQueue > 0 do
        local addon = tremove(enableQueue, 1)
        if addon.enabledState then
            statuses[addon.name] = true
            safecall(addon.OnEnable, addon)
        end
    end
end

-- Account passes that must read the saved data exactly as it loaded: run once
-- at this addon's own ADDON_LOADED, before a pre-SavedVariables db is
-- re-rooted and before any OnInitialize opens a profile and merges defaults
-- into it -- in the suite and in every standalone alike.
local _svLoadedHooks = {}
function LiteKit.OnSavedVariablesLoaded(fn) _svLoadedHooks[#_svLoadedHooks + 1] = fn end

--- For those passes: true while CludesUIDB is still the stand-in a
--- pre-SavedVariables db built (a standalone's file-scope NewDB), with no saved
--- data loaded over it -- a fresh account, whatever the stand-in holds.
function LiteKit.StoreFromBeforeLoad()
    local saved = _preSVDBs[1]
    return saved ~= nil and saved.sv == CludesUIDB
end

local lifecycleFrame = CreateFrame("Frame")
lifecycleFrame:RegisterEvent("ADDON_LOADED")
lifecycleFrame:RegisterEvent("PLAYER_LOGIN")
lifecycleFrame:SetScript("OnEvent", function(self, evt, arg1)
    if evt == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            _parentDBRef = CludesUIDB
            for idx = 1, #_svLoadedHooks do
                safecall(_svLoadedHooks[idx])
            end
            wipe(_svLoadedHooks)
            if IS_STANDALONE then
                _svLoaded = true
                RerootPreSVDBs()
                -- Runtime files can cache default fonts before this addon's
                -- SavedVariables load. Resolve the saved choice when frames init.
                if CludesUI.InvalidateFontCache then CludesUI.InvalidateFontCache() end
            end
        elseif _dbGuardArmed and _parentDBRef and CludesUIDB ~= _parentDBRef then
            -- A stale SavedVariables copy from a child's WTF file replaced the central
            -- DB. Restore the real table; the stale copy purges from the offending file
            -- on its next logout (its TOC no longer declares the variable).
            CludesUIDB = _parentDBRef
        end
    elseif evt == "PLAYER_LOGIN" then
        _dbGuardArmed = false
    end

    -- Process init queue on every ADDON_LOADED (same as AceAddon)
    while #initQueue > 0 do
        local addon = tremove(initQueue, 1)
        safecall(addon.OnInitialize, addon)
        tinsert(enableQueue, addon)
    end

    -- Process the enable (OnEnable) queue once logged in. WHEN we run it
    -- depends on which event delivered us here, and both cases matter:
    --
    --   * PLAYER_LOGIN -> run SYNCHRONOUSLY, right now. PLAYER_LOGIN is a
    --     top-level game event, never dispatched from inside a secure chain,
    --     so the mid-secure-chain taint hazard below does not apply. Running
    --     here also keeps every OnEnable (and the secure setup each performs:
    --     RegisterStateDriver, WrapScript, protected SetCVar, EditMode Hide)
    --     inside the login/reload LOADING-SCREEN window -- the only window in
    --     which those secure operations are permitted while the player is in
    --     combat. C_Timer callbacks do NOT run during the loading screen, so
    --     deferring here would always miss the window on a /reload in combat
    --     and every child addon's secure setup would be blocked
    --     (ADDON_ACTION_BLOCKED storm).
    --
    --   * ADDON_LOADED (post-login demand-loads) -> DEFER one tick. These can
    --     be dispatched from inside Blizzard's own SECURE executions (e.g.
    --     UIParent demand-loading Blizzard_CombatLog), and running OnEnable
    --     bodies synchronously there stamps every value they write with addon
    --     taint born mid-secure-chain -- fields Edit Mode's enter/exit passes
    --     later read, erroring on 12.x secret values. A timer callback is a
    --     fresh, purely addon-owned execution. Such loads happen after the
    --     loading screen anyway, so there is no in-combat secure window to
    --     preserve for them.
    if IsLoggedIn() and #enableQueue > 0 then
        if evt == "PLAYER_LOGIN" then
            FlushEnableQueue()
        elseif not lifecycleFrame._enableFlushQueued then
            lifecycleFrame._enableFlushQueued = true
            C_Timer.After(0, function()
                lifecycleFrame._enableFlushQueued = false
                FlushEnableQueue()
            end)
        end
    end
end)
