if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQuestTracker.lua - the Quest Tracker module's core.
--
--  Blizzard's ObjectiveTrackerFrame still draws the quests; this module skins
--  it, decides when it shows, and adds the quest conveniences (auto accept,
--  auto turn-in, the quest item hotkey, the splash frame). On WoW Forever a
--  profile can use our own tracker instead (CludesUIQuestTracker_Custom.lua).
--
--  This file holds the settings, the style the session renders in, the
--  suppression other modules use, the profile refresh and /cqt. The feature
--  files start once Blizzard_ObjectiveTracker and the login are both there.
-------------------------------------------------------------------------------
local addonName, mod = ...
if not (CludesUI and CludesUI._ModuleNS and CludesUI.NewCombatQueue) then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a part-updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring
CludesUI._ModuleNS[addonName] = mod -- the load-on-demand options find the module through this
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

local EQT = {}
mod.EQT = EQT
_G.CludesUIQuestTracker = EQT

-------------------------------------------------------------------------------
--  Settings. Keys of the old 3,807-line custom tracker are not here: the
--  migration (CludesUI_Migration.lua) files any saved ones under _legacy.
-------------------------------------------------------------------------------
local DEFAULTS = {
    profile = {
        questTracker = {
            enabled = true,
            forceOnScreen = true,
            visibility = "always",
            visOnlyInstances = false,
            visHideHousing = false,
            visHideMounted = false,
            visHideNoTarget = false,
            visHideNoEnemy = false,
            -- In a raid: "always" hides the tracker throughout, "boss" (the
            -- default) only during boss encounters.
            hideInRaidMode = "boss",

            -- The Style page (applies after a reload).
            useBlizzardStyle = false,
            useClassicStyle = false,

            skinHeaders = true,
            -- Blizzard's quest type icons and buttons on the right, instead
            -- of ours (applies after a reload).
            showQuestIcons = false,

            -- Text sizes, read by all the skin code.
            titleFontSize = 12,
            objectiveFontSize = 10,
            headerFontSize = 13,

            -- Our background frame behind the tracker.
            bgR = 0.035,
            bgG = 0.035,
            bgB = 0.035,
            bgAlpha = 0.75,
            showTopLine = true,

            -- Text colours: titles, completed objectives, the focused quest.
            titleR = 1.000,
            titleG = 0.910,
            titleB = 0.471, -- FFE878
            completedR = 0.251,
            completedG = 1.000,
            completedB = 0.349, -- 40FF59
            focusR = 0.871,
            focusG = 0.251,
            focusB = 1.000, -- DE40FF

            -- Conveniences.
            autoAccept = false,
            autoAcceptPreventMulti = true,
            autoAcceptShiftEnable = false,
            autoAcceptShiftSkip = true,
            autoAcceptIgnoreTrivial = false,
            autoAcceptIgnoreOldExpansion = false,
            autoTurnIn = false,
            autoTurnInShiftEnable = false,
            autoTurnInShiftSkip = true,
            questItemHotkey = nil,
        },
    },
}
-- WoW Forever's quest tools add their keys here as they load
-- (CludesUIQuestTracker_Forever.lua), before the database is made.
mod.QT_DEFAULTS = DEFAULTS

local db
local function Database()
    if not db and CludesUI and CludesUI.Lite then
        db = CludesUI.Lite.NewDB("CludesUIQuestTrackerDB", DEFAULTS)
        _G._CUQT_DB = db
    end
    return db
end

-- The profile's quest tracker settings, if the database is ready.
local function SavedSettings()
    local d = Database()
    return d and d.profile and d.profile.questTracker
end

function EQT.DB()
    local qt = SavedSettings()
    if qt then
        return qt
    end
    -- Before the database is ready (login, a profile or spec switch): a stand-in
    -- that keeps the tracker shown. Without enabled and a visibility mode the
    -- visibility check would hide the tracker on any unrelated event meanwhile.
    if not EQT._tmpDB then
        EQT._tmpDB = { enabled = true, visibility = "always" }
    end
    return EQT._tmpDB
end

function EQT.Cfg(key)
    return EQT.DB()[key]
end
function EQT.Set(key, value)
    EQT.DB()[key] = value
end

-- The style a profile's saved flags ask for: "cui" | "blizzard" | "classic".
local function StyleOf(qt)
    return (qt.useClassicStyle and "classic") or (qt.useBlizzardStyle and "blizzard") or "cui"
end

-- The style this session renders, read from the profile once and kept (a
-- profile switch asks for a reload instead). Its first caller is the core's
-- font pass at login, before the module starts, so it opens the database
-- itself; it never reads EQT.DB(), whose stand-in would fix "cui" too early.
function mod.QT_Style()
    if mod._qtStyle == nil then
        local qt = SavedSettings()
        if not qt then
            return "cui"
        end
        mod._qtStyle = StyleOf(qt)
    end
    return mod._qtStyle
end

