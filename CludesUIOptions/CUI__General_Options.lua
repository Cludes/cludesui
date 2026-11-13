if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI__General_Options.lua -- Global Settings module (CVar-based settings
--  shared by all CludesUI addons).
--
--  Default-application policy: CUI preferred defaults apply ONLY while
--  C_CVar.GetCVarInfo shows the CVar still at Blizzard's default (untouched
--  by player/other addon). Widgets always read the live CVar to stay in sync.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL      = "General"
local PAGE_FONTS       = "Fonts"     -- centralized fonts page; body lives in CUI_Fonts_Options.lua
local PAGE_TEXTURES    = "Textures"  -- centralized textures page; body lives in CUI_Textures_Options.lua
local PAGE_GLOWS       = "Glows"     -- centralized glow page; body lives in CUI_Glows_Options.lua
local PAGE_GAMEPAD     = "Gamepad"   -- controller settings page; body lives in CUI_Gamepad_Options.lua
local PAGE_STYLE       = "Style"     -- per-module CludesUI / Blizzard Style page; body lives in CUI_Style_Options.lua
local PAGE_COLORS      = "Colors"    -- the color half of the old "Fonts & Colors" page
local PAGE_NUMBERS     = "Numbers"   -- Number Format page; body lives in CUI_NumberFormat_Options.lua
local PAGE_PROFILES    = "Profiles"
local PAGE_WHATSNEW    = "Patch Notes"

-- Profiles/Patch Notes/CUI Legends are their own sidebar pages, not tabs under Global Settings. Keys match the sidebar buttons in CludesUI_Panel.lua.
local PROFILES_KEY     = "_CUIProfiles"
local PATCHNOTES_KEY   = "_CUIPatchNotes"

-- Standalone single-module builds rename the host addon to contain "Standalone". The What's New tab is suite-only, so it is never added to the page list there.
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil

-------------------------------------------------------------------------------
--  Shared CDM spell-layout export flow (full-profile AND per-addon export).
--  Asks to bundle the CDM spell layout (bar assignments + per-spell settings);
--  Yes opens the spec picker, then calls exportFn(includeCDM, cdmSpecs).
--  Exports ONLY on explicit "No" or a completed picker pick -- escaping
--  either popup produces NO export.
-------------------------------------------------------------------------------
function CludesUI.RunCDMSpellExportFlow(activeName, exportFn)
    local function pickThenExport()
        local specs = {}
        local sp = CludesUIDB and CludesUIDB.spellAssignments
            and CludesUIDB.spellAssignments.profiles
            and CludesUIDB.spellAssignments.profiles[activeName]
            and CludesUIDB.spellAssignments.profiles[activeName].specProfiles
        local n = CludesUI.IS_FOREVER and 0 or ((GetNumSpecializations and GetNumSpecializations()) or 0)
        for i = 1, n do
            local specID = GetSpecializationInfo and GetSpecializationInfo(i)
            if specID then
                local key = tostring(specID)
                local d = sp and sp[key]
                specs[#specs + 1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true or false,
                }
            end
        end
        -- WoW Forever: one row, the store key the player's class uses.
        if CludesUI.IS_FOREVER then
            local id = CludesUI.ForeverClassSpec(nil, CludesUI.SpecHasStringEntry, sp or {}, true)
            if id then
                local key = tostring(id)
                local d = sp and sp[key]
                specs[1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true or false,
                }
            end
        end
        CludesUI:ShowCDMSpecPickerPopup({
            title         = CludesUI.L("Export CDM Spells"),
            foreverAllKeys = true,
            subtitle      = CludesUI.L("This can't change which spells the user tracks in Blizzard's CDM.\nIt's recommended to also share your Blizzard CDM layout for any spec you choose here."),
            subtitleColor = { 1, 0.82, 0.2 },
            subtitleAtBottom = true,
            confirmText   = CludesUI.L("Export"),
            specs         = specs,
            onConfirm     = function(selectedSpecs) exportFn(true, selectedSpecs) end,
            onCancel      = function() end,  -- cancel / Esc / click-off: just close, NO export
        })
    end
    CludesUI:ShowConfirmPopup({
        title       = CludesUI.L("Include CDM Spell Layout?"),
        message     = CludesUI.L("Include your Cooldown Manager spell layout (which spells sit on which bars) plus all per-spell settings for any specs you choose."),
        confirmText = CludesUI.L("Yes"),
        cancelText  = CludesUI.L("No"),
        onConfirm   = function() pickThenExport() end,
        onCancel    = function() exportFn(false, nil) end,  -- "No": export WITHOUT layout
        onDismiss   = function() end,  -- Esc / click-off: just close, NO export
    })
end

-- Language-picker font: each entry is entirely one script (the CJK stock fonts
-- also cover the trailing "(Korean)"-style Latin text), so a plain per-entry
-- font from the locale system's own glyph table beats a multi-script family.
local function LP_FontFor(locale)
    local fn = CludesUI.LocaleGlyphFont
    return (fn and fn(locale)) or (CludesUI.MEDIA_PATH .. "fonts\\Barlow Condensed.ttf")
end

-------------------------------------------------------------------------------
--  Patch-notes content for the What's New page (newest first). Entry `nav`
--  deep-links via NavigateToElementSettings(module, page, section, preSelect, highlight).
-------------------------------------------------------------------------------
CludesUI._WHATSNEW_PATCHES = {
    {
        version = "1.0.0",
        features = {
            { module = "Tank Kit",
              title  = "A module made for tanks",
              desc   = "Your co-tank's health, debuffs and defensives beside your frames, with TAUNT alerts, plus a row of the externals other players put on you. Its settings are under Tank Kit in this panel, or type /ctank. Move its frames in Layout Mode." },
            { module = "Raid Lead",
              title  = "Sort or split the raid",
              desc   = "/raidlead roles sorts the raid into tanks, melee, ranged and healers. /raidlead split makes two balanced halves. /raidlead undo puts everyone back." },
            { module = "Raid Lead",
              title  = "Encounter reminders",
              desc   = "Paste a boss note from wowutils, wowaudit or a Method Raid Tools note. At the pull, your lines show before their time with a countdown, spoken if you like. The leader can send notes to the group." },
            { module = "Raid Lead",
              title  = "Invites, assistants and version check",
              desc   = "Invite a saved roster, promote assistants as they join, and see who runs which CludesUI version." },
            { module = "Raid Lead",
              title  = "Ready check gear and cooldowns",
              desc   = "On a ready check, CludesUI users report durability, item level, missing enchants, raid cooldowns not ready, and a missing flask, food, rune or healthstone. The leader sees the list." },
            { module = "Raid Lead",
              title  = "Immunities on You and Boss Pace",
              desc   = "Icons for immunities on you, and a boss health bar against your target kill time: green ahead, red behind." },
            { module = "Raid Lead",
              title  = "Nicknames, synced with your guild",
              desc   = "Set your nickname once; other CludesUI users in your guild and group see it on their frames." },
            { module = "Raid Lead",
              title  = "Break timer",
              desc   = "/raidlead break 5 puts a break countdown on every CludesUI user's screen, with a sound when it ends. Buttons are under Raid Lead > Setup." },
            { module = "Raid Lead",
              title  = "Kick rotation",
              desc   = "Whose interrupt is next, from an intstart / intend block in the boss note or a Kick Order you type. Red with a sound when it is your turn." },
            { module = "Raid Lead",
              title  = "Aura Glows",
              desc   = "A glowing icon while an aura you pick is on you, built on the game's own aura display so it works in boss fights. Under Raid Lead > Tracking." },
            { module = "Raid Lead",
              title  = "Feasts, gateways and stats",
              desc   = "A chat line when a CludesUI user drops a feast or cauldron, Gateway usable when you can click a Demonic Gateway, and a stats panel. Under Raid Lead > Tracking." },
            { module = "Raid Lead",
              title  = "Aura Sounds",
              desc   = "Play a sound when an aura you pick is applied to you, gains a stack or falls off. The game plays it, so it works in boss fights." },
            { module = "Forever Tools",
              title  = "Training Planner",
              desc   = "On WoW Forever: what your trainer has for you now and its total price, what the next levels bring, and a chat line when you level up. Find it under Forever Tools > Training." },
            { module = "Forever Tools",
              title  = "Tracking Reminder",
              desc   = "On WoW Forever: icons for tracking you know but have not turned on. Click one to turn it on. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Swing Timer",
              desc   = "On WoW Forever: a bar per weapon filling to your next auto attack, from the swing length the game sends. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Mana Bar and five-second rule",
              desc   = "On WoW Forever: your mana while in Bear or Cat Form, and a line counting down the five-second rule after you spend mana. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Consumable Bar",
              desc   = "On WoW Forever: the consumables in your bags on a clickable bar, with counts and cooldowns. Pick which kinds under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Raid Debuffs",
              desc   = "On WoW Forever: the raid debuffs you pick on your target, bright while up, dim while missing. Works in combat. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Gear Sets",
              desc   = "On WoW Forever: your equipment sets on a bar to swap with a click, plus optional sets for mounted and resting. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Instance Tracker",
              desc   = "On WoW Forever: new instances this hour against the cap, a run timer, and a summary of time, deaths, XP and loot when you leave. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Group Inspect",
              desc   = "On WoW Forever: /cinspect lists everyone in your group with level, item level and unenchanted slots. Click a name for the full inspect window." },
            { module = "Forever Tools",
              title  = "Combat extras",
              desc   = "On WoW Forever: a combat timer, a + Combat / - Combat alert, and a stealth reminder for rogues and cat druids. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Bag Space",
              desc   = "On WoW Forever: free bag slots on screen, a warning when nearly full, and the cheapest items you carry on hover." },
            { module = "Forever Tools",
              title  = "Quest Automation",
              desc   = "On WoW Forever: accepts and turns in quests, stops when you have a reward to choose, and can post objective progress to your party. Hold Shift to skip." },
            { module = "Forever Tools",
              title  = "Action Bar Profiles",
              desc   = "On WoW Forever: save your action bars and keybinds under a name and load them on any character of the same class. /cbars or Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Loot Sparkles",
              desc   = "On WoW Forever: keeps the sparkle on lootable quest items, even after a graphics preset turns it off. Under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Best in Slot list",
              desc   = "On WoW Forever: Alt+Shift-click any item to make it your pick for its slot. /cbis shows the list and what you have; tooltips mark BiS items, and a Drop Alert warns when one drops." },
            { module = "Forever Tools",
              title  = "Stat Weights and upgrades",
              desc   = "On WoW Forever: +X% upgrade on gear tooltips for your spec, and each BiS pick's gain. Change any weight under Forever Tools > General." },
            { module = "Forever Tools",
              title  = "Dungeon Journal",
              desc   = "On WoW Forever: /cjournal shows every dungeon and raid with bosses, loot and drop chances, a tip per boss and the quests." },
            { module = "Mythic+ Tools",
              title  = "Title Line",
              desc   = "Your Mythic+ rating against the 0.1% and 1% title lines, with a season graph. Open it with /titleline." },
            { module = "Global Settings",
              title  = "Class colour by default",
              desc   = "A fresh install opens in your class colour. Pick any other theme under CUI Options Theme." },
            { module = "Global Settings",
              title  = "Frost blue house colour",
              desc   = "The CludesUI theme, logo and highlights are frost blue." },
            { module = "Global Settings",
              title  = "Five new colour themes",
              desc   = "Ember, Blood, Arcane, Gold and Toxic join the theme list." },
            { module = "Global Settings",
              title  = "Barlow Condensed is the default font",
              desc   = "Change it under Fonts. Expressway and the other fonts are still in the list." },
            { module = "Profiles",
              title  = "Import older profile strings",
              desc   = "Import Profile also accepts strings in the older format and converts them as it imports." },
            { module = "Global Settings",
              title  = "Shorter slash commands",
              desc   = "/cui opens the panel and /ce the global settings. Each addon has its own shortcut, such as /cab, /cuf, /crf and /cnp." },
        },
        fixes = {
            { module = "Global Settings", text = "Panel artwork loads when a theme is picked instead of all at login, which uses less video memory." },
            { module = "Raid Frames", text = "Nicknames from Timeline Reminders, Northern Sky, Liquid and RakGaming Aliases are picked up again." },
        },
    },
}

