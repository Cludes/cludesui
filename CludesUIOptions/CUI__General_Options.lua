if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
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
local CreateFrame = CUI._Pool.CreateFrame

-- The account-wide settings table, made if it is not there yet, for a write.
local function Account()
    if not CludesUIDB then CludesUIDB = {} end
    return CludesUIDB
end

-------------------------------------------------------------------------------
--  Page / section names
-------------------------------------------------------------------------------
local PAGE_GENERAL = "General"
local PAGE_FONTS = "Fonts" -- centralized fonts page; body lives in CUI_Fonts_Options.lua
local PAGE_TEXTURES = "Textures" -- centralized textures page; body lives in CUI_Textures_Options.lua
local PAGE_GLOWS = "Glows" -- centralized glow page; body lives in CUI_Glows_Options.lua
local PAGE_GAMEPAD = "Gamepad" -- controller settings page; body lives in CUI_Gamepad_Options.lua
local PAGE_STYLE = "Style" -- per-module CludesUI / Blizzard Style page; body lives in CUI_Style_Options.lua
local PAGE_COLORS = "Colors" -- the color half of the old "Fonts & Colors" page
local PAGE_NUMBERS = "Numbers" -- Number Format page; body lives in CUI_NumberFormat_Options.lua
local PAGE_PROFILES = "Profiles"
local PAGE_WHATSNEW = "Patch Notes"

-- Profiles/Patch Notes/CUI Legends are their own sidebar pages, not tabs under Global Settings. Keys match the sidebar buttons in CludesUI_Panel.lua.
local PROFILES_KEY = "_CUIProfiles"
local PATCHNOTES_KEY = "_CUIPatchNotes"

-- Standalone single-module builds rename the host addon to contain "Standalone". The What's New tab is suite-only, so it is never added to the page list there.
local IS_STANDALONE = type(ADDON_NAME) == "string" and ADDON_NAME:find("Standalone") ~= nil

-------------------------------------------------------------------------------
--  Shared CDM spell-layout export flow (full-profile AND per-addon export).
--  Asks to bundle the CDM spell layout (bar assignments + per-spell settings);
--  Yes opens the spec picker, then calls exportFn(includeCDM, cdmSpecs).
--  Exports ONLY on explicit "No" or a completed picker pick -- escaping
--  either popup produces NO export.
-------------------------------------------------------------------------------
function CUI.RunCDMSpellExportFlow(activeName, exportFn)
    local function pickThenExport()
        local specs = {}
        local sp = CludesUIDB
            and CludesUIDB.spellAssignments
            and CludesUIDB.spellAssignments.profiles
            and CludesUIDB.spellAssignments.profiles[activeName]
            and CludesUIDB.spellAssignments.profiles[activeName].specProfiles
        local num = CUI.IS_FOREVER and 0 or ((GetNumSpecializations and GetNumSpecializations()) or 0)
        for idx = 1, num do
            local specID = GetSpecializationInfo and GetSpecializationInfo(idx)
            if specID then
                local key = tostring(specID)
                local d = sp and sp[key]
                specs[#specs + 1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true
                        or false,
                }
            end
        end
        -- WoW Forever: one row, the store key the player's class uses.
        if CUI.IS_FOREVER then
            local ident = CUI.ForeverClassSpec(nil, CUI.SpecHasStringEntry, sp or {}, true)
            if ident then
                local key = tostring(ident)
                local d = sp and sp[key]
                specs[1] = {
                    key = key,
                    checked = (d and type(d.barSpells) == "table" and next(d.barSpells) ~= nil) and true
                        or false,
                }
            end
        end
        CUI:ShowCDMSpecPickerPopup({
            title = CUI.L("Export CDM Spells"),
            foreverAllKeys = true,
            subtitle = CUI.L(
                "This can't change which spells the user tracks in Blizzard's CDM.\nIt's recommended to also share your Blizzard CDM layout for any spec you choose here."
            ),
            subtitleColor = { 1, 0.82, 0.2 },
            subtitleAtBottom = true,
            confirmText = CUI.L("Export"),
            specs = specs,
            onConfirm = function(selectedSpecs) exportFn(true, selectedSpecs) end,
            onCancel = function() end, -- cancel / Esc / click-off: just close, NO export
        })
    end
    CUI:ShowConfirmPopup({
        title = CUI.L("Include CDM Spell Layout?"),
        message = CUI.L(
            "Include your Cooldown Manager spell layout (which spells sit on which bars) plus all per-spell settings for any specs you choose."
        ),
        confirmText = CUI.L("Yes"),
        cancelText = CUI.L("No"),
        onConfirm = function() pickThenExport() end,
        onCancel = function() exportFn(false, nil) end, -- "No": export WITHOUT layout
        onDismiss = function() end, -- Esc / click-off: just close, NO export
    })
end

-- Language-picker font: each entry is entirely one script (the CJK stock fonts
-- also cover the trailing "(Korean)"-style Latin text), so a plain per-entry
-- font from the locale system's own glyph table beats a multi-script family.
local function LP_FontFor(locale)
    local func = CUI.LocaleGlyphFont
    return (func and func(locale)) or (CUI.MEDIA_PATH .. "fonts\\Expressway.TTF")
end