-- WoW Forever: whether a profile wants our tracker instead of Blizzard's.
-- Its own pick decides (customTrackerPick, saved only where it differs from
-- the style's answer); with no pick, the CludesUI style alone turns it on. A
-- false in the older customTracker key also counts as a pick; a true there
-- never was one (that key read true for everyone who had not turned it off).
function mod.CustomTrackerWanted(qt)
    if CludesUI.IS_FOREVER ~= true then
        return false
    end
    local pick = qt.customTrackerPick
    if pick == nil and qt.customTracker == false then
        pick = false
    end
    if pick ~= nil then
        return pick
    end
    return StyleOf(qt) == "cui"
end

-- The options toggle (the tracker in use stays the same until a reload).
function mod.SetCustomTrackerWanted(qt, on)
    on = on and true or false
    qt.customTracker = nil
    if on == (StyleOf(qt) == "cui") then
        qt.customTrackerPick = nil
    else
        qt.customTrackerPick = on
    end
end

-- Whether this session uses our tracker (WoW Forever); kept like the style.
function mod.UseCustomTracker()
    if mod._customTracker == nil then
        local qt = SavedSettings()
        if not qt then
            return false
        end
        mod._customTracker = mod.CustomTrackerWanted(qt)
    end
    return mod._customTracker
end

-- Either stock style: Blizzard's own tracker art and text.
function EQT.Blizz()
    return mod.QT_Style() ~= "cui"
end
function EQT.Classic()
    return mod.QT_Style() == "classic"
end

-------------------------------------------------------------------------------
--  Suppression: another module (the M+ Timer's preview, say) can hide the
--  tracker with _CUQT_SetSuppressed(key, true). Callers stack: it shows again
--  when every key is released. The tracker frame is moved into a hidden
--  parent; its children are never touched.
-------------------------------------------------------------------------------
local suppressors = {}
function _G._CUQT_SetSuppressed(key, on)
    if not key then
        return
    end
    suppressors[key] = on and true or nil
    if EQT.ApplySuppression then
        EQT.ApplySuppression(next(suppressors) ~= nil)
    end
end
function EQT.IsSuppressed()
    return next(suppressors) ~= nil
end

-------------------------------------------------------------------------------
--  Start-up
-------------------------------------------------------------------------------
-- Blizzard_ObjectiveTracker is part of the base UI and loads before us, so
-- its ADDON_LOADED is usually missed: check it is already there.
local sawSelf, sawTracker, loggedIn = false, false, false
if C_AddOns.IsAddOnLoaded("Blizzard_ObjectiveTracker") or _G.ObjectiveTrackerFrame then
    sawTracker = true
end

local starter = CreateFrame("Frame")
starter:RegisterEvent("ADDON_LOADED")
starter:RegisterEvent("PLAYER_LOGIN")

local function Start()
    if not (sawSelf and sawTracker and loggedIn) then
        return
    end
    Database()
    local custom = mod.UseCustomTracker()
    if custom then
        EQT.InitCustom()
    else
        if EQT.InitSkin then
            EQT.InitSkin()
        end
        if EQT.InitVisibility then
            EQT.InitVisibility()
        end
    end
    if EQT.InitQoL then
        EQT.InitQoL()
    end
    -- Our tracker has its own mover; this one moves Blizzard's frame.
    if EQT.InitPosition and not custom then
        EQT.InitPosition()
    end
    starter:UnregisterAllEvents()
end

starter:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        sawSelf = sawSelf or name == addonName
        sawTracker = sawTracker or name == "Blizzard_ObjectiveTracker"
    elseif event == "PLAYER_LOGIN" then
        loggedIn = true
    end
    Start()
end)

-------------------------------------------------------------------------------
--  Profile refresh: CludesUI.RefreshAllAddons calls this after a profile
--  switch, so everything is read again without a reload. Order matters where
--  noted.
-------------------------------------------------------------------------------
local REFRESH_STEPS = {
    "RefreshFonts",
    "UpdateVisibility",
    "RestyleAll",
    -- Before the background: its top edge depends on whether the header shows.
    "ApplyMasterHeaderVisibility",
    "ApplyBackground",
    "ApplyForceOnScreen",
    "SyncPosition",
    -- The hotkey is per profile and held by an override binding: without this
    -- the old profile's key stays taken (over whatever the player bound
    -- there) and the new profile's key is never set.
    "ApplyQuestItemHotkey",
    "SyncAutoQuests",
    -- WoW Forever's quest tools (absent on retail).
    "ApplyQuestWatches",
    "ApplyQuestProgress",
    "ApplyQuestLinks",
}
_G._CUQT_RefreshAll = function()
    for _, step in ipairs(REFRESH_STEPS) do
        if EQT[step] then
            EQT[step]()
        end
    end
end

-------------------------------------------------------------------------------
--  /cqt show | hide | toggle, or nothing to open the settings.
-------------------------------------------------------------------------------
local function SetShown(on)
    EQT.Set("enabled", on)
    if EQT.UpdateVisibility then
        EQT.UpdateVisibility()
    end
end

SLASH_EQT1 = "/cqt"
SlashCmdList.EQT = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "show" then
        SetShown(true)
    elseif msg == "hide" then
        SetShown(false)
    elseif msg == "toggle" then
        SetShown(not EQT.Cfg("enabled"))
    elseif not (InCombatLockdown and InCombatLockdown()) then
        CludesUI:ShowModule("CludesUIQuestTracker")
    end
end