-------------------------------------------------------------------------------
--  FCT font -- handled by CludesUI_Startup.lua which runs earlier.
-------------------------------------------------------------------------------

-- Wait for CludesUI to exist
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not CludesUI or not CludesUI.RegisterModule then return end
    local PP = CludesUI.PanelPP

    local GLOBAL_KEY = CludesUI.GLOBAL_KEY or "_CUIGlobal"
    local floor = math.floor
    local ceil  = math.ceil
    local max   = math.max

    ---------------------------------------------------------------------------
    --  CVar helpers
    ---------------------------------------------------------------------------
    local function GetCVarNum(cvar)
        return tonumber(GetCVar(cvar)) or 0
    end

    local function SetCVarSafe(cvar, value)
        if InCombatLockdown() then return end
        CludesUI.SetCVar(cvar, value)
    end

    -- Graphics and sound settings (Optimize My FPS and Graphics, its Restore and
    -- Increase Game Image Quality) are written as they are, not through
    -- CludesUI.SetCVar: Optimize keeps its own Restore, and Uninstall CUI
    -- never touches them.
    local function SetGfxCVar(cvar, value)
        if InCombatLockdown() then return end
        SetCVar(cvar, value)
    end

    --- Returns current, default as strings (nil-safe)
    local function CVarInfo(cvar)
        local cur, def = C_CVar.GetCVarInfo(cvar)
        return cur or "", def or ""
    end

    --- True while the CVar sits at Blizzard's built-in default (untouched by player or addon).
    local function IsAtBlizzardDefault(cvar)
        local cur, def = CVarInfo(cvar)
        return cur == def
    end

    ---------------------------------------------------------------------------
    --  CUI preferred defaults -- only applied when CVar == Blizzard default
    --
    --  { cvarName, cuiPreferred }
    ---------------------------------------------------------------------------
    local CUI_DEFAULTS = {
        { "cameraDistanceMaxZoomFactor",                    "2.6" },
        { "ActionButtonUseKeyDown",                         "1"   },
    }

    --- Walk the table once at login and apply only where safe.
    local function ApplySmartDefaults()
        for _, entry in ipairs(CUI_DEFAULTS) do
            local cvar, preferred = entry[1], entry[2]
            if IsAtBlizzardDefault(cvar) then
                SetCVarSafe(cvar, preferred)
            end
        end
    end
    ApplySmartDefaults()

    -- Apply suppress lua errors on login (default: ON)
    if not CludesUIDB or CludesUIDB.suppressErrors ~= false then
        SetCVarSafe("scriptErrors", "0")
    end

    -- Optimized graphics settings are NOT re-applied on login: SetCVar already persists, so re-applying would override the user's manual adjustments.

    ---------------------------------------------------------------------------
    --  General page
    ---------------------------------------------------------------------------
    local function BuildGeneralPage(pageName, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        parent._showRowDivider = true

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  Optimized graphics CVar table + buttons (above all sections)
        -------------------------------------------------------------------
        local OPTIMIZED_CVARS = {
            { "graphicsShadowQuality",      "1" },
            { "graphicsLiquidDetail",       "0" },
            { "graphicsParticleDensity",    "5" },
            { "graphicsSSAO",              "0" },
            { "graphicsDepthEffects",       "0" },
            { "graphicsComputeEffects",     "0" },
            { "graphicsOutlineMode",        "0" },
            { "graphicsTextureResolution",  "2" },
            { "graphicsSpellDensity",       "0" },
            { "graphicsProjectedTextures",  "1" },
            { "graphicsViewDistance",        "0" },
            { "graphicsEnvironmentDetail",  "0" },
            { "graphicsGroundClutter",      "0" },
            { "RAIDsettingsEnabled",        "0" },
            { "ResampleAlwaysSharpen",      "1" },
            -- Reverb runs a full effect bus over the mix; disabling it trims audio DSP work and keeps spell/interrupt cues dry and crisp.
            { "Sound_EnableReverb",         "0" },
        }

        local function ApplyOptimizedGfx()
            -- Refused in combat, where SetGfxCVar writes nothing: a backup taken
            -- then would turn the card into Restore with nothing optimized.
            if InCombatLockdown() then return end
            if not CludesUIDB then CludesUIDB = {} end
            -- One-time store: only snapshot if no backup exists yet
            if not CludesUIDB.gfxBackup then
                local backup = {}
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    backup[entry[1]] = GetCVar(entry[1])
                end
                backup["Contrast"] = GetCVar("Contrast")
                CludesUIDB.gfxBackup = backup
            else
                -- Backfill CVars added to the list after the original snapshot so Restore covers them too.
                local backup = CludesUIDB.gfxBackup
                for _, entry in ipairs(OPTIMIZED_CVARS) do
                    if backup[entry[1]] == nil then
                        backup[entry[1]] = GetCVar(entry[1])
                    end
                end
            end
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                SetGfxCVar(entry[1], entry[2])
            end
            local curContrast = tonumber(GetCVar("Contrast")) or 50
            if curContrast <= 55 then
                SetGfxCVar("Contrast", curContrast + 10)
            end
            local rl = CludesUI._widgetRefreshList
            if rl then for i = 1, #rl do rl[i]() end end
        end

        local function RestoreGfxSettings()
            if not CludesUIDB or not CludesUIDB.gfxBackup then return end
            if InCombatLockdown() then return end
            local backup = CludesUIDB.gfxBackup
            for _, entry in ipairs(OPTIMIZED_CVARS) do
                local saved = backup[entry[1]]
                if saved then SetGfxCVar(entry[1], saved) end
            end
            if backup["Contrast"] then SetGfxCVar("Contrast", backup["Contrast"]) end
            CludesUIDB.gfxBackup = nil
            local rl2 = CludesUI._widgetRefreshList
            if rl2 then for i = 1, #rl2 do rl2[i]() end end
        end

        -------------------------------------------------------------------
        --  TOP SECTION: one row, Reset CUI Module Settings | Optimize My FPS
        --  and Graphics | Uninstall CUI. While a graphics backup exists the
        --  Optimize card restores it instead.
        -------------------------------------------------------------------
        local MEDIA_ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"
        -- Red for stop (Reset ALL, Uninstall, Restore), CludesUI's own green
        -- (#4cc9f0) for go (Optimize and its link): fixed, never the theme accent.
        local WARN = { r = 0.9, g = 0.3, b = 0.3 }
        local GO = { r = 0x0c / 255, g = 0xd2 / 255, b = 0x9d / 255 }

        -- Reset ALL's wipe: every CUI addon back to its defaults.
        local function ResetAllNow()
            -- Nuclear wipe: same logic as the beta-exit popup
            local svNames = {
                "CludesUIActionBarsDB",
                "CludesUIAuraBuffRemindersDB",
                "CludesUICooldownManagerDB",
                "CludesUINameplatesDB",
                "CludesUIResourceBarsDB",
                "CludesUIUnitFramesDB",
            }
            for _, name in ipairs(svNames) do
                _G[name] = {}
            end
            -- Loadout Manager keeps a per-character store outside the profiles:
            -- this clears it for the character doing the reset.
            CludesUILoadoutManagerDB = nil
            -- Bags' offline bank keeps every character's saved bags and banks outside them too
            CludesUIBagsInventoryDB = nil
            local oldScale = CludesUIDB and CludesUIDB.ppUIScale
            local oldScaleAuto = CludesUIDB and CludesUIDB.ppUIScaleAuto
            -- Preserve friend group data across reset
            local oldGlobal = CludesUIDB and CludesUIDB.global
            local savedFriends
            if oldGlobal then
                savedFriends = {
                    friendGroups = oldGlobal.friendGroups,
                    friendGroupsByTag = oldGlobal.friendGroupsByTag,
                    friendGroupsTagMigrated = oldGlobal.friendGroupsTagMigrated,
                    friendAssignments = oldGlobal.friendAssignments,
                    friendGroupOrder = oldGlobal.friendGroupOrder,
                    friendGroupColors = oldGlobal.friendGroupColors,
                    friendNotes = oldGlobal.friendNotes,
                    friendFavCollapsed = oldGlobal.friendFavCollapsed,
                    friendPendingCollapsed = oldGlobal.friendPendingCollapsed,
                    friendUngroupedCollapsed = oldGlobal.friendUngroupedCollapsed,
                }
            end
            -- Preserve QoL settings (stored on CludesUIDB root)
            local qolKeys = {
                "autoOpenContainers", "autoSellJunk", "autoRepair",
                "autoRepairGuild", "hideScreenshotStatus", "autoUnwrapCollections",
                "trainAllButton", "ahCurrentExpansion", "quickLoot",
                "autoFillDelete", "skipCinematics", "skipCinematicsAuto",
                "bonusRollConfirmation", "bonusRollOnly",
                "autoInsertKeystone", "quickSignup",
                "persistSignupNote", "signupNote", "hideBlizzardPartyFrame",
                "instanceResetAnnounce", "instanceResetAnnounceMsg",
                "macroFactory",
            }
            local savedQoL = {}
            for _, k in ipairs(qolKeys) do
                if CludesUIDB[k] ~= nil then
                    savedQoL[k] = CludesUIDB[k]
                end
            end
            -- Game settings, not CUI ones: the record of the settings from
            -- before CUI (Uninstall CUI) and Optimize Graphics' Restore values.
            local oldRestore = CludesUIDB.restoreOnUninstall
            local oldGfx = CludesUIDB.gfxBackup
            _G["CludesUIDB"] = {}
            CludesUIDB = _G["CludesUIDB"]
            CludesUIDB.restoreOnUninstall = oldRestore
            CludesUIDB.gfxBackup = oldGfx
            if oldScale then CludesUIDB.ppUIScale = oldScale end
            if oldScaleAuto ~= nil then CludesUIDB.ppUIScaleAuto = oldScaleAuto end
            if savedFriends then
                if not CludesUIDB.global then CludesUIDB.global = {} end
                for k, v in pairs(savedFriends) do
                    CludesUIDB.global[k] = v
                end
            end
            for k, v in pairs(savedQoL) do
                CludesUIDB[k] = v
            end
        end

        -- Reset ALL: a typed confirm, then the wipe and a reload (the wipe runs
        -- as RequestReload's pre-reload work).
        local function ConfirmResetAll()
            CludesUI:ShowConfirmPopup({
                title         = "Reset ALL Settings",
                -- The wipe replaces the whole account store, profiles included.
                message       = "Are you sure you want to reset ALL CUI addon settings to their defaults? This deletes ALL of your profiles, not just the current one, and reloads your UI.",
                disclaimer    = "Every profile on this account is deleted. Export any profile you want to keep first.",
                typeToConfirm = "Confirm",
                confirmText   = "Reset All & Reload",
                cancelText    = "Cancel",
                onConfirm     = function()
                    CludesUI.RequestReload(CludesUI.L("Reset ALL Settings"),
                        CludesUI.L("Reload to finish resetting CUI."), ResetAllNow)
                end,
            })
        end

        -- Uninstall CUI is refused in combat (it reloads) and while Edit Mode is open (it
        -- saves its own copy of the layouts on exit, over the ones put back). True when
        -- it was refused.
        local function UninstallRefused()
            local msg
            if InCombatLockdown() then
                msg = CludesUI.L("Uninstalling reloads the UI and cannot run in combat. Leave combat and try again.")
            elseif CludesUI.EditModeOpen() then
                msg = CludesUI.L("Close Edit Mode first, then try again.")
            end
            if not msg then return false end
            CludesUI:ShowConfirmPopup({
                title       = CludesUI.L("Uninstall CUI"),
                message     = msg,
                confirmText = CludesUI.L("OK"),
                hideCancel  = true,
            })
            return true
        end

        -- Uninstall CUI: puts back the game settings CludesUI changed, turns it off for
        -- every character and reloads (CludesUI_Uninstall.lua). Profiles are kept. The
        -- reload is a RequestReload from onConfirm, not reload = true: the refusal is
        -- checked again there, and reload = true would reload even when it is refused.
        local function ConfirmUninstall()
            if UninstallRefused() then return end
            local message = CludesUI.L("Puts back the game settings CUI changed, such as nameplate, action bar, chat and tooltip options, and turns CUI off for every character, then reloads the UI.") .. "\n\n"
                .. CludesUI.L("Your profiles are kept, so you can turn CUI back on later in the AddOns list.")
            if CludesUIDB and CludesUIDB.gfxBackup then
                message = message .. "\n\n" .. CludesUI.L("Graphics changed by Optimize My FPS and Graphics stay as they are. To undo them, click Restore My Graphics Settings first.")
            end
            CludesUI:ShowConfirmPopup({
                title         = CludesUI.L("Uninstall CUI"),
                message       = message,
                disclaimer    = (not CludesUI.UninstallKnowsOriginals())
                    and CludesUI.L("CUI was installed before it kept a record of your original settings, so the settings it still manages go back to the game's defaults.")
                    or nil,
                confirmText   = CludesUI.L("Uninstall & Reload"),
                cancelText    = CludesUI.L("Cancel"),
                onConfirm     = function()
                    if UninstallRefused() then return end
                    CludesUI.RequestReload(CludesUI.L("Uninstall CUI"),
                        CludesUI.L("Reload to finish uninstalling CUI."), CludesUI.Uninstall)
                end,
            })
        end

        -- The first card's two forms: Optimize, or Restore while a backup exists
        -- (restore given: that form, else the current one).
        local function HasGfxBackup() return (CludesUIDB and CludesUIDB.gfxBackup) ~= nil end
        local function GfxCardContent(restore)
            if restore == nil then restore = HasGfxBackup() end
            if restore then
                return MEDIA_ICONS .. "undo.png", CludesUI.L("Restore My Graphics Settings"),
                    CludesUI.L("Put back your graphics from before optimizing.")
            end
            return MEDIA_ICONS .. "optimize.png", CludesUI.L("Optimize My FPS and Graphics"),
                CludesUI.L("Tune graphics for higher FPS and clarity.")
        end

        -- One row of plain text buttons: Reset ALL, then in the middle Optimize
        -- (a boxed button, with its "What Does This Do?" link under it) or
        -- Restore (plain and red like the others), then Uninstall.
        local GFX_GAP = 8

        -- "What Does This Do?": what Optimize changes. Built first, so the
        -- card's footer can take its measured height.
        local infoBtn = CreateFrame("Button", nil, parent)
        infoBtn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local infoH
        do
            local EG = GO
            local infoFS = infoBtn:CreateFontString(nil, "OVERLAY")
            infoFS:SetFont(CludesUI.EXPRESSWAY, 12, CludesUI.GetFontOutlineFlag())
            infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70)
            infoFS:SetText(CludesUI.L("What Does This Do?"))
            infoFS:SetPoint("TOP")
            infoH = math.ceil(infoFS:GetStringHeight())
            infoBtn:SetSize(infoFS:GetStringWidth() + 10, infoH)
            infoBtn:SetScript("OnEnter", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 1) end)
            infoBtn:SetScript("OnLeave", function() infoFS:SetTextColor(EG.r, EG.g, EG.b, 0.70) end)
            -- Three parts, each its own translation.
            local CHANGES = "What we change:\n\n"
                .. "Shadow Quality - Fair (balanced quality/FPS)\n"
                .. "Liquid Detail - Disabled\n"
                .. "Particle Density - Set to Ultra (keeps important spell effects)\n"
                .. "SSAO (Ambient Occlusion) - Disabled\n"
                .. "Depth Effects - Disabled\n"
                .. "Compute Effects - Disabled\n"
                .. "Outline Mode - Disabled\n"
                .. "Texture Resolution - Set to High\n"
                .. "Spell Density - Set to Essential\n"
                .. "Projected Textures - Enabled (needed for ground effects)\n"
                .. "View Distance - Reduced to 1\n"
                .. "Environment Detail - Reduced to 1\n"
                .. "Ground Clutter - Reduced to 1\n"
                .. "Raid/Dungeon Settings - Uses same settings everywhere\n"
                .. "Resample Sharpening - Enabled (crisper image)\n"
                .. "Contrast - Boosted by +10 (if currently 55 or below)\n"
                .. "Enable Reverb - Disabled (spell and interrupt audio cues stay crisp)\n\n"
                .. "These settings prioritize frame rate and visual clarity over environmental detail. Textures stay high quality so your character and the world still look perfect."
            infoBtn:SetScript("OnClick", function()
                CludesUI:ShowInfoPopup({
                    title = "FPS & Graphics Optimization",
                    content = CludesUI.L("This feature optimizes your in-game graphics settings to give you the best combination of high FPS and visual clarity.")
                        .. "\n\n" .. CludesUI.L("After optimizing, the button changes to 'Restore My Graphics Settings', which reverts every change.")
                        .. "\n\n\n" .. CludesUI.L(CHANGES),
                })
            end)
        end

        -- "What Does This Do?" explains Optimize, so it and its gap exist only
        -- in the Optimize form: under Restore the row has no footer and the
        -- page below moves up. A click that changes the form rebuilds the
        -- page for it. Its text keeps one width for both forms.
        local showInfo = not HasGfxBackup()
        local gfxIcon, gfxTitle, gfxDesc = GfxCardContent()
        local _, altTitle, altDesc = GfxCardContent(showInfo)
        local cards
        y, cards = CludesUI.BuildActionCardRow(parent, y, {
            -- A menu of ALL Settings and each module's own reset (CludesUI_Panel.lua).
            { icon = MEDIA_ICONS .. "sync.png", accent = WARN,
              title = CludesUI.L("Reset CUI Module Settings"),
              desc = CludesUI.L("Pick a module, or ALL, to return to defaults."),
              onClick = function(card) CludesUI._ShowModuleResetMenu(card, ConfirmResetAll) end },
            { icon = gfxIcon, title = gfxTitle, desc = gfxDesc,
              hero = showInfo, accent = showInfo and GO or WARN,
              sizeAlso = { altTitle, altDesc },
              onClick = function()
                  local had = HasGfxBackup()
                  if had then RestoreGfxSettings() else ApplyOptimizedGfx() end
                  if HasGfxBackup() ~= had then CludesUI:RefreshPage(true) end
              end },
            -- power.png's glyph fills its whole canvas: drawn smaller, it matches sync.png.
            { icon = MEDIA_ICONS .. "power.png", accent = WARN, iconSize = 22,
              title = CludesUI.L("Uninstall CUI"), desc = CludesUI.L("Revert CUI's changes and disable."),
              onClick = ConfirmUninstall },
        }, { inline = true, footer = showInfo and (GFX_GAP + infoH) or nil })
        local gfxCard = cards[2]
        -- The link rides the card: clearing the page search shows every
        -- top-level page frame again, which would bring it back over Restore.
        infoBtn:SetParent(gfxCard)
        infoBtn:SetFrameLevel(gfxCard:GetFrameLevel() + 5)
        infoBtn:SetShown(showInfo)
        CludesUI.RegisterWidgetRefresh(function() gfxCard:SetCardContent(GfxCardContent()) end)
        PP.Point(infoBtn, "TOP", gfxCard, "BOTTOM", 0, -GFX_GAP)
        y = y - 6

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, h = W:SectionHeader(parent, "DISPLAY", y);  y = y - h

        local themeValues = {}
        for _, name in ipairs(CludesUI.THEME_ORDER) do
            themeValues[name] = name
        end

        -- Row 1: UI Accent Color | CUI Options Theme
        local themeRow
        themeRow, h = W:DualRow(parent, y,
            { type="multiSwatch", text="UI Accent Color",
              tooltip="Sets the accent color used across all CludesUI elements (tabs, glows, highlights, borders). Defaults to your theme color.",
              swatches = {
                { tooltip = "Class Color",
                  getValue = function()
                      local cr, cg, cb = CludesUI.GetPlayerClassColor()
                      return cr, cg, cb, 1
                  end,
                  setValue = function() end,
                  onClick = function()
                      -- Per-profile: set use-class, then re-resolve + apply live.
                      CludesUI.SetActiveProfileAccent(nil, true)
                      CludesUI.RefreshAccent()
                      CludesUI:RefreshPage()
                  end,
                  refreshAlpha = function()
                      return (select(1, CludesUI.GetActiveAccentState())) and 1 or 0.3
                  end },
                { tooltip = "Custom Color",
                  hasAlpha = false,
                  getValue = function()
                      local _, ca = CludesUI.GetActiveAccentState()
                      if ca then return ca.r, ca.g, ca.b, 1 end
                      return CludesUI.DEFAULT_ACCENT_R, CludesUI.DEFAULT_ACCENT_G, CludesUI.DEFAULT_ACCENT_B, 1
                  end,
                  setValue = function(r, g, b)
                      -- Persists per-profile (custom + useClass=false), applies live.
                      CludesUI.SetAccentColor(r, g, b)
                  end,
                  onClick = function(self)
                      if select(1, CludesUI.GetActiveAccentState()) then
                          -- Switch class -> custom: clear the per-profile class flag and re-resolve (profile custom -> global -> theme).
                          CludesUI.SetActiveProfileAccent(nil, false)
                          CludesUI.RefreshAccent()
                          CludesUI:RefreshPage()
                          return
                      end
                      if self._eabOrigClick then self._eabOrigClick(self) end
                  end,
                  refreshAlpha = function()
                      return (select(1, CludesUI.GetActiveAccentState())) and 0.3 or 1
                  end },
              } },
            { type="dropdown", text="CUI Options Theme",
              values=themeValues,
              order=CludesUI.THEME_ORDER,
              getValue=function()
                return CludesUI.GetActiveTheme()
              end,
              setValue=function(v)
                CludesUI.SetActiveTheme(v)
                -- Re-resolve the accent so the sidebar highlight tracks the theme.
                if CludesUI.RefreshAccent then
                    CludesUI.RefreshAccent()  -- ApplyAccentLive already refreshes the page
                else
                    CludesUI:RefreshPage()
                end
              end }
        );  y = y - h

        -- Inline color swatch on CUI Options Theme (right region)
        if not CludesUI._prebuilding then
            local rightRgn = themeRow._rightRegion
            local function isCustomColorOff()
                return CludesUI.GetActiveTheme() ~= "Custom Color"
            end

            local tcGet = function()
                local db = CludesUIDB
                local sa = db and db.accentColor
                if sa then return sa.r, sa.g, sa.b, 1 end
                return CludesUI.GetAccentColor()
            end
            local tcSet = function(r, g, b)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB.accentColor = { r = r, g = g, b = b }
                -- Only update the window background, not the accent color
                if CludesUI._applyBgTint then
                    CludesUI._applyBgTint(r, g, b)
                end
            end
            local tcSwatch, tcUpdateSwatch = CludesUI.BuildColorSwatch(rightRgn, rightRgn:GetFrameLevel() + 5, tcGet, tcSet, nil, 20)
            PP.Point(tcSwatch, "RIGHT", rightRgn._control, "LEFT", -12, 0)
            rightRgn._lastInline = tcSwatch
            CludesUI.RegisterWidgetRefresh(function()
                local off = isCustomColorOff()
                tcSwatch:SetAlpha(off and 0.15 or 1)
                tcSwatch:EnableMouse(not off)
                tcUpdateSwatch()
            end)
            tcSwatch:SetAlpha(isCustomColorOff() and 0.15 or 1)
            tcSwatch:EnableMouse(not isCustomColorOff())
            tcSwatch:SetScript("OnEnter", function(self)
                if isCustomColorOff() then
                    CludesUI.ShowWidgetTooltip(self, "This option is only available for the Custom Color Theme")
                end
            end)
            tcSwatch:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end

        -- CUI Options Language (Row 2's right slot): options-panel display language (auto-detects the client; untranslated text falls back to English).
        local langCfg
        do
            -- _noLoc: the language list itself is never translated, so a player who booted the wrong language can always read and change it.
            local langValues = {
                _noLoc = true,
                ["auto"] = { text = CludesUI.L("Automatic (Client)") },
                ["enUS"] = { text = "English" },
                ["deDE"] = { text = "Deutsch" },
                ["frFR"] = { text = "Français" },
                ["esES"] = { text = "Español (EU)" },
                ["esMX"] = { text = "Español (LatAm)" },
                ["itIT"] = { text = "Italiano" },
                ["ptBR"] = { text = "Português (BR)" },
                ["ruRU"] = { text = "Русский" },
                ["koKR"] = { text = "한국어 (Korean)" },
                ["zhCN"] = { text = "简体中文 (Simplified Chinese)" },
                ["zhTW"] = { text = "繁體中文 (Traditional Chinese)" },
            }
            local langOrder = { "auto", "enUS", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
            -- Pin each entry to the plain font its own script needs, independent
            -- of whichever display locale is currently active.
            for _, key in ipairs(langOrder) do
                langValues[key].font = LP_FontFor(key)
            end
            -- "auto"'s own text is translated, not a fixed native-script name, so
            -- its script follows the ACTIVE locale rather than its own key.
            langValues["auto"].font = LP_FontFor(CludesUI.LOCALE)

            local function LanguageReload()
                CludesUI:ShowConfirmPopup({
                    title       = "Reload Required",
                    message     = "Changing the language requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText  = "Later",
                    reload      = true,
                })
            end

            -- A non-English game client reads only its own translation file, its
            -- pair's and none other: CludesUILocales.toc tags each file with
            -- the client languages that load it (keep LANG_PAIR in step with its
            -- pairs). English clients read every file.
            local LANG_PAIR = { esMX = "esES", zhCN = "zhTW", zhTW = "zhCN" }
            local clientLocale = GetLocale()
            local function LanguageUnavailable(v)
                if v == "auto" or v == "enUS" or clientLocale == "enUS" or clientLocale == "enGB" then return false end
                if v == clientLocale or LANG_PAIR[clientLocale] == v then return false end
                return "Needs the game client set to English or to this language."
            end

            langCfg = { type="dropdown", text="CUI Options Language",
                tooltip="The display language for the CludesUI options panel. Auto follows your game client. Untranslated text falls back to English.",
                values=langValues, order=langOrder, disabledValues=LanguageUnavailable,
                getValue=function() return (CludesUIDB and CludesUIDB.displayLocale) or "auto" end,
                setValue=function(v)
                    if v == "auto" then v = nil end
                    if CludesUIDB then CludesUIDB.displayLocale = v end
                    LanguageReload()
                end }
        end

        -- Row 2: UI Scale | CUI Options Language
        _, h = W:DualRow(parent, y,
            { type="slider", text="UI Scale",
              min=0.40, max=1.00, step=0.01,
              tooltip="Sets the scale of the whole game UI. 0.53 = 0.5333 and 0.71 = 0.7111",
              tooltipOnControl=true,
              getValue=function()
                if CludesUI._uiScaleDragVal then
                    return CludesUI._uiScaleDragVal
                end
                return CludesUIDB and CludesUIDB.ppUIScale or CludesUI.PP.PixelBestSize()
              end,
              setValue=function(v)
                if not CludesUIDB then CludesUIDB = {} end
                -- Snap 0.53 to exact pixel-perfect 0.5333... (768/1440)
                if math.abs(v - 0.53) < 0.005 then v = 0.5333333333 end
                -- Snap 0.71 to exact pixel-perfect 0.7111... (768/1080)
                if math.abs(v - 0.71) < 0.005 then v = 0.7111111111 end
                CludesUI._uiScaleDragVal = v
                CludesUIDB.ppUIScaleAuto = false
                local mf = CludesUI._mainFrame
                local panelScaleBefore
                if mf then panelScaleBefore = mf:GetEffectiveScale() end
                CludesUI.PP.SetUIScale(v)
                if mf and panelScaleBefore then
                    local newEff = UIParent:GetEffectiveScale()
                    if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
                end
                if not CludesUI._uiScaleCleanup then
                    CludesUI._uiScaleCleanup = true
                    C_Timer.After(0, function()
                        if not CludesUI._sliderDragging then
                            CludesUI._uiScaleDragVal = nil
                            CludesUI:ShowConfirmPopup({
                                title = "UI Scale Changed",
                                message = "Blizzard's Edit Mode snapping may not work correctly until you reload your UI.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload    = true,
                            })
                        end
                        CludesUI._uiScaleCleanup = false
                    end)
                end
              end },
            langCfg
        );  y = y - h

        -- Row 3: CUI Buttons (merged button toggles) | Disable Sync Icons (+ cog)
        -- "CUI Buttons" merges the Pause Menu, Unlock Mode Menu and Minimap
        -- toggles into one checkbox-dropdown over the SAME backend variables: front-end grouping only, settings/defaults unchanged.
        local cuiBtnItems = {
            { key = "pause",   label = "Hide Pause Menu Button",
              tooltip = "Hides the CludesUI button from the game's Escape/pause menu." },
            { key = "unlock",  label = "Hide Layout Mode Menu Button",
              tooltip = "Hides the Layout Mode button from the game's Escape/pause menu. You can still toggle Layout Mode from the CUI options panel." },
            { key = "minimap", label = "Show Minimap Button" },
        }
        local cuiBtnRow
        cuiBtnRow, h = W:DualRow(parent, y,
            { type="dropdown", text="CUI Buttons",
              tooltip="Toggle CludesUI's optional buttons: the Escape menu buttons and the minimap button.",
              values={ ["_placeholder"]="..." }, order={ "_placeholder" },
              getValue=function() return "_placeholder" end,
              setValue=function() end },
            { type="toggle", text="Disable Sync Icons",
              tooltip="Hides the sync icons on the sidebar module list.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.hideSyncIcons or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.hideSyncIcons = v
                  if CludesUI._refreshAllSyncIcons then CludesUI._refreshAllSyncIcons() end
              end }
        );  y = y - h
        -- CUI Buttons checkbox-dropdown (left region)
        if not CludesUI._prebuilding then
            local rgn = cuiBtnRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2,
                cuiBtnItems,
                function(k)
                    if k == "pause" then
                        return CludesUIDB and CludesUIDB.hideGameMenuButton or false
                    elseif k == "unlock" then
                        return not CludesUIDB or CludesUIDB.hideUnlockMenuButton ~= false
                    elseif k == "minimap" then
                        return not (CludesUIDB and CludesUIDB.showMinimapButton == false)
                    end
                    return false
                end,
                function(k, v)
                    if not CludesUIDB then CludesUIDB = {} end
                    if k == "pause" then
                        CludesUIDB.hideGameMenuButton = v
                    elseif k == "unlock" then
                        CludesUIDB.hideUnlockMenuButton = v
                    elseif k == "minimap" then
                        CludesUIDB.showMinimapButton = v
                        if v then CludesUI.ShowMinimapButton() else CludesUI.HideMinimapButton() end
                    end
                end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        -- Cog with "Only Hide Fully Synced" toggle on Disable Sync Icons (right region)
        if not CludesUI._prebuilding then
            local rgn = cuiBtnRow._rightRegion
            CludesUI.BuildInlineCog(rgn, {
                title = "Sync Icon Options",
                rows = {
                    { type="toggle", label="Only Hide Fully Synced",
                      get=function()
                          return CludesUIDB and CludesUIDB.hideSyncIconsOnlyFull or false
                      end,
                      set=function(v)
                          if not CludesUIDB then CludesUIDB = {} end
                          CludesUIDB.hideSyncIconsOnlyFull = v
                          if CludesUI._refreshAllSyncIcons then CludesUI._refreshAllSyncIcons() end
                      end },
                },
            })
        end

        _, h = W:Spacer(parent, y, 20);  y = y - h

        _, h = W:SectionHeader(parent, "UNLOCK MODE", y);  y = y - h
        local pointAnchorRow
        pointAnchorRow, h = W:DualRow(parent, y,
            { type="toggle", text="Point Anchoring",
              tooltip="Show nine source points after clicking Anchor in Layout Mode. Choose a source point, then a target point. Turning this off hides the handles and preserves saved point anchors.",
              getValue=function() return CludesUIDB and CludesUIDB.unlockPointHandles == true end,
              setValue=function(v)
                  CludesUI.SetPointAnchorHandles(v)
                  CludesUI:RefreshPage()
              end },
            { type="dropdown", text="Overlap Cycling",
              tooltip="Scroll with the chosen modifier to cycle overlapping frames in Layout Mode.",
              values=CludesUI.UNLOCK_OVERLAP_LABELS,
              order={ "disabled", "scroll", "shiftscroll", "controlscroll", "altscroll" },
              getValue=function() return CludesUI.GetUnlockOverlapMethod() end,
              setValue=function(v)
                  CludesUIDB = CludesUIDB or {}
                  CludesUIDB.unlockOverlapMethod = v
                  if CludesUI.RefreshUnlockOverlapMethod then CludesUI.RefreshUnlockOverlapMethod() end
              end }); y = y - h
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineSwatches(pointAnchorRow._leftRegion, {
                { tooltip="Connector Lines Color", hasAlpha=true,
                  getValue=function() return CludesUI.GetPointAnchorColor("line") end,
                  setValue=function(r,g,b,a) CludesUI.SetPointAnchorColor("line",r,g,b,a) end },
                { tooltip="Border Color", hasAlpha=true,
                  getValue=function() return CludesUI.GetPointAnchorColor("border") end,
                  setValue=function(r,g,b,a) CludesUI.SetPointAnchorColor("border",r,g,b,a) end },
                { tooltip="Point Color", hasAlpha=true,
                  getValue=function() return CludesUI.GetPointAnchorColor("point") end,
                  setValue=function(r,g,b,a) CludesUI.SetPointAnchorColor("point",r,g,b,a) end },
            }, {
                disabled=function() return not (CludesUIDB and CludesUIDB.unlockPointHandles == true) end,
                disabledTooltip="Point Anchoring",
            })
        end
        _, h = W:Spacer(parent, y, 20); y = y - h

        _, h = W:SectionHeader(parent, "COMBAT", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type="slider", text="Max Camera Distance",
              min=1, max=2.6, step=0.1,
              getValue=function() return GetCVarNum("cameraDistanceMaxZoomFactor") end,
              setValue=function(v)
                v = floor(v * 10 + 0.5) / 10
                SetCVarSafe("cameraDistanceMaxZoomFactor", v)
              end },
            { type="toggle", text="Increase Game Image Quality",
              tooltip="Enables sharpening to improve image clarity. Especially noticeable at lower render scales.",
              getValue=function() return GetCVarBool("ResampleAlwaysSharpen") end,
              setValue=function(v)
                SetGfxCVar("ResampleAlwaysSharpen", v and "1" or "0")
              end });  y = y - h

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Cast Actions on Key Down",
              tooltip="Keybinds respond on key down instead of key up. This helps make your abilities feel more responsive.",
              getValue=function() return GetCVarBool("ActionButtonUseKeyDown") end,
              setValue=function(v)
                SetCVarSafe("ActionButtonUseKeyDown", v and "1" or "0")
                if _G._EAB_ApplyKeyDown then _G._EAB_ApplyKeyDown() end
              end },
            { type="slider", text="Lag Tolerance",
              tooltip="This is the Spell Queue Window, it helps with making sure you can't queue up too many spells at once which makes the game feel laggy. Recommended settings are generally a minimum of 200 + your local ping. If you are unsure of exactly what this setting does, leave it at 400.",
              min=0, max=400, step=1,
              getValue=function() return GetCVarNum("SpellQueueWindow") end,
              setValue=function(v)
                SetCVarSafe("SpellQueueWindow", v)
              end });  y = y - h

        local FCT_FONT_DIR = "Interface\\AddOns\\CludesUI\\media\\fonts\\"
        local fctFontValues = {
            ["default"]                                = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" },
            [FCT_FONT_DIR .. "Expressway.TTF"]         = { text = "Expressway",            font = FCT_FONT_DIR .. "Expressway.TTF" },
            [FCT_FONT_DIR .. "Avant Garde Naowh.ttf"]        = { text = "Avant Garde",   font = FCT_FONT_DIR .. "Avant Garde Naowh.ttf" },
            [FCT_FONT_DIR .. "Arial Bold.TTF"]         = { text = "Arial Bold",            font = FCT_FONT_DIR .. "Arial Bold.TTF" },
            [FCT_FONT_DIR .. "Poppins.ttf"]            = { text = "Poppins",               font = FCT_FONT_DIR .. "Poppins.ttf" },
            [FCT_FONT_DIR .. "FiraSans Medium.ttf"]    = { text = "Fira Sans Medium",      font = FCT_FONT_DIR .. "FiraSans Medium.ttf" },
            [FCT_FONT_DIR .. "Expressway CAPS.ttf"]    = { text = "Expressway CAPS",       font = FCT_FONT_DIR .. "Expressway CAPS.ttf" },
            [FCT_FONT_DIR .. "Arial Narrow.ttf"]       = { text = "Arial Narrow",          font = FCT_FONT_DIR .. "Arial Narrow.ttf" },
            [FCT_FONT_DIR .. "Changa.ttf"]             = { text = "Changa",                font = FCT_FONT_DIR .. "Changa.ttf" },
            [FCT_FONT_DIR .. "Cinzel Decorative.ttf"]  = { text = "Cinzel Decorative",     font = FCT_FONT_DIR .. "Cinzel Decorative.ttf" },
            [FCT_FONT_DIR .. "Exo.otf"]                = { text = "Exo",                   font = FCT_FONT_DIR .. "Exo.otf" },
            [FCT_FONT_DIR .. "FiraSans Bold.ttf"]      = { text = "Fira Sans Bold",        font = FCT_FONT_DIR .. "FiraSans Bold.ttf" },
            [FCT_FONT_DIR .. "FiraSans Light.ttf"]     = { text = "Fira Sans Light",       font = FCT_FONT_DIR .. "FiraSans Light.ttf" },
            [FCT_FONT_DIR .. "Future X Black.otf"]     = { text = "Future X Black",        font = FCT_FONT_DIR .. "Future X Black.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow Ultra.otf"] = { text = "Gotham Narrow Ultra",  font = FCT_FONT_DIR .. "Gotham Narrow Ultra.otf" },
            [FCT_FONT_DIR .. "Gotham Narrow.otf"]      = { text = "Gotham Narrow",         font = FCT_FONT_DIR .. "Gotham Narrow.otf" },
            [FCT_FONT_DIR .. "Russo One.ttf"]          = { text = "Russo One",             font = FCT_FONT_DIR .. "Russo One.ttf" },
            [FCT_FONT_DIR .. "Ubuntu.ttf"]             = { text = "Ubuntu",                font = FCT_FONT_DIR .. "Ubuntu.ttf" },
            [FCT_FONT_DIR .. "Homespun.ttf"]           = { text = "Homespun",              font = FCT_FONT_DIR .. "Homespun.ttf" },
            [FCT_FONT_DIR .. "HWT Artz.ttf"]           = { text = "HWT Artz",              font = FCT_FONT_DIR .. "HWT Artz.ttf" },
            ["Fonts\\FRIZQT__.TTF"]                    = { text = "Friz Quadrata",         font = "Fonts\\FRIZQT__.TTF" },
            ["Fonts\\ARIALN.TTF"]                      = { text = "Arial",                 font = "Fonts\\ARIALN.TTF" },
            ["Fonts\\MORPHEUS.TTF"]                    = { text = "Morpheus",              font = "Fonts\\MORPHEUS.TTF" },
            ["Fonts\\skurri.ttf"]                      = { text = "Skurri",                font = "Fonts\\skurri.ttf" },
        }
        local fctFontOrder = {
            "default",
            FCT_FONT_DIR .. "Expressway.TTF",
            FCT_FONT_DIR .. "Avant Garde Naowh.ttf",
            FCT_FONT_DIR .. "Arial Bold.TTF",
            FCT_FONT_DIR .. "Poppins.ttf",
            FCT_FONT_DIR .. "FiraSans Medium.ttf",
            FCT_FONT_DIR .. "Expressway CAPS.ttf",
            "---",
            FCT_FONT_DIR .. "Arial Narrow.ttf",
            FCT_FONT_DIR .. "Changa.ttf",
            FCT_FONT_DIR .. "Cinzel Decorative.ttf",
            FCT_FONT_DIR .. "Exo.otf",
            FCT_FONT_DIR .. "FiraSans Bold.ttf",
            FCT_FONT_DIR .. "FiraSans Light.ttf",
            FCT_FONT_DIR .. "Future X Black.otf",
            FCT_FONT_DIR .. "Gotham Narrow Ultra.otf",
            FCT_FONT_DIR .. "Gotham Narrow.otf",
            FCT_FONT_DIR .. "Russo One.ttf",
            FCT_FONT_DIR .. "Ubuntu.ttf",
            FCT_FONT_DIR .. "Homespun.ttf",
            FCT_FONT_DIR .. "HWT Artz.ttf",
            "Fonts\\FRIZQT__.TTF",
            "Fonts\\ARIALN.TTF",
            "Fonts\\MORPHEUS.TTF",
            "Fonts\\skurri.ttf",
        }
        for i = #fctFontOrder, 2, -1 do
            local k = fctFontOrder[i]
            if k ~= "---" and not CludesUI.CombatTextFontCoversLocale(k) then
                table.remove(fctFontOrder, i)
            end
        end
        if fctFontOrder[#fctFontOrder] == "---" then fctFontOrder[#fctFontOrder] = nil end
        CludesUI.AppendSharedMediaFonts(fctFontValues, fctFontOrder)

        -- Combat Text (checkbox dropdown + size cog) | Combat Text Font. The
        -- dropdown is a view over the floating combat text CVars the client
        -- has; each extra only applies while the item it refines is on (the
        -- damage extras under Damage, Absorb Shields under Healing, Others'
        -- Target Effects under Target Effects).
        local function DmgOff() return not GetCVarBool("floatingCombatTextCombatDamage_v2") end
        local function HealOff() return not GetCVarBool("floatingCombatTextCombatHealing_v2") end
        local function FxOff() return not GetCVarBool("floatingCombatTextSpellMechanics_v2") end
        local dmgTip = CludesUI.DisabledTooltip("Damage")
        local healTip = CludesUI.DisabledTooltip("Healing")
        local fxTip = CludesUI.DisabledTooltip("Target Effects")
        local COMBAT_TEXT = {}
        for _, item in ipairs({
            { key="floatingCombatTextCombatDamage_v2",            label="Damage" },
            { key="floatingCombatTextCombatLogPeriodicSpells_v2", label="Periodic Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextPetMeleeDamage_v2",          label="Pet Melee Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextPetSpellDamage_v2",          label="Pet Spell Damage",
              lockedFn=DmgOff, lockedTooltip=dmgTip, excludeFromSummaryFn=DmgOff },
            { key="floatingCombatTextCombatHealing_v2",           label="Healing" },
            { key="floatingCombatTextCombatHealingAbsorbTarget_v2", label="Absorb Shields",
              lockedFn=HealOff, lockedTooltip=healTip, excludeFromSummaryFn=HealOff },
            { key="floatingCombatTextSpellMechanics_v2",          label="Target Effects" },
            { key="floatingCombatTextSpellMechanicsOther_v2",     label="Others' Target Effects",
              lockedFn=FxOff, lockedTooltip=fxTip, excludeFromSummaryFn=FxOff },
        }) do
            if C_CVar.GetCVarInfo(item.key) then COMBAT_TEXT[#COMBAT_TEXT + 1] = item end
        end
        local combatTextRow
        combatTextRow, h = W:DualRow(parent, y,
            { type="label", text="Combat Text" },
            { type="dropdown", text="Combat Text Font",
              tooltip="WARNING: This feature requires you to re-log or restart WoW to take effect.",
              tooltipOpts={ color={1, 0.3, 0.3} },
              values = fctFontValues, order = fctFontOrder,
              getValue=function()
                local v = CludesUIDB and CludesUIDB.fctFont
                return v and CludesUI.CombatTextFontCoversLocale(v) and v or "default"
              end,
              setValue=function(v)
                if not CludesUIDB then CludesUIDB = {} end
                if v == "default" then
                    CludesUIDB.fctFont = nil
                    CludesUIDB.fctFontPath = nil
                    CludesUIDB.fctFontPathFor = nil
                else
                    CludesUIDB.fctFont = v
                    -- smf: keys cache their resolved path for the next login's
                    -- early window; see ApplyCombatTextFont in Startup.
                    local e = v:match("^smf:") and fctFontValues[v]
                    CludesUIDB.fctFontPath = e and e.font
                    CludesUIDB.fctFontPathFor = e and v
                end
                CludesUI:ShowConfirmPopup({
                    title   = "Logout Required",
                    message = "Combat text font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                    confirmText = "Okay",
                    cancelText  = "Later",
                })
              end });  y = y - h
        if not CludesUI._prebuilding then
            local rgn = combatTextRow._leftRegion
            local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, COMBAT_TEXT,
                function(key) return GetCVarBool(key) end,
                function(key, v) SetCVarSafe(key, v and "1" or "0") end)
            PP.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
            CludesUI.BuildInlineCog(rgn, {
                title = "Combat Text Size",
                rows = {
                    { type="slider", label="Size", min=0.5, max=2.5, step=0.1,
                      get=function() return GetCVarNum("WorldTextScale_v2") end,
                      set=function(v)
                          v = floor(v * 10 + 0.5) / 10
                          SetCVarSafe("WorldTextScale_v2", v)
                      end },
                },
            })
        end

        -- Swiftmend Brightness Fix (Druid only): the right slot beside Round
        -- Timer Seconds Down, blank for every other class.
        local swiftmendCfg = CludesUI.BlankRowCfg()
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            swiftmendCfg = { type="toggle", text="Prevent Swiftmend Icon Dim",
                tooltip="Prevents Blizzard from dimming Swiftmend on action bars and CDM based on Efflorescence state.",
                getValue=function()
                    return not CludesUIDB or CludesUIDB.brightenSwiftmend ~= false
                end,
                setValue=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.brightenSwiftmend = v
                    if v then
                        if _G._EAB_ScanSwiftmend then _G._EAB_ScanSwiftmend() end
                        if _G._ECDM_ScanSwiftmend then _G._ECDM_ScanSwiftmend() end
                    end
                end }
        end

        -- Row 4: Round Timer Seconds Down | Prevent Swiftmend Icon Dim. Every
        -- timer keeps the formatter it was given (AuraKit reads the setting
        -- once), so a change waits for a reload.
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Round Timer Seconds Down",
              tooltip="Timer seconds round down like Blizzard's buff frame, so a timer reads 0 in its last second. Off, it reads 1 until it ends.",
              getValue=function()
                  return CludesUIDB and CludesUIDB.timerSecondsDown == true or false
              end,
              setValue=function(v)
                  if not CludesUIDB then CludesUIDB = {} end
                  CludesUIDB.timerSecondsDown = v or nil
                  CludesUI:ShowConfirmPopup({
                      title       = "Reload Required",
                      message     = "Changing how timers round requires a UI reload.",
                      confirmText = "Reload Now",
                      cancelText  = "Later",
                      reload      = true,
                  })
              end },
            swiftmendCfg
        ); y = y - h

        _, h = W:Spacer(parent, y, 20);  y = y - h

        -------------------------------------------------------------------
        --  DEVELOPER -- both toggles are duplicated in Quality of Life
        --  (Suppress Lua Errors) and Blizzard Skins+ (Spell ID on Tooltip):
        --  hidden here when BOTH modules are loaded, shown if either is missing so the settings stay reachable.
        -------------------------------------------------------------------
        local _devDupesAvailable = C_AddOns and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("CludesUIQoL")
            and C_AddOns.IsAddOnLoaded("CludesUIBlizzardSkin")
        if not _devDupesAvailable then
            _, h = W:SectionHeader(parent, "DEVELOPER", y);  y = y - h

            _, h = W:DualRow(parent, y,
                { type="toggle", text="Suppress Lua Errors",
                  getValue=function()
                    return not (CludesUIDB and CludesUIDB.suppressErrors == false)
                  end,
                  setValue=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.suppressErrors = v
                    SetCVarSafe("scriptErrors", v and "0" or "1")
                  end },
                { type="toggle", text="Spell ID on Tooltip",
                  getValue=function()
                    return CludesUI.SpellIDOn()
                  end,
                  setValue=function(v)
                    if not CludesUIDB then CludesUIDB = {} end
                    CludesUIDB.showSpellID = v
                    -- Engine-side combat aura-ID CVar rides this setting.
                    if CludesUI.SyncAuraSpellIDCVar then CludesUI.SyncAuraSpellIDCVar() end
                  end });  y = y - h

            _, h = W:Spacer(parent, y, 20);  y = y - h
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Re-read live CVars on panel open: widgets call their getter on each build, so a rebuild picks up external changes (addons, /console).
    ---------------------------------------------------------------------------
    CludesUI:RegisterOnShow(function()
        if CludesUI:GetActiveModule() == GLOBAL_KEY then
            CludesUI:RefreshPage()
        end
    end)

    ---------------------------------------------------------------------------
    --  Enabled Addons page
    ---------------------------------------------------------------------------

    -- The profiles root (CUI_Profiles_Options.lua) sits on the scroll frame
    -- itself, beside the pages: when another page shows it is hidden and
    -- leaves the scroll frame, and nil marks it as needing a build before it
    -- shows again. The frame stays its builder's (options page pool): the
    -- next build parents it to the scroll frame again and dresses it again.
    local function CleanupProfilesRoot()
        local root = CludesUI._profilesRoot
        if root then
            root:Hide()
            root:SetParent(nil)
            CludesUI._profilesRoot = nil
        end
    end

    -- A profiles root build outside a page pass (a cached page shown again):
    -- the refreshers its previous build registered leave the live list first.
    local function RenderProfilesRoot()
        CludesUI._BeginRootRender("profilesRoot")
        _G._CUI_BuildProfilesPage(PAGE_PROFILES, nil, -6)
        CludesUI._EndRootRender("profilesRoot")
    end

    -- Profiles and Patch Notes are their own sidebar pages (registered below), so Global Settings owns General + Style + Fonts + Textures + Glows + Colors + Numbers (Style second, beside General), plus Gamepad while a module it configures is loaded.
    local globalPages = { PAGE_GENERAL, PAGE_STYLE, PAGE_FONTS, PAGE_TEXTURES, PAGE_GLOWS, PAGE_COLORS, PAGE_NUMBERS }
    if CludesUI.ModuleNS("CludesUIActionBars") or CludesUI.ModuleNS("CludesUIUnitFrames")
       or CludesUI.ModuleNS("CludesUIResourceBars") then
        globalPages[#globalPages + 1] = PAGE_GAMEPAD
    end

    CludesUI:RegisterModule(GLOBAL_KEY, {
        title       = "Global Settings",
        description = "General options for all CludesUI addons.",
        pages       = globalPages,
        buildPage   = function(pageName, parent, yOffset)
            -- CleanupProfilesRoot hides/nils the LIVE _profilesRoot, not anything scoped to this pageName. An off-screen search pre-build
            -- cycles pageName through PAGE_GENERAL/PAGE_FONTS/PAGE_TEXTURES/PAGE_COLORS regardless of what the player has open, so it would yank their real Profiles
            -- page away. This module's config.pages never includes PAGE_PROFILES anyway.
            if CludesUI._prebuilding then
                if pageName == PAGE_GENERAL then
                    return BuildGeneralPage(pageName, parent, yOffset)
                elseif pageName == PAGE_FONTS then
                    return _G._CUI_BuildFontsPage and _G._CUI_BuildFontsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_TEXTURES then
                    return _G._CUI_BuildTexturesPage and _G._CUI_BuildTexturesPage(pageName, parent, yOffset)
                elseif pageName == PAGE_GLOWS then
                    return _G._CUI_BuildGlowsPage and _G._CUI_BuildGlowsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_GAMEPAD then
                    return _G._CUI_BuildGamepadPage and _G._CUI_BuildGamepadPage(pageName, parent, yOffset)
                elseif pageName == PAGE_NUMBERS then
                    return _G._CUI_BuildNumberFormatPage and _G._CUI_BuildNumberFormatPage(pageName, parent, yOffset)
                elseif pageName == PAGE_STYLE then
                    return _G._CUI_BuildStylePage and _G._CUI_BuildStylePage(pageName, parent, yOffset)
                elseif pageName == PAGE_COLORS then
                    return _G._CUI_BuildColorsPage(pageName, parent, yOffset)
                elseif pageName == PAGE_WHATSNEW then
                    return CludesUI._BuildWhatsNewPage(pageName, parent, yOffset)
                end
                return
            end
            -- Clean up profiles root when switching to a non-Profiles tab
            if pageName ~= PAGE_PROFILES then
                CleanupProfilesRoot()
            end
            if pageName == PAGE_GENERAL then
                return BuildGeneralPage(pageName, parent, yOffset)
            elseif pageName == PAGE_FONTS then
                return _G._CUI_BuildFontsPage and _G._CUI_BuildFontsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_TEXTURES then
                return _G._CUI_BuildTexturesPage and _G._CUI_BuildTexturesPage(pageName, parent, yOffset)
            elseif pageName == PAGE_GLOWS then
                return _G._CUI_BuildGlowsPage and _G._CUI_BuildGlowsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_GAMEPAD then
                return _G._CUI_BuildGamepadPage and _G._CUI_BuildGamepadPage(pageName, parent, yOffset)
            elseif pageName == PAGE_NUMBERS then
                return _G._CUI_BuildNumberFormatPage and _G._CUI_BuildNumberFormatPage(pageName, parent, yOffset)
            elseif pageName == PAGE_STYLE then
                return _G._CUI_BuildStylePage and _G._CUI_BuildStylePage(pageName, parent, yOffset)
            elseif pageName == PAGE_COLORS then
                return _G._CUI_BuildColorsPage(pageName, parent, yOffset)
            elseif pageName == PAGE_PROFILES then
                return _G._CUI_BuildProfilesPage(pageName, parent, yOffset)
            elseif pageName == PAGE_WHATSNEW then
                return CludesUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end
        end,
        -- Number Format: the value type picker and preview header, and one search
        -- pre-build per value type (each type's Precision row exists only under it).
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_NUMBERS and _G._CUI_NumberFormatHeaderBuilder then
                return _G._CUI_NumberFormatHeaderBuilder()
            end
            return nil
        end,
        getPrebuildVariants = function(pageName)
            if pageName == PAGE_NUMBERS and _G._CUI_NumberFormatVariants then
                return _G._CUI_NumberFormatVariants()
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            -- The cached header's preview may predate a profile switch.
            if pageName == PAGE_NUMBERS and _G._CUI_NumberFormatRefreshHeader then
                _G._CUI_NumberFormatRefreshHeader()
            end
            if pageName == PAGE_GLOWS then
                -- Glow sites bind per-bar and per-spec tables at build time (CDM bars,
                -- tracking bars); a spec swap or bar change behind a cached page would
                -- leave rows writing into stale tables. Rebuild on every return.
                C_Timer.After(0, function()
                    if CludesUI:GetActiveModule() == GLOBAL_KEY
                       and CludesUI:GetActivePage() == PAGE_GLOWS then
                        CludesUI:RefreshPage(true)
                    end
                end)
            end
            if pageName ~= PAGE_PROFILES then
                CleanupProfilesRoot()
            elseif pageName == PAGE_PROFILES and not CludesUI._profilesRoot then
                C_Timer.After(0, function()
                    if CludesUI:GetActiveModule() == GLOBAL_KEY
                       and CludesUI:GetActivePage() == pageName then
                        RenderProfilesRoot()
                    end
                end)
            end
        end,
        -- Reset CUI Module Settings: these settings sit on the account.
        resetScope  = "account",
        onReset     = function()
            -- Reset CVars to CUI preferred defaults (ignoring current state)
            for _, entry in ipairs(CUI_DEFAULTS) do
                SetCVarSafe(entry[1], entry[2])
            end
            -- Reset style/theme settings (accent color, custom theme, class-colored)
            CludesUI.ResetTheme()
            -- Reset all custom class, power, and resource colors to defaults
            if CludesUIDB then
                CludesUIDB.customColors = nil
            end
            -- Reset fonts to defaults
            if CludesUIDB then
                CludesUIDB.fonts = nil
            end
            CludesUI.InvalidateFontCache()
            CludesUI.ApplyColorsToOUF()
            -- Reset the active profile's Number Format to defaults
            CludesUI.ResetNumberFormat()
            -- Reset panel scale to 100%
            CludesUI:SetPanelScale(1.0)
            -- Reset right-click targeting to default (disabled = off)
            if CludesUIDB then
                CludesUIDB.disableRightClickTarget = false
                CludesUIDB.disableRightClickTargetAllyCombat = false
                -- FPS + Secondary Stats are per-profile now; turn them off for the active profile (QoLExtrasSet) so the visible widgets actually clear.
                if CludesUI.QoLExtrasSet then
                    CludesUI.QoLExtrasSet("showFPS", false)
                    CludesUI.QoLExtrasSet("showSecondaryStats", false)
                end
                CludesUIDB.guildChatPrivacy = false
                CludesUIDB.repairWarning = nil
                -- Reset UI scale so next reload re-snapshots from Blizzard default
                CludesUIDB.ppUIScale = nil
                CludesUIDB.ppUIScaleAuto = nil
                -- Developer settings defaults (Spell ID on Tooltip: unset = on)
                CludesUIDB.showSpellID = nil
                if CludesUI.SyncAuraSpellIDCVar then CludesUI.SyncAuraSpellIDCVar() end
                CludesUIDB.suppressErrors = true
                CludesUIDB.timerSecondsDown = nil
                -- Crosshair: the root is the inherited global default, reset here (per-profile overrides clear with the profile's own reset).
                -- Root off = profiles without an override inherit "None".
                CludesUIDB.crosshairSize = "None"
                if CludesUI._applyCrosshair then CludesUI._applyCrosshair() end
                -- Reset unlock mode layout data
                CludesUIDB.unlockAnchors = nil
                CludesUIDB.unlockWidthMatch = nil
                CludesUIDB.unlockHeightMatch = nil
                CludesUIDB.unlockWidthMatchExtra = nil
                CludesUIDB.unlockHeightMatchExtra = nil
                CludesUIDB.unlockPointHandles = nil
                CludesUIDB.unlockPointColors = nil
                -- QoL Features are NOT reset here; they have their own module reset
            end
            if CludesUI._applyRightClickTarget then
                CludesUI._applyRightClickTarget()
            end
            CludesUI._applyHideBlizzardPartyFrame()
            -- One call for both: the FPS readout may be drawn by the Secondary
            -- Stats block, so the two owners have to re-evaluate together.
            if CludesUI._applyFPSDisplay then
                CludesUI._applyFPSDisplay()
            elseif CludesUI._applySecondaryStats then
                CludesUI._applySecondaryStats()
            end
            if CludesUI._applyCrosshair then
                CludesUI._applyCrosshair()
            end
            if CludesUI._applyGuildChatPrivacy then
                CludesUI._applyGuildChatPrivacy()
            end
            -- Apply suppress errors default (on)
            SetCVarSafe("scriptErrors", "0")
            CludesUI:SelectPage(PAGE_GENERAL)
        end,
    })

    -- Profiles & Presets: its own sidebar module, reusing the profiles page builder; the profiles-root lifecycle rides the shared
    -- CleanupProfilesRoot hooks below (keyed to PROFILES_KEY). Second tab: the Overrides management list (built by CUI_SpecOverrides_ListPage.lua).
    --
    -- ONE tab, TWO pages: "Spec Overrides" and "Conditional Overrides" stay completely separate page builders with their own stores, prune
    -- passes and row logic. The tab strip shows one "Overrides" entry and a centered segmented toggle picks the builder (the same control
    -- Raid Frames uses for Simple Setup / Custom Buff Display). The mode is runtime-only, defaulting to the spec list.
    local PAGE_OVERRIDES = "Overrides"

    -- Builds the centered mode toggle, returning the vertical space used. Plain local closure on purpose: no widget row, no capture config, no saved state.
    -- The shared segmented control draws it, so it looks like every other segment switch.
    local function BuildOverridesModeToggle(parent, y)
        -- Wider than the Raid Frames pair (162): "Conditional Overrides" is a longer label than "Custom Buff Display" and must not clip.
        local BTN_W, BTN_H = 180, 31
        local seg = CludesUI.BuildSegmentedControl({
            parent     = parent,
            keys       = { "spec", "cond" },
            labels     = { spec = "Spec Overrides", cond = "Conditional Overrides" },
            width      = BTN_W * 2,
            square     = true,
            height     = BTN_H,
            getChecked = function(key) return (CludesUI._overridesTabMode or "spec") == key end,
            onToggle   = function(key)
                if (CludesUI._overridesTabMode or "spec") == key then return end
                CludesUI._overridesTabMode = key
                -- Forced: the two builders render entirely different rows.
                CludesUI:RefreshPage(true)
            end,
        })
        seg:SetPoint("TOP", parent, "TOP", 0, y - 14)
        seg:SetFrameLevel(parent:GetFrameLevel() + 1)
        -- 14 above + 15 below the buttons.
        return BTN_H + 29
    end

    -- FULL EXPORT tab: a warning and one button, with its own exporter (CludesUI.ExportFullAccountData) sharing NO code path with the
    -- Profiles tab's export flow, so nothing here changes a normal profile string.
    local PAGE_FULLEXPORT = "Full Export"

    local function BuildFullExportPage(parent, yOffset)
        local PAD = CludesUI.CONTENT_PAD or 40
        local y = yOffset - 10
        local width = parent:GetWidth() - PAD * 2

        -- Warning card (red-bordered, full width).
        local warn = CreateFrame("Frame", nil, parent)
        warn:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y)
        warn:SetWidth(width)
        warn:SetFrameLevel(parent:GetFrameLevel() + 2)
        local wbg = CludesUI.SolidTex(warn, "BACKGROUND", 0.10, 0.04, 0.04, 0.55)
        wbg:SetAllPoints()
        CludesUI.MakeRoundedBorder(warn, 0.8, 0.2, 0.2, 0.55, wbg)
        local wtext = CludesUI.MakeFont(warn, 13, nil, 1, 0.55, 0.55, 1)
        wtext:SetPoint("TOPLEFT", warn, "TOPLEFT", 16, -14)
        wtext:SetWidth(width - 32)
        wtext:SetJustifyH("LEFT")
        wtext:SetSpacing(3)
        wtext:SetText(CludesUI.L("This export includes cross profile settings that will overwrite the importing user's settings including Utilities, Hovercast and more that should typically not be shared with standard profiles. THIS IS NOT RECOMMENDED for public sharing of profiles."))
        warn:SetHeight((wtext:GetStringHeight() or 40) + 28)
        y = y - warn:GetHeight() - 40

        -- Centered export button.
        local BTN_W, BTN_H = 300, 38
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(BTN_W, BTN_H)
        btn:SetPoint("TOP", parent, "TOP", 0, y)
        btn:SetFrameLevel(parent:GetFrameLevel() + 5)
        local DARK_BG = CludesUI.DARK_BG
        local bbg = CludesUI.SolidTex(btn, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bbg:SetAllPoints()
        local EG = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local bbrd = CludesUI.MakeRoundedBorder(btn, EG.r, EG.g, EG.b, 0.5, bbg)
        local blbl = CludesUI.MakeFont(btn, 13, nil, EG.r, EG.g, EG.b, 1)
        blbl:SetAlpha(0.8)
        blbl:SetPoint("CENTER")
        blbl:SetText(CludesUI.L("Export All Data with Profile"))
        btn:SetScript("OnEnter", function()
            blbl:SetAlpha(1)
            if bbrd and bbrd.SetColor then bbrd:SetColor(EG.r, EG.g, EG.b, 0.9) end
        end)
        btn:SetScript("OnLeave", function()
            blbl:SetAlpha(0.8)
            if bbrd and bbrd.SetColor then bbrd:SetColor(EG.r, EG.g, EG.b, 0.5) end
        end)
        btn:SetScript("OnClick", function()
            local str = CludesUI.ExportFullAccountData()
            if str then
                CludesUI:ShowExportPopup(str)
            else
                CludesUI:ShowInfoPopup({
                    title = CludesUI.L("Export Failed"),
                    content = CludesUI.L("Could not build the export string."),
                })
            end
        end)
        y = y - BTN_H - 20

        return -y + 40
    end

    -- Runs the toggle, then the selected mode's builder. Builders return total content height measured from the ORIGINAL page top (they
    -- accumulate from the startY handed in), so the toggle's space is already included.
    local function BuildOverridesPage(parent, yOffset)
        local y = yOffset - BuildOverridesModeToggle(parent, yOffset)
        if (CludesUI._overridesTabMode or "spec") == "cond" then
            if CludesUI.Conditions_BuildListPage then
                return CludesUI.Conditions_BuildListPage(parent, y)
            end
        elseif CludesUI.SpecOverrides_BuildListPage then
            return CludesUI.SpecOverrides_BuildListPage(parent, y)
        end
        return 200
    end
    CludesUI:RegisterModule(PROFILES_KEY, {
        title       = "Profiles",
        description = "Import, export, and switch CludesUI profiles and presets.",
        pages       = { PAGE_PROFILES, PAGE_OVERRIDES, PAGE_FULLEXPORT },
        buildPage   = function(pageName, parent, yOffset)
            -- _G._CUI_BuildProfilesPage bypasses `parent` and builds onto the live shared _scrollFrame, and first checks the active profile against the
            -- current spec -- it can call SwitchProfile/RefreshAllAddons and pop a "Reload Required" confirmation. None of that is safe from a
            -- hidden indexing pass, so skip PAGE_PROFILES; it indexes on the player's first visit.
            if CludesUI._prebuilding then
                if pageName == PAGE_OVERRIDES then
                    -- Index the spec list only: the conditional builder is not part of the hidden pre-build pass, and the toggle is chrome.
                    if CludesUI.SpecOverrides_BuildListPage then
                        return CludesUI.SpecOverrides_BuildListPage(parent, yOffset)
                    end
                    return 200
                end
                return
            end
            if pageName == PAGE_OVERRIDES then
                CleanupProfilesRoot()
                return BuildOverridesPage(parent, yOffset)
            end
            if pageName == PAGE_FULLEXPORT then
                CleanupProfilesRoot()
                return BuildFullExportPage(parent, yOffset)
            end
            return _G._CUI_BuildProfilesPage(pageName, parent, yOffset)
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_FULLEXPORT then
                -- The Profiles page builds onto the SHARED profiles root, which outlives page switches, so a cached Full Export page would show
                -- profiles content layered over it. The page itself is static, so cleanup is enough -- no rebuild.
                CleanupProfilesRoot()
            elseif pageName == PAGE_OVERRIDES then
                CleanupProfilesRoot()
                -- The override list changes while the page is cached; rebuild.
                C_Timer.After(0, function()
                    if CludesUI:GetActiveModule() == PROFILES_KEY
                       and CludesUI:GetActivePage() == pageName then
                        CludesUI:RefreshPage(true)
                    end
                end)
            elseif not CludesUI._profilesRoot then
                C_Timer.After(0, function()
                    if CludesUI:GetActiveModule() == PROFILES_KEY
                       and CludesUI:GetActivePage() == pageName then
                        RenderProfilesRoot()
                    end
                end)
            else
                -- Shared root is alive but the Presets tab may have left its subpage showing; the Profiles tab lands on main. An active API
                -- import session wins -- re-enter instead of hiding its page.
                local s = CludesUI._apiImportSession
                if s and s.state ~= "done" then
                    if CludesUI._ProfilesConsumeApiImport then
                        CludesUI._ProfilesConsumeApiImport()
                    end
                elseif CludesUI._ProfilesResetToMain then
                    CludesUI._ProfilesResetToMain()
                end
            end
        end,
    })

    -- Patch Notes: its own sidebar module. Suite-only, never registered in
    -- standalone builds.
    if not IS_STANDALONE then
        CludesUI:RegisterModule(PATCHNOTES_KEY, {
            title       = "Patch Notes",
            description = CludesUI.L("What's new in CludesUI."),
            pages       = { PAGE_WHATSNEW },
            buildPage   = function(pageName, parent, yOffset)
                return CludesUI._BuildWhatsNewPage(pageName, parent, yOffset)
            end,
        })

        -- Window Scale: the header's panel scale slider, left of the collapse box and
        -- centred on the close X. 5% steps from 75% to 200%: a drag shows its value
        -- live and applies on release, the mouse wheel steps one notch per tick, and
        -- every change glides with the track pinned (SetPanelScale), so the slider
        -- never slides out from under the cursor. Built on the first open.
        local scaleCtl, ScaleCtlRefresh
        local function BuildScaleControl()
            local ca = CludesUI._clickArea
            if scaleCtl or not ca then return end
            local MIN = CludesUI.PANEL_SCALE_MIN * 100
            local MAX = CludesUI.PANEL_SCALE_MAX * 100
            local STEP, TRACK_W, PCT_W = 5, 110, 40
            local ctl = CreateFrame("Frame", nil, ca)
            scaleCtl = ctl
            ctl:SetFrameLevel(ca:GetFrameLevel() + 20)
            ctl:SetHeight(24)
            ctl:SetPoint("RIGHT", ca, "TOPRIGHT", -110, -31)

            local pctFs = CludesUI.MakeFont(ctl, 13, nil, 1, 1, 1, 0.9)
            pctFs:SetWidth(PCT_W)
            pctFs:SetJustifyH("RIGHT")
            pctFs:SetPoint("RIGHT", ctl, "RIGHT", 0, 0)
            local function ShowPct(v)
                pctFs:SetText(string.format("%d%%", math.floor(v + 0.5)))
            end
            local function SavedPct()
                return ((CludesUIDB and CludesUIDB.panelScale) or 1) * 100
            end

            local pending   -- the dragged value, shown until the release applies it
            local track, valBox, refresh
            local function Apply(v)
                ShowPct(v)
                if math.abs(v - SavedPct()) < 0.01 then return end
                CludesUI:SetPanelScale(v / 100, track)
            end
            -- Panel chrome, not page content: the refresh the slider registers
            -- leaves the shown page's refresh list again (ScaleCtlRefresh and the
            -- accent callback below repaint it), so the page's first build
            -- registers what its later builds do.
            local pageRefresh = CludesUI._widgetRefreshList
            local pageRefreshN = #pageRefresh
            track, valBox, refresh = CludesUI.BuildSliderCore(ctl, TRACK_W, 4, 12, PCT_W, 20, 12, 0.5,
                MIN, MAX, STEP,
                function() return pending or SavedPct() end,
                function(v)
                    if CludesUI._sliderDragging then
                        pending = v
                        ShowPct(v)
                        return
                    end
                    pending = nil
                    Apply(v)
                end, true)
            for i = #pageRefresh, pageRefreshN + 1, -1 do pageRefresh[i] = nil end
            valBox:Hide()   -- the plain readout replaces the input box
            track:SetPoint("RIGHT", pctFs, "LEFT", -10, 0)

            local label = CludesUI.MakeFont(ctl, 13, nil, 1, 1, 1, 0.6)
            label:SetText(CludesUI.L("Window Scale"))
            label:SetPoint("RIGHT", track, "LEFT", -16, 0)
            -- The whole control takes the wheel; clicks off the track still reach the
            -- click area below (the window drag).
            ctl:SetWidth(PCT_W + 10 + TRACK_W + 16 + label:GetStringWidth())
            ctl:EnableMouseWheel(true)
            ctl:SetScript("OnMouseWheel", function(_, delta)
                if CludesUI._sliderDragging then return end
                if CludesUI:StepPanelScale(delta, track) then
                    ShowPct(SavedPct())
                    refresh()
                end
            end)

            ScaleCtlRefresh = function()
                pending = nil
                ShowPct(SavedPct())
                refresh()
            end
            ScaleCtlRefresh()
            -- Shift + mouse wheel elsewhere on the panel steps the scale too: the
            -- readout follows at once and an accent outline round the control (a
            -- padded host, our own frame) lights up and fades, so the change is easy
            -- to trace. Each step restarts the fade.
            local glowHost = CreateFrame("Frame", nil, ctl)
            glowHost:SetPoint("TOPLEFT", ctl, "TOPLEFT", -10, 6)
            glowHost:SetPoint("BOTTOMRIGHT", ctl, "BOTTOMRIGHT", 8, -6)
            local PlayGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })
            CludesUI._FlashWindowScale = function()
                ScaleCtlRefresh()
                PlayGlow(glowHost)
            end
            CludesUI.RegAccent({ type = "callback", fn = function() refresh() end })
            -- Any scale change (this slider, Reset) lands here once its glide ends.
            if not CludesUI._onScaleChanged then CludesUI._onScaleChanged = {} end
            CludesUI._onScaleChanged[#CludesUI._onScaleChanged + 1] = function()
                if not CludesUI._sliderDragging then ScaleCtlRefresh() end
            end
        end
        local function ScaleCtlOnShow()
            if scaleCtl then ScaleCtlRefresh() else BuildScaleControl() end
        end
        CludesUI:RegisterOnShow(ScaleCtlOnShow)
        if CludesUI._mainFrame and CludesUI._mainFrame:IsShown() then ScaleCtlOnShow() end

    end

    -- Clean up profiles root when panel closes
    CludesUI:RegisterOnHide(function()
        CleanupProfilesRoot()
    end)

    -- Clean up profiles root when switching to any module other than Profiles
    if CludesUI.SelectModule then
        hooksecurefunc(CludesUI, "SelectModule", function(_, folderName)
            if folderName ~= PROFILES_KEY then
                CleanupProfilesRoot()
            end
        end)
    end

    -- HideAllChildren (every page switch) hides the profiles root too.
    CludesUI._AddScrollRootHider(CleanupProfilesRoot)
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