-------------------------------------------------------------------------------
--  Patch-notes content for the What's New page (newest first). Entry `nav`
--  deep-links via NavigateToElementSettings(module, page, section, preSelect, highlight).
-------------------------------------------------------------------------------
CUI._WHATSNEW_PATCHES = {
    {
        version = "1.2.0",
        heroes = {
            {
                module = "Global Settings",
                title = "A whole new look",
                desc = "The settings window in the CludesUI style: a clean, flat frame with square corners, simple lines, and the CludesUI logo drawn in your own accent colour.",
            },
            {
                module = "Bags",
                title = "Modern bags, now the default",
                desc = "Your bags open in the Modern display: one tidy grid with category chips across the top, in place of the sidebar. Prefer the old layout? Set Bag Style back to Grid and it stays that way.",
            },
        },
        features = {
            {
                module = "Global Settings",
                title = "Clear names",
                desc = "Pages and settings say what they do: Edit Layout, Core Settings, What's New, Group Frames, Buff Checks, Quality of Life, Also Show When, Show Empty Slots and more.",
            },
            {
                module = "Global Settings",
                title = "One frame, your colour",
                desc = "Every theme now shares the same clean frame, and your colour comes from UI Accent Color on Core Settings. WoW Forever keeps its warm bronze.",
            },
        },
        fixes = {
            {
                module = "Forever Tools",
                forever = true,
                text = "A player whose level shows ?? now shows their known level in the tooltip, even when the game colours that line.",
            },
        },
    },
    {
        version = "1.1.0",
        heroes = {
            {
                module = "Global Settings",
                title = "Cards and descriptions",
                desc = "Every page groups its settings into cards, every setting has a short description under its name, and corners are square throughout, with tabs, sidebar and footer to match.",
            },
            {
                module = "Layout Mode",
                title = "A new Layout Mode bar",
                desc = "A toolbar across the top of the screen with square toggle buttons, the element filter, and Exit and Save & Exit on the right. It opens with a new animation.",
                onClick = function()
                    if CUI.OpenUnlockMode then CUI:OpenUnlockMode() end
                end,
            },
        },
        features = {
            {
                module = "Global Settings",
                title = "New icons and colours",
                desc = "CludesUI's own interface icons, a cool slate for pop-ups, menus and input boxes, and pop-ups with the title on the left and buttons on the right.",
            },
            {
                module = "Global Settings",
                title = "Buttons for quick choices",
                desc = "Settings with two or three options, such as Orientation or Grow Direction, show every option as a button, so one click does it.",
            },
            {
                module = "Global Settings",
                title = "Sidebar groups",
                desc = "Modules are grouped by what they are for: Combat, Group Content, Interface and Tools.",
            },
            {
                module = "Global Settings",
                title = "Minimap button",
                desc = "The minimap button uses LibDBIcon, so minimap button collectors tidy it away like any other addon's.",
            },
            {
                module = "Raid Frames",
                title = "Frame Bindings",
                desc = "Click and key bindings on your group frames. Global and spec bindings share one column on the left, with their options right beside them.",
            },
            {
                module = "Raid Frames",
                title = "Preview window",
                desc = "The raid and party preview opens in its own window beside the panel.",
            },
            {
                module = "Global Settings",
                title = "/cuiperf",
                desc = "Shows how much CPU time each CludesUI addon is using.",
            },
        },
        fixes = {
            { module = "Unit Frames", forever = true, text = "The Unit Frames page opens again." },
            {
                module = "Forever Tools",
                forever = true,
                text = "The Restock alert, the Discovery tracker and its librarian tooltip no longer cause Lua errors.",
            },
            { module = "Forever Tools", forever = true, text = "The Training page opens for every class." },
            {
                module = "Global Settings",
                text = "Setting descriptions no longer run under the icons and buttons beside a control.",
            },
        },
    },
    {
        version = "1.0.0",
        features = {
            {
                module = "Tank Kit",
                title = "Built for tanks",
                desc = "Your co-tank's health, debuffs and defensives beside your frames, TAUNT alerts, and a row of the externals other players put on you. Set it up under Tank Kit or with /ctank, and move its frames in Layout Mode.",
            },
            {
                module = "Raid Lead",
                title = "Sort or split the raid",
                desc = "/raidlead roles sorts the raid into tanks, melee, ranged and healers, /raidlead split makes two balanced halves, and /raidlead undo puts everyone back.",
            },
            {
                module = "Raid Lead",
                title = "Encounter reminders",
                desc = "Paste a boss note from wowutils, wowaudit or Method Raid Tools. On the pull, your lines appear just before they are due with a countdown, spoken aloud if you like. Leaders can send notes to the whole group.",
            },
            {
                module = "Raid Lead",
                title = "Invites, assistants and version check",
                desc = "Invite a saved roster, promote assistants as they join, and see who is running which CludesUI version.",
            },
            {
                module = "Raid Lead",
                title = "Ready check, sorted",
                desc = "On a ready check, CludesUI users report durability, item level, missing enchants, raid cooldowns still on cooldown, and a missing flask, food, rune or healthstone. The leader sees it all in one list.",
            },
            {
                module = "Raid Lead",
                title = "Immunities on You and Boss Pace",
                desc = "Icons for the immunities on you, and a boss health bar against your target kill time: green when you are ahead, red when behind.",
            },
            {
                module = "Raid Lead",
                title = "Nicknames, shared with your guild",
                desc = "Set your nickname once and other CludesUI users in your guild and group see it on their frames.",
            },
            {
                module = "Raid Lead",
                title = "Break timer",
                desc = "/raidlead break 5 puts a break countdown on every CludesUI user's screen, with a sound when it ends. The buttons are under Raid Lead > Setup.",
            },
            {
                module = "Raid Lead",
                title = "Kick rotation",
                desc = "Shows whose interrupt is next, from an intstart / intend block in the boss note or a Kick Order you type. It turns red with a sound when it is your turn.",
            },
            {
                module = "Raid Lead",
                title = "Aura Glows",
                desc = "A glowing icon while an aura you pick is on you. It is built on the game's own aura display, so it keeps working in boss fights. Under Raid Lead > Tracking.",
            },
            {
                module = "Raid Lead",
                title = "Feasts, gateways and stats",
                desc = "A chat line when a CludesUI user drops a feast or cauldron, a Gateway usable alert when you can click a Demonic Gateway, and a stats panel. Under Raid Lead > Tracking.",
            },
            {
                module = "Raid Lead",
                title = "Aura Sounds",
                desc = "Plays a sound when an aura you pick lands on you, gains a stack or falls off. The game plays it, so it works in boss fights too.",
            },
            {
                module = "Raid Lead",
                title = "Boss Timelines and Encounter Alerts",
                desc = "Every Midnight raid boss's abilities (/cbt), countdown bars for the next ones during the fight, and timed calls for your role on the reminder display.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Training Planner",
                desc = "What your trainer has for you right now and what it costs, what the next levels bring, and a chat line when you level up. Under Forever Tools > Training.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Tracking Reminder",
                desc = "Icons for tracking you know but have not switched on. Click one to turn it on. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Swing Timer",
                desc = "A bar per weapon that fills up to your next auto attack, timed from the swing length the game sends. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Mana Bar and five-second rule",
                desc = "Your mana while in Bear or Cat Form, and a line counting down the five-second rule after you spend mana. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Consumable Bar",
                desc = "The consumables in your bags on one clickable bar, with counts and cooldowns. Choose which kinds under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Raid Debuffs",
                desc = "The raid debuffs you pick, shown on your target: bright while up, dim while missing. Works in combat. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Gear Sets",
                desc = "Your equipment sets on a bar, swapped with one click, plus optional sets for mounted and resting. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Instance Tracker",
                desc = "New instances this hour against the cap, a run timer, and a summary of time, deaths, XP and loot when you leave. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Group Inspect",
                desc = "/cinspect lists everyone in your group with their level, item level and unenchanted slots. Click a name for the full inspect window.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Combat extras",
                desc = "A combat timer, a + Combat / - Combat alert, and a stealth reminder for rogues and cat druids. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Bag Space",
                desc = "Free bag slots on screen, a warning when you are nearly full, and the cheapest items you carry on hover.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Quest Automation",
                desc = "Accepts and turns in quests for you, stops when there is a reward to choose, and can post objective progress to your party. Hold Shift to skip.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Action Bar Profiles",
                desc = "Save your action bars and keybinds under a name and load them on any character of the same class. /cbars or Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Loot Sparkles",
                desc = "Keeps the sparkle on lootable quest items, even after a graphics preset turns it off. Under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Best in Slot list",
                desc = "Alt+Shift-click any item to make it your pick for its slot. /cbis shows the list and what you already have, tooltips mark BiS items, and a Drop Alert tells you when one drops.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Stat Weights and upgrades",
                desc = "A +X% upgrade line on gear tooltips for your spec, and each BiS pick's gain. Change any weight under Forever Tools > General.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Dungeon Journal",
                desc = "/cjournal shows every dungeon and raid with its bosses, loot and drop chances, a tip per boss and the quests.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Dungeon maps in the journal",
                desc = "Each dungeon page in /cjournal shows its map floor by floor, with a numbered pin per boss and the entrance.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Healer Mana and Pet Tracker",
                desc = "Your healers' mana, lowest first, with anyone drinking marked; and a warning when your pet is missing, passive or low.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Mana Efficiency",
                desc = "A mana spell's healing or damage per mana and per second on its tooltip, with your spell power and talents counted in.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Restock and reminders",
                desc = "A restock list when you reach a city (with optional auto buy), Lockpicking on lockbox tooltips, a gear swap reminder and a nudge about unspent talent points.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "PvP: enemy players and Kill on Sight",
                desc = "A new PvP page: enemy players nearby with alerts and stealth warnings, Kill on Sight, the last hour, win and loss statistics, and sharing that works with Spy users. /cpvp.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "XP per Hour and Group XP",
                desc = "XP per hour, time to level and how long each level took, plus XP bars for your group.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Layer Tracker",
                desc = "Which layer you are on, a countdown before the game moves you, and the layer swap accepted for you when you join a group.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Mail and Alts",
                desc = "What your alts hold on item tooltips, an Alts button and Quick Attach at the mailbox, and a warning before mail expires.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Boat and Zeppelin Timers",
                desc = "When each ship leaves and arrives, on the minimap and in a zone list. Timed by riding, clicking, or players who share their timings.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Town Map",
                desc = "Trainers, vendors, innkeepers, the bank, mailboxes and spirit healers for your faction on the world map, with mailboxes and spirit healers on the minimap too.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Blessing Bar",
                desc = "For paladins: a button per class that blesses whoever needs it next, your aura, seal and Righteous Fury, and /cbless for every paladin's assignments. Works with PallyPower users too.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Discovery",
                desc = "/cdiscovery lists the library books, the Cozy Sleeping Bag chain and a Field Journal of fish, herbs and dishes, with a tracker, map pins and an alert when a book is nearby.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Quest List and Rares",
                desc = "Discovery lists every quest and rare by zone with what you have done, puts quest givers and rares on the world map, and alerts you when a rare is close.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Professions",
                desc = "/cprof shows your next rank and where to train it, your skill-up recipes and a Recipe Finder for everything you have not learned, with an alert when the next rank is ready.",
            },
            {
                module = "Forever Tools",
                forever = true,
                title = "Player History and notes",
                desc = "Who you have grouped with and how often (/chistory), plus a tag and note on any player from their right-click menu, shown on their tooltip.",
            },
            {
                module = "Mythic+ Tools",
                title = "Title Line",
                desc = "Your Mythic+ rating against the 0.1% and 1% title lines, with a season graph. Open it with /titleline.",
            },
            {
                module = "Global Settings",
                title = "Expressway font",
                desc = "Expressway is the default font. Change it under Fonts, with Barlow Condensed and many more to pick from.",
            },
            {
                module = "Global Settings",
                title = "Slash commands",
                desc = "/cui opens the panel and /ce the core settings. Each addon has its own shortcut too, such as /cab, /cuf, /crf and /cnp.",
            },
        },
        fixes = {
            {
                module = "Global Settings",
                text = "Window artwork now loads only when it is first shown, instead of all at login, so it uses less video memory.",
            },
            {
                module = "Raid Frames",
                text = "Nicknames from Timeline Reminders, Northern Sky, Liquid and RakGaming Aliases are picked up again.",
            },
        },
    },
}

-------------------------------------------------------------------------------
--  FCT font -- handled by CludesUI_Startup.lua which runs earlier.
-------------------------------------------------------------------------------

-- Wait for CludesUI to exist
CUI.AtOptionsLogin(function()
    local Pix = CUI.PanelPP

    local GLOBAL_KEY = CUI.GLOBAL_KEY or "_CUIGlobal"
    local floor = math.floor
    local ceil = math.ceil
    local max = math.max

    ---------------------------------------------------------------------------
    --  CVar helpers
    ---------------------------------------------------------------------------
    local function GetCVarNum(cvar) return tonumber(GetCVar(cvar)) or 0 end

    local function SetCVarSafe(cvar, value)
        if InCombatLockdown() then return end
        CUI.SetCVar(cvar, value)
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
        local current, def = C_CVar.GetCVarInfo(cvar)
        return current or "", def or ""
    end

    --- True while the CVar sits at Blizzard's built-in default (untouched by player or addon).
    local function IsAtBlizzardDefault(cvar)
        local current, def = CVarInfo(cvar)
        return current == def
    end

    ---------------------------------------------------------------------------
    --  CUI preferred defaults -- only applied when CVar == Blizzard default
    --
    --  { cvarName, cuiPreferred }
    ---------------------------------------------------------------------------
    local CUI_DEFAULTS = {
        { "cameraDistanceMaxZoomFactor", "2.6" },
        { "ActionButtonUseKeyDown", "1" },
    }

    --- Walk the table once at login and apply only where safe.
    local function ApplySmartDefaults()
        for _, record in ipairs(CUI_DEFAULTS) do
            local cvar, preferred = record[1], record[2]
            if IsAtBlizzardDefault(cvar) then SetCVarSafe(cvar, preferred) end
        end
    end
    ApplySmartDefaults()

    -- Apply suppress lua errors on login (default: ON)
    if not CludesUIDB or CludesUIDB.suppressErrors ~= false then SetCVarSafe("scriptErrors", "0") end

    -- Optimized graphics settings are NOT re-applied on login: SetCVar already persists, so re-applying would override the user's manual adjustments.

    ---------------------------------------------------------------------------
    --  General page
    ---------------------------------------------------------------------------
    local function BuildGeneralPage(page, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height

        hostFrame._showRowDivider = true

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -------------------------------------------------------------------
        --  Optimized graphics CVar table + buttons (above all sections)
        -------------------------------------------------------------------
        local OPTIMIZED_CVARS = {
            { "graphicsShadowQuality", "1" },
            { "graphicsLiquidDetail", "0" },
            { "graphicsParticleDensity", "5" },
            { "graphicsSSAO", "0" },
            { "graphicsDepthEffects", "0" },
            { "graphicsComputeEffects", "0" },
            { "graphicsOutlineMode", "0" },
            { "graphicsTextureResolution", "2" },
            { "graphicsSpellDensity", "0" },
            { "graphicsProjectedTextures", "1" },
            { "graphicsViewDistance", "0" },
            { "graphicsEnvironmentDetail", "0" },
            { "graphicsGroundClutter", "0" },
            { "RAIDsettingsEnabled", "0" },
            { "ResampleAlwaysSharpen", "1" },
            -- Reverb runs a full effect bus over the mix; disabling it trims audio DSP work and keeps spell/interrupt cues dry and crisp.
            { "Sound_EnableReverb", "0" },
        }

        local function ApplyOptimizedGfx()
            -- Refused in combat, where SetGfxCVar writes nothing: a backup taken
            -- then would turn the card into Restore with nothing optimized.
            if InCombatLockdown() then return end
            if not CludesUIDB then CludesUIDB = {} end
            -- One-time store: only snapshot if no backup exists yet
            if not CludesUIDB.gfxBackup then
                local backup = {}
                for _, record in ipairs(OPTIMIZED_CVARS) do
                    backup[record[1]] = GetCVar(record[1])
                end
                backup["Contrast"] = GetCVar("Contrast")
                CludesUIDB.gfxBackup = backup
            else
                -- Backfill CVars added to the list after the original snapshot so Restore covers them too.
                local backup = CludesUIDB.gfxBackup
                for _, record in ipairs(OPTIMIZED_CVARS) do
                    if backup[record[1]] == nil then backup[record[1]] = GetCVar(record[1]) end
                end
            end
            for _, record in ipairs(OPTIMIZED_CVARS) do
                SetGfxCVar(record[1], record[2])
            end
            local curContrast = tonumber(GetCVar("Contrast")) or 50
            if curContrast <= 55 then SetGfxCVar("Contrast", curContrast + 10) end
            local refreshList = CUI._widgetRefreshList
            if refreshList then
                for idx = 1, #refreshList do
                    refreshList[idx]()
                end
            end
        end

        local function RestoreGfxSettings()
            if not CludesUIDB or not CludesUIDB.gfxBackup then return end
            if InCombatLockdown() then return end
            local backup = CludesUIDB.gfxBackup
            for _, record in ipairs(OPTIMIZED_CVARS) do
                local saved = backup[record[1]]
                if saved then SetGfxCVar(record[1], saved) end
            end
            if backup["Contrast"] then SetGfxCVar("Contrast", backup["Contrast"]) end
            CludesUIDB.gfxBackup = nil
            local rl2 = CUI._widgetRefreshList
            if rl2 then
                for idx = 1, #rl2 do
                    rl2[idx]()
                end
            end
        end

        -------------------------------------------------------------------
        --  The actions Maintenance (at the foot of the page) runs: Reset CUI
        --  Module Settings, Optimize My FPS and Graphics (Restore while a
        --  graphics backup exists) and Uninstall CUI.
        -------------------------------------------------------------------
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
                "autoOpenContainers",
                "autoSellJunk",
                "autoRepair",
                "autoRepairGuild",
                "hideScreenshotStatus",
                "autoUnwrapCollections",
                "trainAllButton",
                "ahCurrentExpansion",
                "quickLoot",
                "autoFillDelete",
                "skipCinematics",
                "skipCinematicsAuto",
                "bonusRollConfirmation",
                "bonusRollOnly",
                "autoInsertKeystone",
                "quickSignup",
                "persistSignupNote",
                "signupNote",
                "hideBlizzardPartyFrame",
                "instanceResetAnnounce",
                "instanceResetAnnounceMsg",
                "macroFactory",
            }
            local savedQoL = {}
            for _, keyName in ipairs(qolKeys) do
                if CludesUIDB[keyName] ~= nil then savedQoL[keyName] = CludesUIDB[keyName] end
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
                for keyName, val in pairs(savedFriends) do
                    CludesUIDB.global[keyName] = val
                end
            end
            for keyName, val in pairs(savedQoL) do
                CludesUIDB[keyName] = val
            end
        end

        -- Reset ALL: a typed confirm, then the wipe and a reload (the wipe runs
        -- as RequestReload's pre-reload work).
        local function ConfirmResetAll()
            CUI:ShowConfirmPopup({
                title = "Reset ALL Settings",
                -- The wipe replaces the whole account store, profiles included.
                message = "Are you sure you want to reset ALL CUI addon settings to their defaults? This deletes ALL of your profiles, not just the current one, and reloads your UI.",
                disclaimer = "Every profile on this account is deleted. Export any profile you want to keep first.",
                typeToConfirm = "Confirm",
                confirmText = "Reset All & Reload",
                cancelText = "Cancel",
                onConfirm = function()
                    CUI.RequestReload(
                        CUI.L("Reset ALL Settings"),
                        CUI.L("Reload to finish resetting CUI."),
                        ResetAllNow
                    )
                end,
            })
        end

        -- Uninstall CUI is refused in combat (it reloads) and while Edit Mode is open (it
        -- saves its own copy of the layouts on exit, over the ones put back). True when
        -- it was refused.
        local function UninstallRefused()
            local msg
            if InCombatLockdown() then
                msg =
                    CUI.L("Uninstalling reloads the UI and cannot run in combat. Leave combat and try again.")
            elseif CUI.EditModeOpen() then
                msg = CUI.L("Close Edit Mode first, then try again.")
            end
            if not msg then return false end
            CUI:ShowConfirmPopup({
                title = CUI.L("Uninstall CUI"),
                message = msg,
                confirmText = CUI.L("OK"),
                hideCancel = true,
            })
            return true
        end

        -- Uninstall CUI: puts back the game settings CludesUI changed, turns it off for
        -- every character and reloads (CludesUI_Uninstall.lua). Profiles are kept. The
        -- reload is a RequestReload from onConfirm, not reload = true: the refusal is
        -- checked again there, and reload = true would reload even when it is refused.
        local function ConfirmUninstall()
            if UninstallRefused() then return end
            local message = CUI.L(
                "Puts back the game settings CUI changed, such as nameplate, action bar, chat and tooltip options, and turns CUI off for every character, then reloads the UI."
            ) .. "\n\n" .. CUI.L(
                "Your profiles are kept, so you can turn CUI back on later in the AddOns list."
            )
            if CludesUIDB and CludesUIDB.gfxBackup then
                message = message
                    .. "\n\n"
                    .. CUI.L(
                        "Graphics changed by Optimize My FPS and Graphics stay as they are. To undo them, click Restore My Graphics Settings first."
                    )
            end
            CUI:ShowConfirmPopup({
                title = CUI.L("Uninstall CUI"),
                message = message,
                disclaimer = (not CUI.UninstallKnowsOriginals())
                        and CUI.L(
                            "CUI was installed before it kept a record of your original settings, so the settings it still manages go back to the game's defaults."
                        )
                    or nil,
                confirmText = CUI.L("Uninstall & Reload"),
                cancelText = CUI.L("Cancel"),
                onConfirm = function()
                    if UninstallRefused() then return end
                    CUI.RequestReload(
                        CUI.L("Uninstall CUI"),
                        CUI.L("Reload to finish uninstalling CUI."),
                        CUI.Uninstall
                    )
                end,
            })
        end

        -- A saved graphics backup means Optimize has run: Maintenance offers Restore.
        local function HasGfxBackup() return (CludesUIDB and CludesUIDB.gfxBackup) ~= nil end
        -- What Optimize changes, for Maintenance's Details button.
        local function ShowOptimizeInfo()
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
            CUI:ShowInfoPopup({
                title = "FPS & Graphics Optimization",
                content = CUI.L(
                    "This feature optimizes your in-game graphics settings to give you the best combination of high FPS and visual clarity."
                )
                    .. "\n\n"
                    .. CUI.L(
                        "After optimizing, the button changes to 'Restore My Graphics Settings', which reverts every change."
                    )
                    .. "\n\n\n"
                    .. CUI.L(CHANGES),
            })
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "DISPLAY", cursorY)
        cursorY = cursorY - height

        local themeValues = {}
        for _, name in ipairs(CUI.THEME_ORDER) do
            themeValues[name] = name
        end

        -- Row 1: CUI Options Theme | UI Accent Color (the accent follows the theme)
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "CUI Options Theme",
            tooltip = "The look of this options window: its frame art and colours.",
            values = themeValues,
            order = CUI.THEME_ORDER,
            getValue = function() return CUI.GetActiveTheme() end,
            setValue = function(val)
                CUI.SetActiveTheme(val)
                -- Re-resolve the accent so the sidebar highlight tracks the theme.
                if CUI.RefreshAccent then
                    CUI.RefreshAccent() -- ApplyAccentLive already refreshes the page
                else
                    CUI:RefreshPage()
                end
            end,
        }, {
            type = "multiSwatch",
            text = "UI Accent Color",
            tooltip = "Sets the accent color used across all CludesUI elements (tabs, glows, highlights, borders). Defaults to your theme color.",
            swatches = {
                {
                    tooltip = "Class Color",
                    getValue = function()
                        local cr, cg, cb = CUI.GetPlayerClassColor()
                        return cr, cg, cb, 1
                    end,
                    setValue = function() end,
                    onClick = function()
                        -- Per-profile: set use-class, then re-resolve + apply live.
                        CUI.SetActiveProfileAccent(nil, true)
                        CUI.RefreshAccent()
                        CUI:RefreshPage()
                    end,
                    refreshAlpha = function() return (select(1, CUI.GetActiveAccentState())) and 1 or 0.3 end,
                },
                {
                    tooltip = "Custom Color",
                    hasAlpha = false,
                    getValue = function()
                        local _, ca = CUI.GetActiveAccentState()
                        if ca then return ca.r, ca.g, ca.b, 1 end
                        return CUI.DEFAULT_ACCENT_R, CUI.DEFAULT_ACCENT_G, CUI.DEFAULT_ACCENT_B, 1
                    end,
                    setValue = function(red, green, blue)
                        -- Persists per-profile (custom + useClass=false), applies live.
                        CUI.SetAccentColor(red, green, blue)
                    end,
                    onClick = function(self)
                        if select(1, CUI.GetActiveAccentState()) then
                            -- Switch class -> custom: clear the per-profile class flag and re-resolve (profile custom -> global -> theme).
                            CUI.SetActiveProfileAccent(nil, false)
                            CUI.RefreshAccent()
                            CUI:RefreshPage()
                            return
                        end
                        if self._eabOrigClick then self._eabOrigClick(self) end
                    end,
                    refreshAlpha = function() return (select(1, CUI.GetActiveAccentState())) and 0.3 or 1 end,
                },
            },
        })
        cursorY = cursorY - height

        -- CUI Options Language (Row 2's right slot): options-panel display language (auto-detects the client; untranslated text falls back to English).
        local langCfg
        do
            -- _noLoc: the language list itself is never translated, so a player who booted the wrong language can always read and change it.
            local langValues = {
                _noLoc = true,
                ["auto"] = { text = CUI.L("Automatic (Client)") },
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
            local langOrder = {
                "auto",
                "enUS",
                "deDE",
                "frFR",
                "esES",
                "esMX",
                "itIT",
                "ptBR",
                "ruRU",
                "koKR",
                "zhCN",
                "zhTW",
            }
            -- Pin each entry to the plain font its own script needs, independent
            -- of whichever display locale is currently active.
            for _, key in ipairs(langOrder) do
                langValues[key].font = LP_FontFor(key)
            end
            -- "auto"'s own text is translated, not a fixed native-script name, so
            -- its script follows the ACTIVE locale rather than its own key.
            langValues["auto"].font = LP_FontFor(CUI.LOCALE)

            local function LanguageReload()
                CUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Changing the language requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end

            -- A non-English game client reads only its own translation file, its
            -- pair's and none other: CludesUILocales.toc tags each file with
            -- the client languages that load it (keep LANG_PAIR in step with its
            -- pairs). English clients read every file.
            local LANG_PAIR = { esMX = "esES", zhCN = "zhTW", zhTW = "zhCN" }
            local clientLocale = GetLocale()
            local function LanguageUnavailable(val)
                if val == "auto" or val == "enUS" or clientLocale == "enUS" or clientLocale == "enGB" then
                    return false
                end
                if val == clientLocale or LANG_PAIR[clientLocale] == val then return false end
                return "Needs the game client set to English or to this language."
            end

            langCfg = {
                type = "dropdown",
                text = "CUI Options Language",
                tooltip = "The display language for the CludesUI options panel. Auto follows your game client. Untranslated text falls back to English.",
                values = langValues,
                order = langOrder,
                disabledValues = LanguageUnavailable,
                getValue = function() return (CludesUIDB and CludesUIDB.displayLocale) or "auto" end,
                setValue = function(val)
                    if val == "auto" then val = nil end
                    if CludesUIDB then CludesUIDB.displayLocale = val end
                    LanguageReload()
                end,
            }
        end

        -- Row 2: UI Scale | CUI Options Language
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "UI Scale",
            min = 0.40,
            max = 1.00,
            step = 0.01,
            tooltip = "Sets the scale of the whole game UI. 0.53 = 0.5333 and 0.71 = 0.7111",
            tooltipOnControl = true,
            getValue = function()
                if CUI._uiScaleDragVal then return CUI._uiScaleDragVal end
                return CludesUIDB and CludesUIDB.ppUIScale or CUI.PP.PixelBestSize()
            end,
            setValue = function(val)
                if not CludesUIDB then CludesUIDB = {} end
                -- Snap 0.53 to exact pixel-perfect 0.5333... (768/1440)
                if math.abs(val - 0.53) < 0.005 then val = 0.5333333333 end
                -- Snap 0.71 to exact pixel-perfect 0.7111... (768/1080)
                if math.abs(val - 0.71) < 0.005 then val = 0.7111111111 end
                CUI._uiScaleDragVal = val
                CludesUIDB.ppUIScaleAuto = false
                local mf = CUI._mainFrame
                local panelScaleBefore
                if mf then panelScaleBefore = mf:GetEffectiveScale() end
                CUI.PP.SetUIScale(val)
                if mf and panelScaleBefore then
                    local newEff = UIParent:GetEffectiveScale()
                    if newEff > 0 then mf:SetScale(panelScaleBefore / newEff) end
                end
                if not CUI._uiScaleCleanup then
                    CUI._uiScaleCleanup = true
                    C_Timer.After(0, function()
                        if not CUI._sliderDragging then
                            CUI._uiScaleDragVal = nil
                            CUI:ShowConfirmPopup({
                                title = "UI Scale Changed",
                                message = "Blizzard's Edit Mode snapping may not work correctly until you reload your UI.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload = true,
                            })
                        end
                        CUI._uiScaleCleanup = false
                    end)
                end
            end,
        }, langCfg)
        cursorY = cursorY - height

        -- Row 3: CUI Buttons (merged button toggles) | Disable Sync Icons (+ cog)
        -- "CUI Buttons" merges the Pause Menu, Unlock Mode Menu and Minimap
        -- toggles into one checkbox-dropdown over the SAME backend variables: front-end grouping only, settings/defaults unchanged.
        local cuiBtnItems = {
            {
                key = "pause",
                label = "Hide Pause Menu Button",
                tooltip = "Hides the CludesUI button from the game's Escape/pause menu.",
            },
            {
                key = "unlock",
                label = "Hide Layout Mode Menu Button",
                tooltip = "Hides the Layout Mode button from the game's Escape/pause menu. You can still toggle Layout Mode from the CUI options panel.",
            },
            { key = "minimap", label = "Show Minimap Button" },
        }
        local cuiBtnRow
        cuiBtnRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "CUI Buttons",
            tooltip = "Toggle CludesUI's optional buttons: the Escape menu buttons and the minimap button.",
            values = { ["_placeholder"] = "..." },
            order = { "_placeholder" },
            getValue = function() return "_placeholder" end,
            setValue = function() end,
        }, {
            type = "toggle",
            text = "Disable Sync Icons",
            tooltip = "Hides the sync icons on the sidebar module list.",
            getValue = function() return CludesUIDB and CludesUIDB.hideSyncIcons or false end,
            setValue = function(val)
                Account().hideSyncIcons = val
                if CUI._refreshAllSyncIcons then CUI._refreshAllSyncIcons() end
            end,
        })
        cursorY = cursorY - height
        -- CUI Buttons checkbox-dropdown (left region)
        if not CUI._prebuilding then
            local region = cuiBtnRow._leftRegion
            if region._control then region._control:Hide() end
            local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                cuiBtnItems,
                function(keyName)
                    if keyName == "pause" then
                        return CludesUIDB and CludesUIDB.hideGameMenuButton or false
                    elseif keyName == "unlock" then
                        return not CludesUIDB or CludesUIDB.hideUnlockMenuButton ~= false
                    elseif keyName == "minimap" then
                        return not (CludesUIDB and CludesUIDB.showMinimapButton == false)
                    end
                    return false
                end,
                function(keyName, val)
                    if not CludesUIDB then CludesUIDB = {} end
                    if keyName == "pause" then
                        CludesUIDB.hideGameMenuButton = val
                    elseif keyName == "unlock" then
                        CludesUIDB.hideUnlockMenuButton = val
                    elseif keyName == "minimap" then
                        CludesUIDB.showMinimapButton = val
                        if val then
                            CUI.ShowMinimapButton()
                        else
                            CUI.HideMinimapButton()
                        end
                    end
                end
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(cbDDRefresh)
        end
        -- Cog with "Only Hide Fully Synced" toggle on Disable Sync Icons (right region)
        if not CUI._prebuilding then
            local region = cuiBtnRow._rightRegion
            CUI.BuildInlineCog(region, {
                title = "Sync Icon Options",
                rows = {
                    {
                        type = "toggle",
                        label = "Only Hide Fully Synced",
                        get = function() return CludesUIDB and CludesUIDB.hideSyncIconsOnlyFull or false end,
                        set = function(val)
                            Account().hideSyncIconsOnlyFull = val
                            if CUI._refreshAllSyncIcons then CUI._refreshAllSyncIcons() end
                        end,
                    },
                },
            })
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "UNLOCK MODE", cursorY)
        cursorY = cursorY - height
        local pointAnchorRow
        pointAnchorRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Point Anchoring",
            tooltip = "Show nine source points after clicking Anchor in Layout Mode. Choose a source point, then a target point. Turning this off hides the handles and preserves saved point anchors.",
            getValue = function() return CludesUIDB and CludesUIDB.unlockPointHandles == true end,
            setValue = function(val)
                CUI.SetPointAnchorHandles(val)
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Overlap Cycling",
            tooltip = "Scroll with the chosen modifier to cycle overlapping frames in Layout Mode.",
            values = CUI.UNLOCK_OVERLAP_LABELS,
            order = { "disabled", "scroll", "shiftscroll", "controlscroll", "altscroll" },
            getValue = function() return CUI.GetUnlockOverlapMethod() end,
            setValue = function(val)
                CludesUIDB = CludesUIDB or {}
                CludesUIDB.unlockOverlapMethod = val
                if CUI.RefreshUnlockOverlapMethod then CUI.RefreshUnlockOverlapMethod() end
            end,
        })
        cursorY = cursorY - height
        if not CUI._prebuilding then
            CUI.BuildInlineSwatches(pointAnchorRow._leftRegion, {
                {
                    tooltip = "Connector Lines Color",
                    hasAlpha = true,
                    getValue = function() return CUI.GetPointAnchorColor("line") end,
                    setValue = function(red, green, blue, a)
                        CUI.SetPointAnchorColor("line", red, green, blue, a)
                    end,
                },
                {
                    tooltip = "Border Color",
                    hasAlpha = true,
                    getValue = function() return CUI.GetPointAnchorColor("border") end,
                    setValue = function(red, green, blue, a)
                        CUI.SetPointAnchorColor("border", red, green, blue, a)
                    end,
                },
                {
                    tooltip = "Point Color",
                    hasAlpha = true,
                    getValue = function() return CUI.GetPointAnchorColor("point") end,
                    setValue = function(red, green, blue, a)
                        CUI.SetPointAnchorColor("point", red, green, blue, a)
                    end,
                },
            }, {
                disabled = function() return not (CludesUIDB and CludesUIDB.unlockPointHandles == true) end,
                disabledTooltip = "Point Anchoring",
            })
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "COMBAT", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Max Camera Distance",
            tooltip = "How far the camera can zoom out.",
            min = 1,
            max = 2.6,
            step = 0.1,
            getValue = function() return GetCVarNum("cameraDistanceMaxZoomFactor") end,
            setValue = function(val)
                val = floor(val * 10 + 0.5) / 10
                SetCVarSafe("cameraDistanceMaxZoomFactor", val)
            end,
        }, {
            type = "toggle",
            text = "Increase Game Image Quality",
            tooltip = "Enables sharpening to improve image clarity. Especially noticeable at lower render scales.",
            getValue = function() return GetCVarBool("ResampleAlwaysSharpen") end,
            setValue = function(val) SetGfxCVar("ResampleAlwaysSharpen", val and "1" or "0") end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Cast Actions on Key Down",
            tooltip = "Keybinds respond on key down instead of key up. This helps make your abilities feel more responsive.",
            getValue = function() return GetCVarBool("ActionButtonUseKeyDown") end,
            setValue = function(val)
                SetCVarSafe("ActionButtonUseKeyDown", val and "1" or "0")
                if _G._CUAB_ApplyKeyDown then _G._CUAB_ApplyKeyDown() end
            end,
        }, {
            type = "slider",
            text = "Lag Tolerance",
            tooltip = "This is the Spell Queue Window, it helps with making sure you can't queue up too many spells at once which makes the game feel laggy. Recommended settings are generally a minimum of 200 + your local ping. If you are unsure of exactly what this setting does, leave it at 400.",
            min = 0,
            max = 400,
            step = 1,
            getValue = function() return GetCVarNum("SpellQueueWindow") end,
            setValue = function(val) SetCVarSafe("SpellQueueWindow", val) end,
        })
        cursorY = cursorY - height

        local FCT_FONT_DIR = "Interface\\AddOns\\CludesUI\\media\\fonts\\"
        local fctFontValues = {
            ["default"] = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" },
            [FCT_FONT_DIR .. "Expressway.TTF"] = {
                text = "Expressway",
                font = FCT_FONT_DIR .. "Expressway.TTF",
            },
            [FCT_FONT_DIR .. "Avant Garde.ttf"] = {
                text = "Avant Garde",
                font = FCT_FONT_DIR .. "Avant Garde.ttf",
            },
            [FCT_FONT_DIR .. "Arial Bold.TTF"] = {
                text = "Arial Bold",
                font = FCT_FONT_DIR .. "Arial Bold.TTF",
            },
            [FCT_FONT_DIR .. "Poppins.ttf"] = {
                text = "Poppins",
                font = FCT_FONT_DIR .. "Poppins.ttf",
            },
            [FCT_FONT_DIR .. "FiraSans Medium.ttf"] = {
                text = "Fira Sans Medium",
                font = FCT_FONT_DIR .. "FiraSans Medium.ttf",
            },
            [FCT_FONT_DIR .. "Expressway CAPS.ttf"] = {
                text = "Expressway CAPS",
                font = FCT_FONT_DIR .. "Expressway CAPS.ttf",
            },
            [FCT_FONT_DIR .. "Arial Narrow.ttf"] = {
                text = "Arial Narrow",
                font = FCT_FONT_DIR .. "Arial Narrow.ttf",
            },
            [FCT_FONT_DIR .. "Changa.ttf"] = {
                text = "Changa",
                font = FCT_FONT_DIR .. "Changa.ttf",
            },
            [FCT_FONT_DIR .. "Cinzel Decorative.ttf"] = {
                text = "Cinzel Decorative",
                font = FCT_FONT_DIR .. "Cinzel Decorative.ttf",
            },
            [FCT_FONT_DIR .. "Exo.otf"] = { text = "Exo", font = FCT_FONT_DIR .. "Exo.otf" },
            [FCT_FONT_DIR .. "FiraSans Bold.ttf"] = {
                text = "Fira Sans Bold",
                font = FCT_FONT_DIR .. "FiraSans Bold.ttf",
            },
            [FCT_FONT_DIR .. "FiraSans Light.ttf"] = {
                text = "Fira Sans Light",
                font = FCT_FONT_DIR .. "FiraSans Light.ttf",
            },
            [FCT_FONT_DIR .. "Future X Black.otf"] = {
                text = "Future X Black",
                font = FCT_FONT_DIR .. "Future X Black.otf",
            },
            [FCT_FONT_DIR .. "Gotham Narrow Ultra.otf"] = {
                text = "Gotham Narrow Ultra",
                font = FCT_FONT_DIR .. "Gotham Narrow Ultra.otf",
            },
            [FCT_FONT_DIR .. "Gotham Narrow.otf"] = {
                text = "Gotham Narrow",
                font = FCT_FONT_DIR .. "Gotham Narrow.otf",
            },
            [FCT_FONT_DIR .. "Russo One.ttf"] = {
                text = "Russo One",
                font = FCT_FONT_DIR .. "Russo One.ttf",
            },
            [FCT_FONT_DIR .. "Ubuntu.ttf"] = {
                text = "Ubuntu",
                font = FCT_FONT_DIR .. "Ubuntu.ttf",
            },
            [FCT_FONT_DIR .. "Homespun.ttf"] = {
                text = "Homespun",
                font = FCT_FONT_DIR .. "Homespun.ttf",
            },
            [FCT_FONT_DIR .. "HWT Artz.ttf"] = {
                text = "HWT Artz",
                font = FCT_FONT_DIR .. "HWT Artz.ttf",
            },
            ["Fonts\\FRIZQT__.TTF"] = { text = "Friz Quadrata", font = "Fonts\\FRIZQT__.TTF" },
            ["Fonts\\ARIALN.TTF"] = { text = "Arial", font = "Fonts\\ARIALN.TTF" },
            ["Fonts\\MORPHEUS.TTF"] = { text = "Morpheus", font = "Fonts\\MORPHEUS.TTF" },
            ["Fonts\\skurri.ttf"] = { text = "Skurri", font = "Fonts\\skurri.ttf" },
        }
        local fctFontOrder = {
            "default",
            FCT_FONT_DIR .. "Expressway.TTF",
            FCT_FONT_DIR .. "Avant Garde.ttf",
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
        for idx = #fctFontOrder, 2, -1 do
            local keyName = fctFontOrder[idx]
            if keyName ~= "---" and not CUI.CombatTextFontCoversLocale(keyName) then
                table.remove(fctFontOrder, idx)
            end
        end
        if fctFontOrder[#fctFontOrder] == "---" then fctFontOrder[#fctFontOrder] = nil end
        CUI.AppendSharedMediaFonts(fctFontValues, fctFontOrder)

        -- Combat Text (checkbox dropdown + size cog) | Combat Text Font. The
        -- dropdown is a view over the floating combat text CVars the client
        -- has; each extra only applies while the item it refines is on (the
        -- damage extras under Damage, Absorb Shields under Healing, Others'
        -- Target Effects under Target Effects).
        local function DmgOff() return not GetCVarBool("floatingCombatTextCombatDamage_v2") end
        local function HealOff() return not GetCVarBool("floatingCombatTextCombatHealing_v2") end
        local function FxOff() return not GetCVarBool("floatingCombatTextSpellMechanics_v2") end
        local dmgTip = CUI.DisabledTooltip("Damage")
        local healTip = CUI.DisabledTooltip("Healing")
        local fxTip = CUI.DisabledTooltip("Target Effects")
        local COMBAT_TEXT = {}
        for _, entry in ipairs({
            { key = "floatingCombatTextCombatDamage_v2", label = "Damage" },
            {
                key = "floatingCombatTextCombatLogPeriodicSpells_v2",
                label = "Periodic Damage",
                lockedFn = DmgOff,
                lockedTooltip = dmgTip,
                excludeFromSummaryFn = DmgOff,
            },
            {
                key = "floatingCombatTextPetMeleeDamage_v2",
                label = "Pet Melee Damage",
                lockedFn = DmgOff,
                lockedTooltip = dmgTip,
                excludeFromSummaryFn = DmgOff,
            },
            {
                key = "floatingCombatTextPetSpellDamage_v2",
                label = "Pet Spell Damage",
                lockedFn = DmgOff,
                lockedTooltip = dmgTip,
                excludeFromSummaryFn = DmgOff,
            },
            { key = "floatingCombatTextCombatHealing_v2", label = "Healing" },
            {
                key = "floatingCombatTextCombatHealingAbsorbTarget_v2",
                label = "Absorb Shields",
                lockedFn = HealOff,
                lockedTooltip = healTip,
                excludeFromSummaryFn = HealOff,
            },
            { key = "floatingCombatTextSpellMechanics_v2", label = "Target Effects" },
            {
                key = "floatingCombatTextSpellMechanicsOther_v2",
                label = "Others' Target Effects",
                lockedFn = FxOff,
                lockedTooltip = fxTip,
                excludeFromSummaryFn = FxOff,
            },
        }) do
            if C_CVar.GetCVarInfo(entry.key) then COMBAT_TEXT[#COMBAT_TEXT + 1] = entry end
        end
        local combatTextRow
        combatTextRow, height = W:DualRow(hostFrame, cursorY, { type = "label", text = "Combat Text" }, {
            type = "dropdown",
            text = "Combat Text Font",
            tooltip = "WARNING: This feature requires you to re-log or restart WoW to take effect.",
            tooltipOpts = { color = { 1, 0.3, 0.3 } },
            values = fctFontValues,
            order = fctFontOrder,
            getValue = function()
                local val = CludesUIDB and CludesUIDB.fctFont
                return val and CUI.CombatTextFontCoversLocale(val) and val or "default"
            end,
            setValue = function(val)
                if not CludesUIDB then CludesUIDB = {} end
                if val == "default" then
                    CludesUIDB.fctFont = nil
                    CludesUIDB.fctFontPath = nil
                    CludesUIDB.fctFontPathFor = nil
                else
                    CludesUIDB.fctFont = val
                    -- smf: keys cache their resolved path for the next login's
                    -- early window; see ApplyCombatTextFont in Startup.
                    local e = val:match("^smf:") and fctFontValues[val]
                    CludesUIDB.fctFontPath = e and e.font
                    CludesUIDB.fctFontPathFor = e and val
                end
                CUI:ShowConfirmPopup({
                    title = "Logout Required",
                    message = "Combat text font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                    confirmText = "Okay",
                    cancelText = "Later",
                })
            end,
        })
        cursorY = cursorY - height
        if not CUI._prebuilding then
            local region = combatTextRow._leftRegion
            local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                COMBAT_TEXT,
                function(key) return GetCVarBool(key) end,
                function(key, val) SetCVarSafe(key, val and "1" or "0") end
            )
            Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(cbDDRefresh)
            CUI.BuildInlineCog(region, {
                title = "Combat Text Size",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 0.5,
                        max = 2.5,
                        step = 0.1,
                        get = function() return GetCVarNum("WorldTextScale_v2") end,
                        set = function(val)
                            val = floor(val * 10 + 0.5) / 10
                            SetCVarSafe("WorldTextScale_v2", val)
                        end,
                    },
                },
            })
        end

        -- Swiftmend Brightness Fix (Druid only): the right slot beside Round
        -- Timer Seconds Down, blank for every other class.
        local swiftmendCfg = CUI.BlankRowCfg()
        local _, playerClass = UnitClass("player")
        if playerClass == "DRUID" then
            swiftmendCfg = {
                type = "toggle",
                text = "Prevent Swiftmend Icon Dim",
                tooltip = "Prevents Blizzard from dimming Swiftmend on action bars and CDM based on Efflorescence state.",
                getValue = function() return not CludesUIDB or CludesUIDB.brightenSwiftmend ~= false end,
                setValue = function(val)
                    Account().brightenSwiftmend = val
                    if val then
                        if _G._CUAB_ScanSwiftmend then _G._CUAB_ScanSwiftmend() end
                        if _G._CUCDM_ScanSwiftmend then _G._CUCDM_ScanSwiftmend() end
                    end
                end,
            }
        end

        -- Row 4: Round Timer Seconds Down | Prevent Swiftmend Icon Dim. Every
        -- timer keeps the formatter it was given (AuraKit reads the setting
        -- once), so a change waits for a reload.
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Round Timer Seconds Down",
            tooltip = "Timer seconds round down like Blizzard's buff frame, so a timer reads 0 in its last second. Off, it reads 1 until it ends.",
            getValue = function() return CludesUIDB and CludesUIDB.timerSecondsDown == true or false end,
            setValue = function(val)
                Account().timerSecondsDown = val or nil
                CUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Changing how timers round requires a UI reload.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end,
        }, swiftmendCfg)
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -------------------------------------------------------------------
        --  MAINTENANCE: the account-wide actions, kept at the foot of the page
        --  so they are at hand without being the first thing on it.
        -------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, "MAINTENANCE", cursorY)
        cursorY = cursorY - height
        do
            local restore = HasGfxBackup()
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = restore and "Restore My Graphics Settings" or "Optimize My FPS and Graphics",
                buttonText = restore and "Restore" or "Optimize",
                width = 110,
                tooltip = restore and "Put back your graphics from before optimizing."
                    or "Tune graphics for higher FPS and clarity. Details lists every change.",
                onClick = function()
                    local had = HasGfxBackup()
                    if had then
                        RestoreGfxSettings()
                    else
                        ApplyOptimizedGfx()
                    end
                    if HasGfxBackup() ~= had then CUI:RefreshPage(true) end
                end,
            }, {
                type = "labeledButton",
                text = "What Optimize Changes",
                buttonText = "Details",
                width = 110,
                tooltip = "Every graphics setting Optimize My FPS and Graphics changes, and why.",
                onClick = ShowOptimizeInfo,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Reset CUI Module Settings",
                buttonText = "Reset",
                width = 110,
                tooltip = "Pick a module, or ALL, to return to its defaults.",
                onClick = function()
                    local foci = GetMouseFoci and GetMouseFoci()
                    local anchor = (foci and foci[1]) or (GetMouseFocus and GetMouseFocus()) or UIParent
                    CUI._ShowModuleResetMenu(anchor, ConfirmResetAll)
                end,
            }, {
                type = "labeledButton",
                text = "Uninstall CUI",
                buttonText = "Uninstall",
                width = 110,
                tooltip = "Revert CUI's changes to your game settings, turn it off for every character and reload. Your profiles are kept.",
                onClick = ConfirmUninstall,
            })
            cursorY = cursorY - height
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -------------------------------------------------------------------
        --  DEVELOPER -- both toggles are duplicated in Quality of Life
        --  (Suppress Lua Errors) and Blizzard Skins+ (Spell ID on Tooltip):
        --  hidden here when BOTH modules are loaded, shown if either is missing so the settings stay reachable.
        -------------------------------------------------------------------
        local _devDupesAvailable = C_AddOns
            and C_AddOns.IsAddOnLoaded
            and C_AddOns.IsAddOnLoaded("CludesUIQoL")
            and C_AddOns.IsAddOnLoaded("CludesUIBlizzardSkin")
        if not _devDupesAvailable then
            _, height = W:SectionHeader(hostFrame, "DEVELOPER", cursorY)
            cursorY = cursorY - height

            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Suppress Lua Errors",
                tooltip = "Turns off the game's own Lua error pop-ups. Error addons such as BugSack still catch them.",
                getValue = function() return not (CludesUIDB and CludesUIDB.suppressErrors == false) end,
                setValue = function(val)
                    Account().suppressErrors = val
                    SetCVarSafe("scriptErrors", val and "0" or "1")
                end,
            }, {
                type = "toggle",
                text = "Spell ID on Tooltip",
                tooltip = "Adds the spell ID to spell tooltips.",
                getValue = function() return CUI.SpellIDOn() end,
                setValue = function(val)
                    Account().showSpellID = val
                    -- Engine-side combat aura-ID CVar rides this setting.
                    if CUI.SyncAuraSpellIDCVar then CUI.SyncAuraSpellIDCVar() end
                end,
            })
            cursorY = cursorY - height

            _, height = W:Spacer(hostFrame, cursorY, 20)
            cursorY = cursorY - height
        end

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Re-read live CVars on panel open: widgets call their getter on each build, so a rebuild picks up external changes (addons, /console).
    ---------------------------------------------------------------------------
    CUI:RegisterOnShow(function()
        if CUI:GetActiveModule() == GLOBAL_KEY then CUI:RefreshPage() end
    end)

    ---------------------------------------------------------------------------
    --  Enabled Addons page
    ---------------------------------------------------------------------------

    -- The profiles root (CUI_Profiles_Options.lua) sits on the scroll frame
    -- itself, beside the pages: when another page shows it is hidden and
    -- leaves the scroll frame, and nil marks it as needing a build before it
    -- shows again. The frame stays its builder's (options page pool): the
    -- next build parents it to the scroll frame again and dresses it again.
    local function HideProfilesRoot()
        local root = CUI._profilesRoot
        if root then
            root:Hide()
            root:SetParent(nil)
            CUI._profilesRoot = nil
        end
    end

    -- A profiles root build outside a page pass (a cached page shown again):
    -- the refreshers its previous build registered leave the live list first.
    local function RenderProfilesRoot()
        CUI._BeginRootRender("profilesRoot")
        _G._CUI_BuildProfilesPage(PAGE_PROFILES, nil, -6)
        CUI._EndRootRender("profilesRoot")
    end

    -- Profiles and Patch Notes are their own sidebar pages (registered below), so Global Settings owns General + Style + Fonts + Textures + Glows + Colors + Numbers (Style second, beside General), plus Gamepad while a module it configures is loaded.
    local globalPages =
        { PAGE_GENERAL, PAGE_STYLE, PAGE_FONTS, PAGE_TEXTURES, PAGE_GLOWS, PAGE_COLORS, PAGE_NUMBERS }
    if
        CUI.ModuleNS("CludesUIActionBars")
        or CUI.ModuleNS("CludesUIUnitFrames")
        or CUI.ModuleNS("CludesUIResourceBars")
    then
        globalPages[#globalPages + 1] = PAGE_GAMEPAD
    end

    CUI:RegisterModule(GLOBAL_KEY, {
        title = "Global Settings",
        description = "General options for all CludesUI addons.",
        pages = globalPages,
        buildPage = function(page, hostFrame, yOffset)
            -- CleanupProfilesRoot hides/nils the LIVE _profilesRoot, not anything scoped to this pageName. An off-screen search pre-build
            -- cycles pageName through PAGE_GENERAL/PAGE_FONTS/PAGE_TEXTURES/PAGE_COLORS regardless of what the player has open, so it would yank their real Profiles
            -- page away. This module's config.pages never includes PAGE_PROFILES anyway.
            if CUI._prebuilding then
                if page == PAGE_GENERAL then
                    return BuildGeneralPage(page, hostFrame, yOffset)
                elseif page == PAGE_FONTS then
                    return _G._CUI_BuildFontsPage and _G._CUI_BuildFontsPage(page, hostFrame, yOffset)
                elseif page == PAGE_TEXTURES then
                    return _G._CUI_BuildTexturesPage and _G._CUI_BuildTexturesPage(page, hostFrame, yOffset)
                elseif page == PAGE_GLOWS then
                    return _G._CUI_BuildGlowsPage and _G._CUI_BuildGlowsPage(page, hostFrame, yOffset)
                elseif page == PAGE_GAMEPAD then
                    return _G._CUI_BuildGamepadPage and _G._CUI_BuildGamepadPage(page, hostFrame, yOffset)
                elseif page == PAGE_NUMBERS then
                    return _G._CUI_BuildNumberFormatPage
                        and _G._CUI_BuildNumberFormatPage(page, hostFrame, yOffset)
                elseif page == PAGE_STYLE then
                    return _G._CUI_BuildStylePage and _G._CUI_BuildStylePage(page, hostFrame, yOffset)
                elseif page == PAGE_COLORS then
                    return _G._CUI_BuildColorsPage(page, hostFrame, yOffset)
                elseif page == PAGE_WHATSNEW then
                    return CUI._BuildWhatsNewPage(page, hostFrame, yOffset)
                end
                return
            end
            -- Clean up profiles root when switching to a non-Profiles tab
            if page ~= PAGE_PROFILES then HideProfilesRoot() end
            if page == PAGE_GENERAL then
                return BuildGeneralPage(page, hostFrame, yOffset)
            elseif page == PAGE_FONTS then
                return _G._CUI_BuildFontsPage and _G._CUI_BuildFontsPage(page, hostFrame, yOffset)
            elseif page == PAGE_TEXTURES then
                return _G._CUI_BuildTexturesPage and _G._CUI_BuildTexturesPage(page, hostFrame, yOffset)
            elseif page == PAGE_GLOWS then
                return _G._CUI_BuildGlowsPage and _G._CUI_BuildGlowsPage(page, hostFrame, yOffset)
            elseif page == PAGE_GAMEPAD then
                return _G._CUI_BuildGamepadPage and _G._CUI_BuildGamepadPage(page, hostFrame, yOffset)
            elseif page == PAGE_NUMBERS then
                return _G._CUI_BuildNumberFormatPage
                    and _G._CUI_BuildNumberFormatPage(page, hostFrame, yOffset)
            elseif page == PAGE_STYLE then
                return _G._CUI_BuildStylePage and _G._CUI_BuildStylePage(page, hostFrame, yOffset)
            elseif page == PAGE_COLORS then
                return _G._CUI_BuildColorsPage(page, hostFrame, yOffset)
            elseif page == PAGE_PROFILES then
                return _G._CUI_BuildProfilesPage(page, hostFrame, yOffset)
            elseif page == PAGE_WHATSNEW then
                return CUI._BuildWhatsNewPage(page, hostFrame, yOffset)
            end
        end,
        -- Number Format: the value type picker and preview header, and one search
        -- pre-build per value type (each type's Precision row exists only under it).
        getHeaderBuilder = function(page)
            if page == PAGE_NUMBERS and _G._CUI_NumberFormatHeaderBuilder then
                return _G._CUI_NumberFormatHeaderBuilder()
            end
            return nil
        end,
        getPrebuildVariants = function(page)
            if page == PAGE_NUMBERS and _G._CUI_NumberFormatVariants then
                return _G._CUI_NumberFormatVariants()
            end
            return nil
        end,
        onPageCacheRestore = function(page)
            -- The cached header's preview may predate a profile switch.
            if page == PAGE_NUMBERS and _G._CUI_NumberFormatRefreshHeader then
                _G._CUI_NumberFormatRefreshHeader()
            end
            if page == PAGE_GLOWS then
                -- Glow sites bind per-bar and per-spec tables at build time (CDM bars,
                -- tracking bars); a spec swap or bar change behind a cached page would
                -- leave rows writing into stale tables. Rebuild on every return.
                C_Timer.After(0, function()
                    if CUI:GetActiveModule() == GLOBAL_KEY and CUI:GetActivePage() == PAGE_GLOWS then
                        CUI:RefreshPage(true)
                    end
                end)
            end
            if page ~= PAGE_PROFILES then
                HideProfilesRoot()
            elseif page == PAGE_PROFILES and not CUI._profilesRoot then
                C_Timer.After(0, function()
                    if CUI:GetActiveModule() == GLOBAL_KEY and CUI:GetActivePage() == page then
                        RenderProfilesRoot()
                    end
                end)
            end
        end,
        -- Reset CUI Module Settings: these settings sit on the account.
        resetScope = "account",
        onReset = function()
            -- Reset CVars to CUI preferred defaults (ignoring current state)
            for _, record in ipairs(CUI_DEFAULTS) do
                SetCVarSafe(record[1], record[2])
            end
            -- Reset style/theme settings (accent color, custom theme, class-colored)
            CUI.ResetTheme()
            -- Reset all custom class, power, and resource colors to defaults
            if CludesUIDB then CludesUIDB.customColors = nil end
            -- Reset fonts to defaults
            if CludesUIDB then CludesUIDB.fonts = nil end
            CUI.InvalidateFontCache()
            CUI.ApplyColorsToOUF()
            -- Reset the active profile's Number Format to defaults
            CUI.ResetNumberFormat()
            -- Reset panel scale to 100%
            CUI:SetPanelScale(1.0)
            -- Reset right-click targeting to default (disabled = off)
            if CludesUIDB then
                CludesUIDB.disableRightClickTarget = false
                CludesUIDB.disableRightClickTargetAllyCombat = false
                -- FPS + Secondary Stats are per-profile now; turn them off for the active profile (QoLExtrasSet) so the visible widgets actually clear.
                if CUI.QoLExtrasSet then
                    CUI.QoLExtrasSet("showFPS", false)
                    CUI.QoLExtrasSet("showSecondaryStats", false)
                end
                CludesUIDB.guildChatPrivacy = false
                CludesUIDB.repairWarning = nil
                -- Reset UI scale so next reload re-snapshots from Blizzard default
                CludesUIDB.ppUIScale = nil
                CludesUIDB.ppUIScaleAuto = nil
                -- Developer settings defaults (Spell ID on Tooltip: unset = on)
                CludesUIDB.showSpellID = nil
                if CUI.SyncAuraSpellIDCVar then CUI.SyncAuraSpellIDCVar() end
                CludesUIDB.suppressErrors = true
                CludesUIDB.timerSecondsDown = nil
                -- Crosshair: the root is the inherited global default, reset here (per-profile overrides clear with the profile's own reset).
                -- Root off = profiles without an override inherit "None".
                CludesUIDB.crosshairSize = "None"
                if CUI._applyCrosshair then CUI._applyCrosshair() end
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
            if CUI._applyRightClickTarget then CUI._applyRightClickTarget() end
            CUI._applyHideBlizzardPartyFrame()
            -- One call for both: the FPS readout may be drawn by the Secondary
            -- Stats block, so the two owners have to re-evaluate together.
            if CUI._applyFPSDisplay then
                CUI._applyFPSDisplay()
            elseif CUI._applySecondaryStats then
                CUI._applySecondaryStats()
            end
            if CUI._applyCrosshair then CUI._applyCrosshair() end
            if CUI._applyGuildChatPrivacy then CUI._applyGuildChatPrivacy() end
            -- Apply suppress errors default (on)
            SetCVarSafe("scriptErrors", "0")
            CUI:SelectPage(PAGE_GENERAL)
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
    local function BuildOverridesModeToggle(hostFrame, cursorY)
        -- Wider than the Raid Frames pair (162): "Conditional Overrides" is a longer label than "Custom Buff Display" and must not clip.
        local BTN_W, BTN_H = 180, 31
        local seg = CUI.BuildSegmentedControl({
            parent = hostFrame,
            keys = { "spec", "cond" },
            labels = { spec = "Spec Overrides", cond = "Conditional Overrides" },
            width = BTN_W * 2,
            square = true,
            height = BTN_H,
            getChecked = function(key) return (CUI._overridesTabMode or "spec") == key end,
            onToggle = function(key)
                if (CUI._overridesTabMode or "spec") == key then return end
                CUI._overridesTabMode = key
                -- Forced: the two builders render entirely different rows.
                CUI:RefreshPage(true)
            end,
        })
        seg:SetPoint("TOP", hostFrame, "TOP", 0, cursorY - 14)
        seg:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
        -- 14 above + 15 below the buttons.
        return BTN_H + 29
    end

    -- FULL EXPORT tab: a warning and one button, with its own exporter (CludesUI.ExportFullAccountData) sharing NO code path with the
    -- Profiles tab's export flow, so nothing here changes a normal profile string.
    local PAGE_FULLEXPORT = "Full Export"

    local function BuildFullExportPage(hostFrame, yOffset)
        local PAD = CUI.CONTENT_PAD or 40
        local cursorY = yOffset - 10
        local width = hostFrame:GetWidth() - PAD * 2

        -- Warning card (red-bordered, full width).
        local warn = CreateFrame("Frame", nil, hostFrame)
        warn:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", PAD, cursorY)
        warn:SetWidth(width)
        warn:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
        local wbg = CUI.SolidTex(warn, "BACKGROUND", 0.10, 0.04, 0.04, 0.55)
        wbg:SetAllPoints()
        CUI.MakeRoundedBorder(warn, 0.8, 0.2, 0.2, 0.55, wbg)
        local wtext = CUI.MakeFont(warn, 13, nil, 1, 0.55, 0.55, 1)
        wtext:SetPoint("TOPLEFT", warn, "TOPLEFT", 16, -14)
        wtext:SetWidth(width - 32)
        wtext:SetJustifyH("LEFT")
        wtext:SetSpacing(3)
        wtext:SetText(
            CUI.L(
                "This export includes cross profile settings that will overwrite the importing user's settings including Utilities, Frame Bindings and more that should typically not be shared with standard profiles. THIS IS NOT RECOMMENDED for public sharing of profiles."
            )
        )
        warn:SetHeight((wtext:GetStringHeight() or 40) + 28)
        cursorY = cursorY - warn:GetHeight() - 40

        -- Centered export button.
        local BTN_W, BTN_H = 300, 38
        local button = CreateFrame("Button", nil, hostFrame)
        button:SetSize(BTN_W, BTN_H)
        button:SetPoint("TOP", hostFrame, "TOP", 0, cursorY)
        button:SetFrameLevel(hostFrame:GetFrameLevel() + 5)
        local DARK_BG = CUI.DARK_BG
        local bbg = CUI.SolidTex(button, "BACKGROUND", DARK_BG.r, DARK_BG.g, DARK_BG.b, 0.92)
        bbg:SetAllPoints()
        local ACC = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local bbrd = CUI.MakeRoundedBorder(button, ACC.r, ACC.g, ACC.b, 0.5, bbg)
        local blbl = CUI.MakeFont(button, 13, nil, ACC.r, ACC.g, ACC.b, 1)
        blbl:SetAlpha(0.8)
        blbl:SetPoint("CENTER")
        blbl:SetText(CUI.L("Export All Data with Profile"))
        button:SetScript("OnEnter", function()
            blbl:SetAlpha(1)
            if bbrd and bbrd.SetColor then bbrd:SetColor(ACC.r, ACC.g, ACC.b, 0.9) end
        end)
        button:SetScript("OnLeave", function()
            blbl:SetAlpha(0.8)
            if bbrd and bbrd.SetColor then bbrd:SetColor(ACC.r, ACC.g, ACC.b, 0.5) end
        end)
        button:SetScript("OnClick", function()
            local str = CUI.ExportFullAccountData()
            if str then
                CUI:ShowExportPopup(str)
            else
                CUI:ShowInfoPopup({
                    title = CUI.L("Export Failed"),
                    content = CUI.L("Could not build the export string."),
                })
            end
        end)
        cursorY = cursorY - BTN_H - 20

        return -cursorY + 40
    end

    -- Runs the toggle, then the selected mode's builder. Builders return total content height measured from the ORIGINAL page top (they
    -- accumulate from the startY handed in), so the toggle's space is already included.
    local function BuildOverridesPage(hostFrame, yOffset)
        local cursorY = yOffset - BuildOverridesModeToggle(hostFrame, yOffset)
        if (CUI._overridesTabMode or "spec") == "cond" then
            if CUI.Conditions_BuildListPage then return CUI.Conditions_BuildListPage(hostFrame, cursorY) end
        elseif CUI.SpecOverrides_BuildListPage then
            return CUI.SpecOverrides_BuildListPage(hostFrame, cursorY)
        end
        return 200
    end
    CUI:RegisterModule(PROFILES_KEY, {
        title = "Profiles",
        description = "Import, export, and switch CludesUI profiles and presets.",
        pages = { PAGE_PROFILES, PAGE_OVERRIDES, PAGE_FULLEXPORT },
        buildPage = function(page, hostFrame, yOffset)
            -- _G._CUI_BuildProfilesPage bypasses `parent` and builds onto the live shared _scrollFrame, and first checks the active profile against the
            -- current spec -- it can call SwitchProfile/RefreshAllAddons and pop a "Reload Required" confirmation. None of that is safe from a
            -- hidden indexing pass, so skip PAGE_PROFILES; it indexes on the player's first visit.
            if CUI._prebuilding then
                if page == PAGE_OVERRIDES then
                    -- Index the spec list only: the conditional builder is not part of the hidden pre-build pass, and the toggle is chrome.
                    if CUI.SpecOverrides_BuildListPage then
                        return CUI.SpecOverrides_BuildListPage(hostFrame, yOffset)
                    end
                    return 200
                end
                return
            end
            if page == PAGE_OVERRIDES then
                HideProfilesRoot()
                return BuildOverridesPage(hostFrame, yOffset)
            end
            if page == PAGE_FULLEXPORT then
                HideProfilesRoot()
                return BuildFullExportPage(hostFrame, yOffset)
            end
            return _G._CUI_BuildProfilesPage(page, hostFrame, yOffset)
        end,
        onPageCacheRestore = function(page)
            if page == PAGE_FULLEXPORT then
                -- The Profiles page builds onto the SHARED profiles root, which outlives page switches, so a cached Full Export page would show
                -- profiles content layered over it. The page itself is static, so cleanup is enough -- no rebuild.
                HideProfilesRoot()
            elseif page == PAGE_OVERRIDES then
                HideProfilesRoot()
                -- The override list changes while the page is cached; rebuild.
                C_Timer.After(0, function()
                    if CUI:GetActiveModule() == PROFILES_KEY and CUI:GetActivePage() == page then
                        CUI:RefreshPage(true)
                    end
                end)
            elseif not CUI._profilesRoot then
                C_Timer.After(0, function()
                    if CUI:GetActiveModule() == PROFILES_KEY and CUI:GetActivePage() == page then
                        RenderProfilesRoot()
                    end
                end)
            else
                -- Shared root is alive but the Presets tab may have left its subpage showing; the Profiles tab lands on main. An active API
                -- import session wins -- re-enter instead of hiding its page.
                local cfg = CUI._apiImportSession
                if cfg and cfg.state ~= "done" then
                    if CUI._ProfilesConsumeApiImport then CUI._ProfilesConsumeApiImport() end
                elseif CUI._ProfilesResetToMain then
                    CUI._ProfilesResetToMain()
                end
            end
        end,
    })

    -- Patch Notes: its own sidebar module. Suite-only, never registered in
    -- standalone builds.
    if not IS_STANDALONE then
        CUI:RegisterModule(PATCHNOTES_KEY, {
            title = "Patch Notes",
            description = CUI.L("What's new in CludesUI."),
            pages = { PAGE_WHATSNEW },
            buildPage = function(page, hostFrame, yOffset)
                return CUI._BuildWhatsNewPage(page, hostFrame, yOffset)
            end,
        })

        -- Window Scale: the header's panel scale slider, left of the collapse box and
        -- centred on the close X. 5% steps from 75% to 200%: a drag shows its value
        -- live and applies on release, the mouse wheel steps one notch per tick, and
        -- every change glides with the track pinned (SetPanelScale), so the slider
        -- never slides out from under the cursor. Built on the first open.
        local scaleCtl, ScaleCtlRefresh
        local function BuildScaleControl()
            local ca = CUI._clickArea
            if scaleCtl or not ca then return end
            local MIN = CUI.PANEL_SCALE_MIN * 100
            local MAX = CUI.PANEL_SCALE_MAX * 100
            local STEP, TRACK_W, PCT_W = 5, 110, 40
            local ctl = CreateFrame("Frame", nil, ca)
            scaleCtl = ctl
            ctl:SetFrameLevel(ca:GetFrameLevel() + 20)
            ctl:SetHeight(24)
            ctl:SetPoint("RIGHT", ca, "TOPRIGHT", -110, -31)

            local pctFs = CUI.MakeFont(ctl, 13, nil, 1, 1, 1, 0.9)
            pctFs:SetWidth(PCT_W)
            pctFs:SetJustifyH("RIGHT")
            pctFs:SetPoint("RIGHT", ctl, "RIGHT", 0, 0)
            local function ShowPct(val) pctFs:SetText(string.format("%d%%", math.floor(val + 0.5))) end
            local function SavedPct() return ((CludesUIDB and CludesUIDB.panelScale) or 1) * 100 end

            local pending -- the dragged value, shown until the release applies it
            local track, valBox, refresh
            local function Apply(val)
                ShowPct(val)
                if math.abs(val - SavedPct()) < 0.01 then return end
                CUI:SetPanelScale(val / 100, track)
            end
            -- Panel chrome, not page content: the refresh the slider registers
            -- leaves the shown page's refresh list again (ScaleCtlRefresh and the
            -- accent callback below repaint it), so the page's first build
            -- registers what its later builds do.
            local pageRefresh = CUI._widgetRefreshList
            local pageRefreshN = #pageRefresh
            track, valBox, refresh = CUI.BuildSliderCore(
                ctl,
                TRACK_W,
                4,
                12,
                PCT_W,
                20,
                12,
                0.5,
                MIN,
                MAX,
                STEP,
                function() return pending or SavedPct() end,
                function(val)
                    if CUI._sliderDragging then
                        pending = val
                        ShowPct(val)
                        return
                    end
                    pending = nil
                    Apply(val)
                end,
                true
            )
            for idx = #pageRefresh, pageRefreshN + 1, -1 do
                pageRefresh[idx] = nil
            end
            valBox:Hide() -- the plain readout replaces the input box
            track:SetPoint("RIGHT", pctFs, "LEFT", -10, 0)

            local labelText = CUI.MakeFont(ctl, 13, nil, 1, 1, 1, 0.6)
            labelText:SetText(CUI.L("Window Scale"))
            labelText:SetPoint("RIGHT", track, "LEFT", -16, 0)
            -- The whole control takes the wheel; clicks off the track still reach the
            -- click area below (the window drag).
            ctl:SetWidth(PCT_W + 10 + TRACK_W + 16 + labelText:GetStringWidth())
            ctl:EnableMouseWheel(true)
            ctl:SetScript("OnMouseWheel", function(_, delta)
                if CUI._sliderDragging then return end
                if CUI:StepPanelScale(delta, track) then
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
            local PlayGlow = CUI.MakeSettingGlow({ color = CUI.CLUDES_GREEN })
            CUI._FlashWindowScale = function()
                ScaleCtlRefresh()
                PlayGlow(glowHost)
            end
            CUI.RegAccent({
                type = "callback",
                fn = function() refresh() end,
            })
            -- Any scale change (this slider, Reset) lands here once its glide ends.
            if not CUI._onScaleChanged then CUI._onScaleChanged = {} end
            CUI._onScaleChanged[#CUI._onScaleChanged + 1] = function()
                if not CUI._sliderDragging then ScaleCtlRefresh() end
            end
        end
        local function ScaleCtlOnShow()
            if scaleCtl then
                ScaleCtlRefresh()
            else
                BuildScaleControl()
            end
        end
        CUI:RegisterOnShow(ScaleCtlOnShow)
        if CUI._mainFrame and CUI._mainFrame:IsShown() then ScaleCtlOnShow() end
    end

    -- Clean up profiles root when panel closes
    CUI:RegisterOnHide(function() HideProfilesRoot() end)

    -- Clean up profiles root when switching to any module other than Profiles
    if CUI.SelectModule then
        hooksecurefunc(CUI, "SelectModule", function(_, folderName)
            if folderName ~= PROFILES_KEY then HideProfilesRoot() end
        end)
    end

    -- HideAllChildren (every page switch) hides the profiles root too.
    CUI._AddScrollRootHider(HideProfilesRoot)
end)
