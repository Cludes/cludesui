if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CludesUIDataBars: user-created multi-bar engine.
--
-- ENGINE FILE. Owns DB + fresh profile shape (bars array, monotonic never-reused
-- ids); shared infra (fonts, formatters, heartbeat, OOC deferral, frame pool, popup
-- helper, text fit cache); the owned rich tooltip (replaces every GameTooltip call
-- site); the layout solver (auto-fit px + pct weight partition of the remainder); the
-- bar factory (frame, theme -- cui atlas cover-fit / modern flat --, slots, per-block
-- background + hover overlay, teardown); the visibility runtime (multi-select engine
-- + legacy scalar fallback + per-bar mouseover poll proxies); unlock-mode
-- registration (one element per bar, key "EDB_<id>"); and the bar/block CRUD API on
-- `ns` consumed by the options file.
--
-- Block factories (clock, fps, ms, location, coords, gold, xprep, spec,
-- profession, travel, micromenu, currency, spacer) live in
-- Blocks\*.lua (one file per block, shared helpers in Blocks\Shared.lua) and
-- attach themselves to ns.BlockFactories.
--
-- API HANDOFF (everything the options file may call; nothing else):
--   ns.GetProfile() -> profile
--   ns.BarsInOrder() -> ordered array of barCfg (live table; read-only)
--   ns.GetBar(id) -> barCfg | nil
--   ns.CreateBar(templateKey) -> barCfg    "bottom"|"minimapc"|"microstrip"|"empty"
--   ns.DeleteBar(id)                       no confirm (UI confirms)
--   ns.RenameBar(id, name)
--   ns.ApplyBar(id)                        idempotent cfg -> runtime
--   ns.ApplyTheme(id)                      theme-only fast path
--   ns.RequestLayout(id)                   coalesced relayout
--   ns.AddBlock(barId, typeKey) -> blockCfg
--   ns.RemoveBlock(barId, blockId)
--   ns.MoveBlock(barId, blockId, delta)    delta = -1 | 1
--   ns.MoveBlockTo(barId, blockId, index)  drag-reorder commit (pre-removal index)
--   ns.BarSizingMode(barCfg) -> "auto" | "even"
--   ns.EnsureFillBlock(barCfg) -> fill block id (healed to last block)
--   ns.SetFillBlock(barId, blockId)
--   ns.SetCenterBlock(barId, blockId | nil)   Force Centered designation
--   ns.NormalizedShare(barCfg, blockId) -> number
--   ns.SolveLayout(barCfg, L, measureFn) -> segments (pure)
--   ns.GetLiveAutoLength(barId, blockId) -> px | nil
--   ns.BuildCurrencyList() -> values, order
--   ns.BuildLDBList() -> values, order      LibDataBroker sources, by name
--   ns.GetLDB() -> LibDataBroker-1.1 | nil
--   ns.LocationWidthMode(blockSettings) -> "auto" | "manual"
--   ns.LOC_MAX_WIDTH_DEFAULT               Manual-mode width before one is set
--   ns.BlockTextDynamic(blockType) -> r, g, b   state-driven Text Color swatch
--   ns.UpdateAllBarVisibility()
--   ns.MakePreviewBackdrop(host, themeCfg, showBorder)
--   ns.BLOCK_TYPES / ns.BLOCK_DEFAULTS / ns.EDB_VIS_CAPS / ns.EDGE_PAD
--
--  The calls that run the other way (options file -> runtime). Both are
--  defined from the options PLAYER_LOGIN handler, hence the nil guard at
--  their call sites:
--
--   ns.OpenBlockSettings(barId, blockId, settingKey)
--       a block whose empty state invites a click sends the player to the
--       control that fills it in: deep-links to the
--       "block:<blockId>:<settingKey>" click target the options page
--       registers for that row (see _edbClickTargets).
--   ns.OnBarLaidOut(barId)
--       called at the end of every layout pass of a bar: the options page's
--       preview strip re-solves from the block measurements that pass settled.

local ADDON_NAME, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewCombatQueue
        and CludesUI._Pool
        and CludesUI.RequestTimePlayed
        and CludesUI.FormatDuration
        and CludesUI.SetFontFamily
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the Time Played block asks /played through RequestTimePlayed and formats through FormatDuration; the tooltip rows take font families through SetFontFamily)
CludesUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

local WB = CludesUI.Lite.NewAddon("CludesUIDataBars")
mod.WB = WB

-- Localized-ish string table shared with the Blocks\ files (ns.L).
local L = {
    LEFT_CLICK = "|cffFFFFFFLeft Click:|r",
    RIGHT_CLICK = "|cffFFFFFFRight Click:|r",
    MIDDLE_CLICK = "|cffFFFFFFMiddle Click:|r",
    SHIFT_MIDDLE_CLICK = "|cffFFFFFFShift + Middle Click:|r",
    SHIFT_LEFT_CLICK = "|cffFFFFFFShift + Left Click:|r",
    CTRL_LEFT_CLICK = "|cffFFFFFFCtrl + Left Click:|r",
    CTRL_RIGHT_CLICK = "|cffFFFFFFCtrl + Right Click:|r",
    CTRL_SHIFT_RIGHT_CLICK = "|cffFFFFFFCtrl + Shift + Right Click:|r",
    CTRL_ALT_LEFT_CLICK = "|cffFFFFFFCtrl + Alt + Left Click a Name:|r",
    SHIFT_HOVER = "|cffFFFFFFShift + Hover:|r",
    YOU_HAVE_MAIL = "You've Got Mail!",
    SERVER_TIME = "Server time",
    SAVED_INSTANCES = "Saved Raid(s)",
    DAILY_RESET = "Daily reset",
    WEEKLY_RESET = "Weekly reset",
    TOGGLE_CALENDAR = "Toggle Calendar",
    TOGGLE_CLOCK = "Toggle Clock",
    RELOAD_UI = "Reload UI",
    FPS = "FPS",
    HOME = "Home",
    WORLD = "World",
    DOWNLOAD = "Download",
    UPLOAD = "Upload",
    KB_PER_SEC = "KB/s",
    MEMORY_USAGE = "Memory Usage",
    REFRESH_STATS = "Refresh stats / print memory snapshot",
    FORCE_GC = "Force garbage collection",
    GOLD = "Gold",
    SESSION = "Session",
    EARNED = "Earned",
    SPENT = "Spent",
    PROFIT = "Profit",
    DEFICIT = "Deficit",
    TOTAL = "Total",
    WOW_TOKEN = "WoW Token",
    OPEN_BAGS = "Open Bags",
    BAGS = "Bags",
    FREE = "Free",
    OPEN_CURRENCIES = "Open Currencies",
    RESET_SESSION = "Reset Session",
    RESET_ALL_DATA = "Reset All Data",
    REMOVE_CHARACTER = "Remove Character",
    SHOW_EVERY_CHARACTER = "Show Every Character",
    PLUS_N_MORE = "+ %d more",
    TRAVEL_COOLDOWNS = "Travel Cooldowns",
    HEARTHSTONE = "Hearthstone",
    READY = "Ready",
    ON_COOLDOWN = "On Cooldown",
    MYTHIC_TELEPORTS = "Mythic+ Teleports",
    USE_HEARTHSTONE = "Use Hearthstone",
    OTHER_CHARACTERS = "Other Characters",
    RANDOM_HEARTHSTONE = "Random Hearthstone",
    RETURN_FROM_HOME = "Return from Home",
    RETURN_AVAILABLE = "Return available",
    HOME_ALLIANCE = "Home (A)",
    HOME_HORDE = "Home (H)",
    TRAVEL_ARCANTINA = "Arcantina",
    TRAVEL_MOONGLADE = "Moonglade",
    CURRENT_SPEC = "Current Specialization",
    CHANGE_SPEC = "Change Specialization",
    CHANGE_SPEC_SHORT = "Change Spec",
    CHANGE_LOOT_SPEC = "Change Loot Spec",
    OPEN_TALENTS = "Open Talents",
    CANNOT_USE_COMBAT = "Cannot Use While In Combat",
    COMBAT_STATUS = "Combat Status",
    IN_COMBAT = "In Combat",
    OUT_OF_COMBAT = "Out of Combat",
    AUDIO = "Audio",
    AUDIO_MASTER = "Master",
    AUDIO_SFX = "Sound Effects",
    AUDIO_MUSIC = "Music",
    AUDIO_AMBIENCE = "Ambience",
    AUDIO_DIALOG = "Dialog",
    AUDIO_MUTE_HINT = "Toggle Mute",
    AUDIO_SET_HINT = "Set Volume",
    AUDIO_SCROLL_HINT = "Adjust Volume",
    AUDIO_SHIFT_HINT = "Hold Shift for 10% Steps",
    AUDIO_MUTED = "Muted",
    SCROLL_WHEEL = "|cffFFFFFFScroll:|r",
    DRAG_BAR = "|cffFFFFFFDrag Bar:|r",
    CHANGE_LOADOUT = "Change Loadout",
    OPEN_PROFESSION = "Open Profession",
    OPEN_PROFESSION_BOOK = "Open Profession Book",
    START_CAMPFIRE = "Start a Campfire",
    ACH_POINTS = "Achievement Points",
    DELVE_JOURNEY = "Delver's Journey",
    COMPANION_LEVEL = "Companion Level",
    SELECT_CURRENCY = "Select a currency",
    SELECT_PLUGIN = "Select a plugin",
    OPEN_SETTINGS = "Open Settings",
    CRESTS = "Crests",
    SEASON_MAXIMUM = "Current Season Maximum",
    ILVL = "ILVL",
    ITEM_LEVEL = "Item Level",
    EQUIPPED = "Equipped",
    PVP_ITEM_LEVEL = "PvP Item Level",
    OPEN_CHARACTER = "Open Character Sheet",
    WHISPER = "Whisper",
    WHISPER_BNET = "Whisper BNet",
    INVITE = "Invite",
    NO_FRIENDS_ONLINE = "No friends online",
    NOT_IN_GUILD = "Not in a guild",
    TOGGLE_WORLD_MAP = "Toggle World Map",
    SWITCH_TO_REP = "Switch to Reputation",
    SWITCH_TO_XP = "Switch to Experience",
    PROGRESS = "Progress",
    RESTED = "Rested",
}
mod.L = L

-- Upvalues
local _G = _G
local CreateFrame = CreateFrame
local UIParent = UIParent
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local pairs, ipairs = pairs, ipairs
local type, select = type, select
local pcall = pcall
local wipe = wipe
local format = string.format
local tinsert, tremove = table.insert, table.remove
local tconcat = table.concat
local tsort = table.sort
local floor = math.floor
local upper, min, abs = math.max, math.min, math.abs

local Pix = CludesUI.PP
-- The options page frame pool's table (made by the parent, filled in place when
-- the options addon loads it): read for its Gen at call time.
local POOL = CludesUI._Pool

local MEDIA = "Interface\\AddOns\\CludesUIDataBars\\media\\"
mod.MEDIA = MEDIA
-- The suite's shared micro menu art (CludesUI\media\micromenu\), also used by
-- Quickdraw: the micro menu, bags, gold, location, item level, stats and Great
-- Vault icons.
mod.MICROMENU_MEDIA = "Interface\\AddOns\\CludesUI\\media\\micromenu\\"

-------------------------------------------------------------------------------
--  Defaults (fresh profile shape; the old single-bar keys are abandoned)
-------------------------------------------------------------------------------
local defaultSet = {
    profile = {
        nextBarId = 0, -- monotonic bar id counter; only ever incremented
        bars = {}, -- ordered array of barCfg
    },
}

-------------------------------------------------------------------------------
--  Block type registry
-------------------------------------------------------------------------------
mod.BLOCK_TYPES = {
    { key = "clock", label = "Clock" },
    { key = "fps", label = "FPS" },
    { key = "ms", label = "Latency" },
    { key = "location", label = "Location" },
    { key = "coords", label = "Coordinates" },
    { key = "gold", label = "Gold" },
    { key = "bags", label = "Bags" },
    { key = "durability", label = "Durability" },
    { key = "combat", label = "Combat Status" },
    { key = "xprep", label = "XP / Reputation Bar" },
    { key = "spec", label = "Spec & Loot Spec" },
    { key = "profession", label = "Professions" },
    { key = "profession2", label = "Secondary Professions" },
    { key = "travel", label = "Travel Cooldowns" },
    { key = "micromenu", label = "Micro Menu" },
    { key = "currency", label = "Currency" },
    { key = "crests", label = "Crests" },
    { key = "ilvl", label = "Item Level" },
    { key = "greatvault", label = "Great Vault" },
    {
        key = "mplussummary",
        label = "M+ Summary",
        available = function()
            return CludesUI._MythicRuns ~= nil
        end,
    },
    { key = "timeplayed", label = "Time Played" },
    { key = "audio", label = "Audio" },
    { key = "ldb", label = "Broker Plugin" },
    { key = "spacer", label = "Spacer" },
}

-- The types the picker offers: one with available() only while it answers
-- true (M+ Summary needs Mythic+ Tools loaded). Asked when the picker is built,
-- after login, once every module has loaded. A bar saved with one keeps it.
function mod.OfferedBlockTypes()
    local result = {}
    for _, t in ipairs(mod.BLOCK_TYPES) do
        if not t.available or t.available() then
            result[#result + 1] = t
        end
    end
    return result
end

mod.BLOCK_DEFAULTS = {
    clock = {
        localTime = true,
        twentyFour = true,
        showMail = true,
        showResting = true,
        fontSizeClock = nil,
        fontSizeInfo = nil,
    },
    fps = {},
    ms = { showIcon = false },
    -- widthMode/maxWidth deliberately unset: "auto" is the resolved default
    -- (ns.LocationWidthMode); nil maxWidth marks the width as never chosen,
    -- which the options page pulses about.
    location = { showIcon = true, showSubZone = true },
    coords = { showIcon = true, precision = 0, hideInInstance = true },
    gold = {
        showIcons = true,
        showBagSpace = false,
        showSmall = false,
        coinIcons = false,
        abbreviate = false,
        forceEnglishUnits = false,
    },
    bags = { showIcon = true, value = "free", reagent = false, lowThreshold = 0 },
    durability = { showIcon = true },
    combat = { onlyInCombat = false },
    xprep = { mode = "auto" },
    spec = { showLoadout = true, useUppercase = false },
    profession = {},
    profession2 = {},
    travel = { randomizeHs = true },
    micromenu = {
        disableBlizzardMicroMenu = false,
        hideSocialText = false,
        mainMenuSpacing = 4,
        iconSpacing = 2,
        menu = true,
        guild = true,
        social = true,
        char = true,
        spell = true,
        ach = true,
        quest = true,
        lfg = true,
        pvp = true,
        housing = true,
        journal = true,
        pet = true,
        shop = true,
        help = true,
    },
    currency = { currencyId = nil, showIcon = true, showDescription = true },
    -- t1..t5 are TIER slots, not currency ids: a season swap replaces the ids
    -- in Blocks\Shared.lua (CRESTS) and the player's checklist selection still applies.
    crests = {
        t1 = true,
        t2 = true,
        t3 = true,
        t4 = true,
        t5 = true,
        showIcons = true,
        separator = "slash",
        showSeasonProgress = false,
        hideEmpty = false,
        reverse = false,
    },
    ilvl = { prefix = "short", value = "equipped", precision = 0 },
    greatvault = {},
    mplussummary = { hideWhenEmpty = false },
    timeplayed = { alwaysTotal = false },
    audio = { channel = "master" },
    -- Broker plugin: one block type for every LibDataBroker data source, picked
    -- by name (source). stripColors defaults ON -- broker text arrives full of
    -- the plugin's own |cff.. codes, which would silently beat this block's Text
    -- Color and its accent hover. maxWidth nil = size from the live string.
    ldb = {
        source = nil,
        showIcon = true,
        showLabel = false,
        showText = true,
        stripColors = true,
        maxWidth = nil,
    },
    spacer = {},
}

-- Factories are registered by Blocks\*.lua.
mod.BlockFactories = {}

-- WoW Forever has no Great Vault, no season crests, no Mythic+ Tools runs and
-- one spec per class with nothing to switch: those blocks leave the picker
-- (BLOCK_TYPES), the add path refuses them (no default, so the Bottom Info Bar
-- template skips its spec block) and their Blocks\*.lua files return before
-- registering a factory, so a bar saved with one shows an empty slot there
-- instead of erroring.
if CludesUI.IS_FOREVER then
    local FOREVER_OFF = { greatvault = true, crests = true, spec = true, mplussummary = true }
    table.insert(mod.BLOCK_TYPES, #mod.BLOCK_TYPES, { key = "supplies", label = "Class Resources" })
    mod.BLOCK_DEFAULTS.supplies = { showIcon = true }
    for i = #mod.BLOCK_TYPES, 1, -1 do
        if FOREVER_OFF[mod.BLOCK_TYPES[i].key] then
            table.remove(mod.BLOCK_TYPES, i)
        end
    end
    for key in pairs(FOREVER_OFF) do
        mod.BLOCK_DEFAULTS[key] = nil
    end
end

local DeepCopy = CludesUI.Lite.DeepCopy

-------------------------------------------------------------------------------
--  Profile access
-------------------------------------------------------------------------------
function mod.GetProfile()
    return WB.db and WB.db.profile
end

function mod.BarsInOrder()
    local profile = mod.GetProfile()
    if profile then
        return profile.bars
    end
    return {}
end

function mod.GetBar(ident)
    local profile = mod.GetProfile()
    if not profile then
        return nil
    end
    local barList = profile.bars
    for i = 1, #barList do
        if barList[i].id == ident then
            return barList[i]
        end
    end
    return nil
end

local function GetBlock(barCfg, blockId)
    if not barCfg then
        return nil
    end
    for i = 1, #barCfg.blocks do
        if barCfg.blocks[i].id == blockId then
            return barCfg.blocks[i], i
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Fonts
-------------------------------------------------------------------------------
-- family: the text can show other players' writing (the tooltip rows that list
-- friends and guild members with their names and notes). It takes a font family
-- (CludesUI.SetFontFamily): Cyrillic, Korean and Chinese letters draw in the
-- client's own faces. Every font write to such a string passes family.
function mod.SetFont(fontStr, dim, barCfg, family)
    if not (fontStr and fontStr.SetFont) then
        return
    end
    local filePath = CludesUI.GetFontPath("dataBars")
    local flags = CludesUI.GetFontOutlineFlag()
    local scale = 100
    if barCfg and barCfg.fontScale then
        scale = barCfg.fontScale
    end
    local sz = upper(6, floor((dim or 11) * scale / 100 + 0.5))
    local useShadow = flags == "" and CludesUI.GetFontUseShadow()
    if family then
        -- The family carries the drop shadow.
        CludesUI.SetFontFamily(fontStr, filePath, sz, flags, useShadow and true or false)
        return
    end
    -- SetShadowOffset does not render on 12.x; shadows must ride a FontObject.
    -- Prime BEFORE SetFont -- the inherited shadow survives the typeface call.
    CludesUI.PrimeFontShadow(fontStr, useShadow and true or false)
    fontStr:SetFont(filePath, sz, flags)
end

function mod.GetAccent()
    if CludesUI.GetAccentColor then
        return CludesUI.GetAccentColor()
    end
    local theme = CludesUI.CLUDES_GREEN
    if theme then
        return theme.r, theme.g, theme.b
    end
    return 0.298, 0.788, 0.941
end

-- Colour gradient (bad -> caution -> good)
function mod.SlowColorGradient(perc)
    perc = upper(0, min(1, perc))
    local function smoothstep(t)
        return t * t * (3 - 2 * t)
    end
    if perc < 0.5 then
        local t = smoothstep(perc * 2)
        return 1, t, 0.08 * (1 - t)
    else
        local t = smoothstep((perc - 0.5) * 2)
        return 1, 1, t
    end
end

-- Snap a measurement to an even whole pixel, min 2 (text height rounding).
function mod.SnapToPixelGrid(v)
    local r = floor((v or 0) + 0.5)
    return upper(2, r + (r % 2))
end

-------------------------------------------------------------------------------
--  Money / time formatting (pure)
-------------------------------------------------------------------------------
local DENOMINATIONS = {
    { divisor = 10000, symbol = GOLD_AMOUNT_SYMBOL, color = "|cffe2ac7a" }, -- E2AC7A (user-set; do not "restore" to ffd700)
    { divisor = 100, symbol = SILVER_AMOUNT_SYMBOL, color = "|cffc7c7cf" },
    { divisor = 1, symbol = COPPER_AMOUNT_SYMBOL, color = "|cffed8a3f" }, -- copper-orange
}

-- Coin textures, one per denomination. ":0:0:2:0" is Blizzard's own
-- GetCoinTextureString sizing: 0 height inherits the font, so icons follow the
-- bar's/tooltip's text size. Split per coin on purpose -- GetCoinTextureString welds
-- all three into one string, which cannot be laid out in aligned columns.
local COIN_TEX = {
    "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t",
    "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t",
}
-- Trailer for denomination i: coin texture when Coin Icons is on, else the localized
-- suffix letter (colored on request). Every money renderer routes through this so Coin
-- Icons/Coin Colored/Show Silver&Copper compose identically everywhere --
-- GetCoinTextureString can't, it always emits all three coins welded into one string.
local function CoinMarker(i, coinIcons, coloured)
    if coinIcons then
        return COIN_TEX[i]
    end
    local d = DENOMINATIONS[i]
    if coloured then
        return d.color .. d.symbol .. "|r"
    end
    return d.symbol
end

-- Gold abbreviation (SI units): 284208 -> "284.2K". The breakpoint table and
-- any locale-specific algorithm (e.g. CJK wan/yi grouping) live in the
-- shared CludesUI_NumberFormat.lua, so every module abbreviates the same way.
local function GoldDisplay(val, abbreviate, forceEnglish)
    if abbreviate then
        return CludesUI.AbbreviateNumberFixed(val, forceEnglish)
    end
    return BreakUpLargeNumbers and BreakUpLargeNumbers(val) or tostring(val)
end

-- Money split per denomination: one token per coin, so callers can align them
-- in columns (tooltip) or separate lines (vertical bar) -- a single formatted
-- string can't, since the proportional font makes "9g" and "1 234g" different
-- widths and everything after the first drifts. Buffer is reused;
-- Tip_AddColumns copies it, so one buffer serves all rows. Silver and copper
-- follow showSmall, and always come while there is no gold, as in FormatMoney
-- (an amount under 1 gold never reads a bare 0g).
local _moneyTokens = {}

function mod.MoneyTokens(amount, showSmall, coinIcons, coloured, abbreviate, forceEnglish)
    amount = floor(abs(amount or 0))
    wipe(_moneyTokens)
    local gold = floor(amount / DENOMINATIONS[1].divisor)
    _moneyTokens[1] = GoldDisplay(gold, abbreviate, forceEnglish) .. CoinMarker(1, coinIcons, coloured)
    if showSmall ~= false or gold == 0 then
        local silver = floor((amount % DENOMINATIONS[1].divisor) / DENOMINATIONS[2].divisor)
        _moneyTokens[2] = silver .. CoinMarker(2, coinIcons, coloured)
        _moneyTokens[3] = (amount % DENOMINATIONS[2].divisor) .. CoinMarker(3, coinIcons, coloured)
    end
    return _moneyTokens
end

function mod.FormatMoney(amount, useColors, showSmall, coinIcons, abbreviate, forceEnglish)
    amount = floor(abs(amount or 0))
    local coloured = useColors ~= false
    local parts, foundGold = {}, false
    for i, denom in ipairs(DENOMINATIONS) do
        local val = floor(amount / denom.divisor)
        amount = amount % denom.divisor
        if i == 1 and val > 0 then
            foundGold = true
            parts[#parts + 1] = GoldDisplay(val, abbreviate, forceEnglish)
                .. CoinMarker(i, coinIcons, coloured)
        elseif i > 1 and (not foundGold or showSmall ~= false) and (val > 0 or (i == 3 and #parts == 0)) then
            parts[#parts + 1] = val .. CoinMarker(i, coinIcons, coloured)
        end
    end
    if #parts == 0 then
        return "0" .. CoinMarker(3, coinIcons, coloured)
    end
    return tconcat(parts, " ")
end

-- Reset countdowns for the clock tooltip. SecondsToTime is the client's own duration
-- formatter, so units come out localized. Same call the Minimap module
-- (CUI_Minimap_Tooltips.lua) makes for the weekly reset, so both render identically.
-- Seconds are suppressed above a minute (3 units already covers "2d 5h 30m"); below a
-- minute they're all that's left, so suppressing them there would return "".
function mod.FormatTimeLeft(seconds)
    seconds = floor(seconds or 0)
    return SecondsToTime(seconds, seconds >= 60, nil, 3)
end

function mod.FormatCooldown(cd)
    if cd <= 0 then
        return nil
    end
    cd = floor(cd)
    if cd >= 3600 then
        return format("%d:%02d:%02d", floor(cd / 3600), floor(cd % 3600 / 60), cd % 60)
    end
    return format("%d:%02d", floor(cd / 60), cd % 60)
end

function mod.GetFPSSuffix()
    local s = FPS_ABBR
    if s then
        return s
    end
    return " fps"
end
function mod.GetMSSuffix()
    local s = MILLISECONDS_ABBR
    if s then
        return s
    end
    return " ms"
end

-------------------------------------------------------------------------------
--  Combat deferral (last caller per key wins; runs on regen)
-------------------------------------------------------------------------------
function mod.DeferUntilOOC(key, func)
    if not InCombatLockdown() then
        func()
        return
    end
    mod.CombatQueue.Defer(key, func)
end

-------------------------------------------------------------------------------
--  Shared 1-second heartbeat. Ticker exists only while listeners exist.
--  Keys are instance-scoped ("clock:EDB3_2") so two blocks never collide.
-------------------------------------------------------------------------------
do
    local listeners = {}
    local ticker
    function mod.RegisterHeartbeat(key, func)
        listeners[key] = func
        if not ticker then
            ticker = C_Timer.NewTicker(1, function()
                -- Isolate listeners: one erroring block must not starve the rest.
                for _, callback in pairs(listeners) do
                    local success, err = pcall(callback)
                    if not success then
                        geterrorhandler()(err)
                    end
                end
            end)
        end
    end
    function mod.UnregisterHeartbeat(key)
        listeners[key] = nil
        if ticker and next(listeners) == nil then
            ticker:Cancel()
            ticker = nil
        end
    end
end

-------------------------------------------------------------------------------
--  Frame pool (popup rows). Per-instance pools are built with this too.
-------------------------------------------------------------------------------
function mod.CreateFramePool(frameType, hostFrame, template)
    local pool = { _type = frameType, _parent = hostFrame, _template = template }
    pool._active = {}
    pool._inactive = {}

    function pool:Acquire()
        local f = tremove(self._inactive)
        if not f then
            f = CreateFrame(self._type, nil, self._parent, self._template)
        end
        f:SetParent(self._parent)
        f:Show()
        self._active[#self._active + 1] = f
        return f
    end

    local function ResetPooledFrame(f)
        if not f then
            return
        end
        f:Hide()
        f:ClearAllPoints()
        f:SetParent(pool._parent)
        f:SetAlpha(1)
        f:SetScale(1)
        f:SetWidth(1)
        f:SetHeight(1)
        f:EnableMouse(false)
        f:RegisterForClicks()
        f:SetScript("OnEnter", nil)
        f:SetScript("OnLeave", nil)
        f:SetScript("OnClick", nil)
        f:SetScript("OnMouseDown", nil)
        f:SetScript("OnMouseUp", nil)
        f:SetScript("OnUpdate", nil)
        f:SetScript("OnShow", nil)
        f:SetScript("OnHide", nil)
        if f.GetNormalTexture and f:GetNormalTexture() and f:GetNormalTexture().SetTexture then
            f:GetNormalTexture():SetTexture(nil)
        end
        if f.GetPushedTexture and f:GetPushedTexture() and f:GetPushedTexture().SetTexture then
            f:GetPushedTexture():SetTexture(nil)
        end
        if f.GetHighlightTexture and f:GetHighlightTexture() and f:GetHighlightTexture().SetTexture then
            f:GetHighlightTexture():SetTexture(nil)
        end
        if f.GetDisabledTexture and f:GetDisabledTexture() and f:GetDisabledTexture().SetTexture then
            f:GetDisabledTexture():SetTexture(nil)
        end
        if f.GetCheckedTexture and f:GetCheckedTexture() and f:GetCheckedTexture().SetTexture then
            f:GetCheckedTexture():SetTexture(nil)
        end
        if f.SetButtonState then
            f:SetButtonState("NORMAL")
        end
        if f.SetChecked then
            f:SetChecked(false)
        end
        if f.SetText then
            f:SetText("")
        end
        if f.SetAttribute then
            pcall(f.SetAttribute, f, "type", nil)
            pcall(f.SetAttribute, f, "macrotext", nil)
            pcall(f.SetAttribute, f, "clickbutton", nil)
        end
        if f.GetNumRegions then
            -- select() avoids allocating a throwaway table per released frame.
            for i = 1, f:GetNumRegions() do
                local r = select(i, f:GetRegions())
                if r and r.Hide then
                    r:Hide()
                end
                if r and r.SetAlpha then
                    r:SetAlpha(1)
                end
                if r and r.ClearAllPoints then
                    r:ClearAllPoints()
                end
                if r and r.SetText then
                    r:SetText("")
                end
                if r and r.SetTexture then
                    r:SetTexture(nil)
                end
                if r and r.SetVertexColor then
                    r:SetVertexColor(1, 1, 1, 1)
                end
                if r and r.SetTexCoord then
                    r:SetTexCoord(0, 1, 0, 1)
                end
            end
        end
    end

    function pool:ReleaseAll()
        for i = #self._active, 1, -1 do
            local f = tremove(self._active, i)
            ResetPooledFrame(f)
            self._inactive[#self._inactive + 1] = f
        end
    end

    return pool
end

-------------------------------------------------------------------------------
--  Popup helper: single shared click-catcher closes whichever popup is open.
--  True singleton by design (only one popup open app-wide at a time).
-------------------------------------------------------------------------------
do
    local sharedClickCatcher
    local activePopup

    local function GetClickCatcher()
        if not sharedClickCatcher then
            sharedClickCatcher = CreateFrame("Button", nil, UIParent)
            sharedClickCatcher:SetAllPoints(UIParent)
            sharedClickCatcher:SetFrameStrata("DIALOG")
            sharedClickCatcher:SetFrameLevel(100)
            sharedClickCatcher:Hide()
            sharedClickCatcher:EnableMouse(true)
            sharedClickCatcher:RegisterForClicks("AnyDown", "AnyUp")
            sharedClickCatcher:SetScript("OnClick", function()
                if activePopup and activePopup:IsShown() then
                    activePopup:Hide()
                end
            end)
        end
        return sharedClickCatcher
    end

    function mod.CreatePopupFrame(hostFrame)
        -- House tooltip styling (same recipe as ns.Tip_*'s EnsureTip), NOT
        -- Blizzard's TooltipBackdropTemplate -- must match every other tip.
        local dialog = CreateFrame("Frame", nil, UIParent)
        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(dialog, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        dialog:SetFrameStrata("TOOLTIP")
        dialog:SetClampedToScreen(true)
        dialog:Hide()
        dialog:EnableKeyboard(false)
        dialog:SetToplevel(true)

        local cc = GetClickCatcher()
        dialog._wbClickCatcher = cc
        dialog:SetFrameLevel(cc:GetFrameLevel() + 10)
        dialog:SetScript("OnShow", function(self)
            activePopup = self
            local catcher = self._wbClickCatcher
            -- Hover-driven popups dismiss on mouse-leave instead; arming the
            -- full-screen catcher for them would eat unrelated clicks.
            if catcher and not self._wbNoCatcher then
                catcher:ClearAllPoints()
                catcher:SetAllPoints(UIParent)
                catcher:Show()
                catcher:SetFrameStrata(self:GetFrameStrata())
                catcher:SetFrameLevel(upper(1, self:GetFrameLevel() - 1))
            end
        end)
        dialog:SetScript("OnHide", function(self)
            if activePopup == self then
                activePopup = nil
            end
            local catcher = self._wbClickCatcher
            if catcher and (not activePopup or not activePopup:IsShown()) then
                catcher:Hide()
            end
            if self._wbOnHide then
                self:_wbOnHide()
            end
        end)
        return dialog
    end
end

-------------------------------------------------------------------------------
--  Text fitting helpers + fit cache
-------------------------------------------------------------------------------
function mod.SetWrappedText(fontStr, width, justify)
    if not fontStr then
        return
    end
    fontStr:SetWidth(upper(1, width or 1))
    if fontStr.SetWordWrap then
        fontStr:SetWordWrap(true)
    end
    if fontStr.SetNonSpaceWrap then
        fontStr:SetNonSpaceWrap(true)
    end
    if fontStr.SetJustifyH then
        fontStr:SetJustifyH(justify or "CENTER")
    end
end

function mod.ResetInlineText(fontStr, justify)
    if not fontStr then
        return
    end
    fontStr:SetWidth(0)
    if fontStr.SetWordWrap then
        fontStr:SetWordWrap(false)
    end
    if fontStr.SetNonSpaceWrap then
        fontStr:SetNonSpaceWrap(false)
    end
    if fontStr.SetJustifyH then
        fontStr:SetJustifyH(justify or "LEFT")
    end
end

local _fitCache, _fitCacheCount = {}, 0
local _measureFS
local _fitKeyParts = {}

function mod.MeasureFS()
    if not _measureFS and UIParent then
        _measureFS = UIParent:CreateFontString(nil, "OVERLAY")
    end
    return _measureFS
end

-- FitFontToLines: largest font size in [minSize..startSize] at which every
-- line fits within maxWidth. Cache key includes the bar's font scale so two
-- bars at different scales never share entries.
function mod.FitFontToLines(lines, startSize, minSize, maxWidth, barCfg)
    local fontStr = mod.MeasureFS()
    if not fontStr then
        return startSize
    end
    local width = upper(1, maxWidth or 1)
    local start = startSize or 14
    local floorSize = minSize or upper(8, start - 6)
    local scale = 100
    if barCfg and barCfg.fontScale then
        scale = barCfg.fontScale
    end

    wipe(_fitKeyParts)
    _fitKeyParts[1] = start
    _fitKeyParts[2] = floorSize
    _fitKeyParts[3] = width
    _fitKeyParts[4] = scale
    for i, lineTex in ipairs(lines or {}) do
        _fitKeyParts[i + 4] = lineTex or ""
    end
    local cacheKey = tconcat(_fitKeyParts, "\1")
    local cached = _fitCache[cacheKey]
    if cached then
        return cached
    end

    for dim = start, floorSize, -1 do
        mod.SetFont(fontStr, dim, barCfg)
        local widest = 0
        for _, lineTex in ipairs(lines or {}) do
            fontStr:SetText(lineTex or "")
            local wid = fontStr:GetStringWidth() or 0
            if wid > widest then
                widest = wid
            end
        end
        if widest <= width then
            if _fitCacheCount > 200 then
                _fitCache = {}
                _fitCacheCount = 0
            end
            _fitCache[cacheKey] = dim
            _fitCacheCount = _fitCacheCount + 1
            return dim
        end
    end
    if _fitCacheCount > 200 then
        _fitCache = {}
        _fitCacheCount = 0
    end
    _fitCache[cacheKey] = floorSize
    _fitCacheCount = _fitCacheCount + 1
    return floorSize
end

function mod.WipeFitCache()
    _fitCache = {}
    _fitCacheCount = 0
end

-------------------------------------------------------------------------------
--  Owned rich tooltip (single frame, pooled FontStrings, two columns)
--  Replaces every GameTooltip site in the old module code.
-------------------------------------------------------------------------------
do
    local tipText
    local owner
    local rowList = {} -- rows[i] = { left = fs, right = fs, cols = { fs, ... } }
    local payload = {} -- data[i] = { l, r, lr, lg, lb, rr, rg, rb }
    local dataCount = 0
    local colW = {} -- per-Tip_Show widest token per sub-column
    local PAD = 10
    local ROW_GAP = 3
    local COL_GAP = 18
    local TOKEN_GAP = 8
    local FONT_SIZE = 12
    -- TOOLTIP strata orders purely by frame level, and a frame created straight
    -- under UIParent starts at the bottom of it -- so a plain level let other
    -- tooltips (e.g. a unit tooltip through a bar block) draw over this one.
    -- Sit far above Blizzard's tooltips; overlay hosts stack on top (Tip_Show).
    local TIP_LEVEL = 900

    -- Interactive rows: secure spell buttons overlaid on action rows
    -- (Tip_AddActionDouble). SecureActionButtonTemplate, type="spell" fed a
    -- STATIC INTEGER spellID, attributes written OOC only (same contract as
    -- the QoL teleport prompt). Buttons live on a secure host under UIParent
    -- whose visibility driver yanks them the instant lockdown starts (covers
    -- a tip left open across a pull); the tip keeps no protected children, so
    -- Tip_Hide stays combat-legal. Keep-alive poll lets the cursor travel off
    -- the owner onto the tip to click a row without it closing.
    local actionPool = {}
    local activeActions = 0
    local actionHost -- secure container, built with the first button
    local actionsDirty = false -- a teardown landed in combat; regen finishes it
    local interactive = false
    -- Caller-forced interactive mode (Tip_MarkInteractive): hover-persistent
    -- even when the shown tip has zero clickable rows. Reset per Tip_Begin.
    local forceInteractive = false
    local keepAlive

    -- Plain clickable rows: an insecure Button overlay running a Lua callback
    -- on click (Tip_AddClickable). Used by social/guild member lists, whose
    -- actions (whisper, invite, BNet whisper) are all UNPROTECTED -- unlike
    -- the spell pool above, no secure host or combat handling needed; free
    -- to create/configure in or out of combat.
    local clickPool = {}
    local activeClicks = 0
    -- Row the last Tip_AddClickable/Tip_AddClickableColumns call added: 0 when
    -- that add was dropped or any other row was added since. The only row
    -- Tip_SetRowWheel may attach to.
    local clickRow = 0

    local function EnsureTip()
        if tipText then
            return tipText
        end
        tipText = CreateFrame("Frame", "CludesUIDataBarsTip", UIParent)
        tipText:SetFrameStrata("TOOLTIP")
        tipText:SetFrameLevel(TIP_LEVEL)
        tipText:SetClampedToScreen(true)
        -- Wheel sink: Tip_Show enables it only while a row takes the wheel, so the
        -- gaps between those rows never scroll the camera. Off until then.
        tipText:SetScript("OnMouseWheel", function() end)
        tipText:EnableMouseWheel(false)
        tipText:Hide()
        local backdrop = tipText:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.97)
        if Pix and Pix.CreateBorder then
            Pix.CreateBorder(tipText, 0, 0, 0, 0.9, 1, "OVERLAY", 7)
        end
        return tipText
    end

    local function EnsureRow(i)
        local rowFrame = rowList[i]
        if not rowFrame then
            rowFrame = {}
            rowFrame.left = tipText:CreateFontString(nil, "OVERLAY")
            rowFrame.right = tipText:CreateFontString(nil, "OVERLAY")
            rowFrame.cols = {}
            rowList[i] = rowFrame
        end
        return rowFrame
    end

    local function EnsureCol(rowFrame, c)
        local fontStr = rowFrame.cols[c]
        if not fontStr then
            fontStr = tipText:CreateFontString(nil, "OVERLAY")
            rowFrame.cols[c] = fontStr
        end
        return fontStr
    end

    -- Pooled rows: a row reused with fewer/no sub-columns must not leave
    -- the previous show's token FontStrings on screen.
    local function HideCols(rowFrame, from)
        for c = from, #rowFrame.cols do
            rowFrame.cols[c]:Hide()
        end
    end

    -- Hide/detach every overlay button. PROTECTED (SecureActionButtonTemplate),
    -- so OOC-only: a mid-combat teardown sets the dirty flag and the host's
    -- regen handler finishes it (state driver already pulled the host off
    -- screen, so nothing stays clickable meanwhile).
    local function HideActionButtons()
        if activeActions == 0 and not actionsDirty then
            return
        end
        if InCombatLockdown() then
            actionsDirty = true
            return
        end
        actionsDirty = false
        for i = 1, #actionPool do
            local b = actionPool[i]
            b:Hide()
            b:ClearAllPoints()
            b:SetScript("OnEnter", nil)
            b:SetScript("OnLeave", nil)
        end
        activeActions = 0
    end

    local function EnsureActionHost()
        if actionHost then
            return actionHost
        end
        actionHost =
            CreateFrame("Frame", "CludesUIDataBarsTipActions", UIParent, "SecureHandlerStateTemplate")
        actionHost:SetFrameStrata("TOOLTIP")
        actionHost:SetFrameLevel(TIP_LEVEL + 10)
        actionHost:SetAllPoints(tipText)
        -- No clickable overlays in combat, ever: the driver hides the host
        -- securely the instant lockdown starts and re-shows it on regen for
        -- the next out-of-combat tip.
        RegisterStateDriver(actionHost, "visibility", "[combat] hide; show")
        local regen = CreateFrame("Frame")
        regen:RegisterEvent("PLAYER_REGEN_ENABLED")
        regen:RegisterEvent("PLAYER_REGEN_DISABLED")
        regen:SetScript("OnEvent", function(_, evt)
            if evt == "PLAYER_REGEN_ENABLED" then
                if actionsDirty then
                    HideActionButtons()
                end
                return
            end
            -- REGEN_DISABLED: InCombatLockdown() reports true already, but
            -- protected-frame writes are still legal until this handler returns. A
            -- protected frame left anchored would block tip:SetSize() all fight, firing
            -- ADDON_ACTION_BLOCKED on any plain tooltip hover. Sever the anchor now;
            -- next OOC Tip_Show re-attaches the host.
            actionsDirty = false
            for i = 1, #actionPool do
                local b = actionPool[i]
                b:Hide()
                b:ClearAllPoints()
                b:SetScript("OnEnter", nil)
                b:SetScript("OnLeave", nil)
            end
            activeActions = 0
            actionHost:ClearAllPoints()
        end)
        return actionHost
    end

    -- Grow-only pool; buttons configured fresh each Tip_Show. Creation/
    -- reconfiguration only run OOC (overlay build is combat-skipped), so
    -- secure attribute writes are always legal. House style: white 0.10
    -- wash on hover, HIGHLIGHT layer, no scripts -- shared by both overlay
    -- pools so the two clickable-row kinds always look identical.
    local function AddRowHighlight(b)
        local highlight = b:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0.10)
    end

    local function AcquireActionButton()
        activeActions = activeActions + 1
        local b = actionPool[activeActions]
        if not b then
            b = CreateFrame("Button", nil, EnsureActionHost(), "SecureActionButtonTemplate")
            b:SetFrameLevel(TIP_LEVEL + 10)
            b:EnableMouse(true)
            -- AnyUp only + useOnKeyDown=false: registering both click phases lets
            -- ActionButtonUseKeyDown fire the cast twice, and the second press
            -- cancels the cast the first started (same rule as the travel
            -- block's hearth button).
            b:RegisterForClicks("AnyUp")
            b:SetAttribute("useOnKeyDown", false)
            AddRowHighlight(b)
            -- Default type; the overlay build swaps type/payload per row
            -- (spell rows and toy rows share this pool).
            b:SetAttribute("type", "spell")
            -- Static handler, installed once; pooled reuse only swaps the
            -- action attributes and the hover recolor scripts.
            b:HookScript("PostClick", function()
                mod.Tip_Hide()
            end)
            actionPool[activeActions] = b
        end
        return b
    end

    -- Insecure clickable pool (social/guild rows): callbacks call unprotected
    -- functions only, so no secure host or combat handling needed -- buttons
    -- build/click in any lockdown state.
    local function HideClickButtons()
        if activeClicks == 0 then
            return
        end
        for i = 1, #clickPool do
            local b = clickPool[i]
            b:Hide()
            b:ClearAllPoints()
            b:SetScript("OnClick", nil)
            b:SetScript("OnEnter", nil)
            b:SetScript("OnLeave", nil)
            b:SetScript("OnMouseWheel", nil)
            b:EnableMouseWheel(false)
        end
        activeClicks = 0
    end

    -- Grow-only pool; buttons parent to the tip (riding its strata/clamping)
    -- and sit above its FontStrings so the overlay wins hit testing.
    local function AcquireClickButton()
        activeClicks = activeClicks + 1
        local b = clickPool[activeClicks]
        if not b then
            b = CreateFrame("Button", nil, EnsureTip())
            b:SetFrameLevel(tipText:GetFrameLevel() + 5)
            b:EnableMouse(true)
            b:RegisterForClicks("AnyUp")
            AddRowHighlight(b)
            clickPool[activeClicks] = b
        end
        return b
    end

    -- Lay an overlay button over row i and wire its hover affordance. Shared by
    -- both secure action rows and insecure clickable ones -- to the player
    -- they're the same thing, an interactive tooltip row. The accent recolor
    -- only shows if the row's left text carries no embedded |c..|r codes.
    local function PlaceRowOverlay(b, i, innerW)
        local d, rowFrame = payload[i], rowList[i]
        -- Re-stated per placement, not just at creation: the tip's level can
        -- rise on any Tip_Show, and a pooled button keeping the old base
        -- would sink under the background. Never lowered.
        local wanted = tipText:GetFrameLevel() + 5
        if b:GetFrameLevel() < wanted then
            b:SetFrameLevel(wanted)
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tipText, "TOPLEFT", PAD, d._y)
        b:SetSize(upper(1, innerW), upper(1, d._h))
        local ar, ag, ab = mod.GetAccent()
        local lr, lg, lb = d.lr or 1, d.lg or 1, d.lb or 1
        b:SetScript("OnEnter", function()
            rowFrame.left:SetTextColor(ar, ag, ab, 1)
        end)
        b:SetScript("OnLeave", function()
            rowFrame.left:SetTextColor(lr, lg, lb, 1)
        end)
        b:Show()
    end

    local function StopKeepAlive()
        if keepAlive then
            keepAlive:Cancel()
            keepAlive = nil
        end
    end

    -- Dismiss once the cursor is over neither owner nor tip. IsMouseOver tests
    -- rectangles (ignores overlay buttons), so a clickable row still counts as
    -- "over the tip". Both rects test EXPANDED (the tip sits a 6px gap off the
    -- bar; unexpanded would drop the tip crossing that dead zone). Two-tick
    -- grace (~0.2s) covers slow diagonal exits past a corner.
    local KA_SLACK = 12
    local function StartKeepAlive()
        if keepAlive then
            return
        end
        local missed = 0
        keepAlive = C_Timer.NewTicker(0.1, function()
            if not (tipText and tipText:IsShown()) then
                StopKeepAlive()
                return
            end
            local overOwner = owner
                and owner.IsMouseOver
                and owner:IsMouseOver(KA_SLACK, -KA_SLACK, -KA_SLACK, KA_SLACK)
            local overTip = tipText:IsMouseOver(KA_SLACK, -KA_SLACK, -KA_SLACK, KA_SLACK)
            if overOwner or overTip then
                missed = 0
            else
                missed = missed + 1
                if missed >= 2 then
                    mod.Tip_Hide()
                end
            end
        end)
    end

    function mod.Tip_Begin(ownerFrame)
        EnsureTip()
        owner = ownerFrame
        dataCount = 0
        clickRow = 0
        forceInteractive = false
    end

    -- Secret text must never enter a row: SetText would display it, and
    -- Tip_Show sizes via GetStringWidth, which errors on a SECRET-fed
    -- FontString. Rows carrying a secret are dropped here, so the tooltip
    -- shortens instead of erroring. Add functions return true when added.
    function mod.Tip_AddLine(textValue, r, g, b)
        if not tipText then
            return
        end
        clickRow = 0
        if textValue ~= nil and issecretvalue(textValue) then
            return
        end
        -- Fixed UI strings resolve through the shared locale; dynamic content
        -- (names, numbers, already-localized strings) has no key, falls back unchanged.
        textValue = CludesUI.L(textValue)
        dataCount = dataCount + 1
        local d = payload[dataCount]
        if not d then
            d = {}
            payload[dataCount] = d
        end
        d.l = textValue or " "
        d.lr = r
        d.lg = g
        d.lb = b
        d.r = nil
        d.wrap = nil
        d.action = nil
        d.actionToy = nil
        d.actionMacro = nil
        d.actionHouse = nil
        d._padBand = nil
        d.onClick = nil
        d.onWheel = nil
        d.ncols = nil
        return true
    end

    -- Long prose (currency descriptions etc.): word-wraps at maxWidth px
    -- instead of blowing the tooltip out to the widest single line.
    function mod.Tip_AddWrappedLine(textValue, maxWidth, r, g, b)
        if not tipText then
            return
        end
        if mod.Tip_AddLine(textValue, r, g, b) then
            payload[dataCount].wrap = maxWidth or 280
        end
    end

    function mod.Tip_AddDouble(leftX, right, lr, lg, lb, rr, rg, rb)
        if not tipText then
            return
        end
        clickRow = 0
        if (leftX ~= nil and issecretvalue(leftX)) or (right ~= nil and issecretvalue(right)) then
            return
        end
        leftX = CludesUI.L(leftX)
        right = CludesUI.L(right) -- see Tip_AddLine
        dataCount = dataCount + 1
        local d = payload[dataCount]
        if not d then
            d = {}
            payload[dataCount] = d
        end
        d.l = leftX or " "
        d.lr = lr
        d.lg = lg
        d.lb = lb
        d.r = right or ""
        d.rr = rr
        d.rg = rg
        d.rb = rb
        d.wrap = nil
        d.action = nil
        d.actionToy = nil
        d.actionMacro = nil
        d.actionHouse = nil
        d._padBand = nil
        d.onClick = nil
        d.onWheel = nil
        d.ncols = nil
        return true
    end

    -- Like Tip_AddDouble, but the right side is tokens in pixel-aligned
    -- sub-columns instead of one right-aligned string -- a single string can't
    -- line up vertically since the proportional font makes "+10" and "0/4"
    -- different widths. Tokens carry their own inline color codes; the array
    -- is copied, so callers may reuse one buffer for every row.
    function mod.Tip_AddColumns(leftX, tokens, lr, lg, lb)
        if not tipText then
            return
        end
        clickRow = 0
        if leftX ~= nil and issecretvalue(leftX) then
            return
        end
        local num = (tokens and #tokens) or 0
        for i = 1, num do
            if issecretvalue(tokens[i]) then
                return
            end
        end
        dataCount = dataCount + 1
        local d = payload[dataCount]
        if not d then
            d = {}
            payload[dataCount] = d
        end
        d.l = leftX or " "
        d.lr = lr
        d.lg = lg
        d.lb = lb
        d.r = nil
        d.wrap = nil
        d.action = nil
        d.actionToy = nil
        d.actionMacro = nil
        d.actionHouse = nil
        d._padBand = nil
        d.onClick = nil
        d.onWheel = nil
        -- nil, never 0: Tip_Show tests `if d.ncols`, and 0 is true in Lua, so a
        -- token-less row would reserve the right column and pad the tip by
        -- COL_GAP for content that never renders.
        d.ncols = num > 0 and num or nil
        if num > 0 then
            local c = d.cols
            if not c then
                c = {}
                d.cols = c
            end
            for i = 1, num do
                c[i] = tokens[i]
            end
        end
        return true
    end

    -- Click-to-cast row: like Tip_AddDouble, but Tip_Show overlays a secure
    -- spell button and keeps the tip alive while hovered. spellID MUST be a
    -- static integer (never API-derived or secret-capable -- same contract as
    -- the QoL teleport prompt). Degrades to a plain double line in combat.
    function mod.Tip_AddActionDouble(leftX, right, spellId, lr, lg, lb, rr, rg, rb)
        if mod.Tip_AddDouble(leftX, right, lr, lg, lb, rr, rg, rb) and spellId then
            payload[dataCount].action = spellId
        end
    end

    -- Click-to-use TOY row: same overlay/keep-alive/combat-degrade contract as
    -- Tip_AddActionDouble, but fires type="toy" with a STATIC integer toy
    -- itemID (toy effects aren't reliably castable via the spell attribute).
    function mod.Tip_AddToyActionDouble(leftX, right, toyItemID, lr, lg, lb, rr, rg, rb)
        if mod.Tip_AddDouble(leftX, right, lr, lg, lb, rr, rg, rb) and toyItemID then
            payload[dataCount].actionToy = toyItemID
        end
    end

    -- Click-to-run MACRO row: same overlay/degrade contract. macrotext MUST be built
    -- from static ids only (e.g. "/use item:NNNN") -- never API-derived strings.
    function mod.Tip_AddMacroActionDouble(leftX, right, macrotext, lr, lg, lb, rr, rg, rb)
        if mod.Tip_AddDouble(leftX, right, lr, lg, lb, rr, rg, rb) and macrotext then
            payload[dataCount].actionMacro = macrotext
        end
    end

    -- Click-to-teleport HOUSE row: same overlay/degrade contract. house is a HouseInfo
    -- whose GUIDs the caller checked are not secret; returnTrip fires returnhome instead.
    function mod.Tip_AddHouseActionDouble(leftX, right, house, returnTrip, lr, lg, lb, rr, rg, rb)
        if mod.Tip_AddDouble(leftX, right, lr, lg, lb, rr, rg, rb) and house then
            payload[dataCount].actionHouse = { house = house, returnTrip = returnTrip }
        end
    end

    -- Mark the row just added to carry the clickable-row padding band even
    -- without an action, so a row's spacing stays stable across its
    -- clickable/plain states (e.g. the travel hearthstone line on cooldown).
    function mod.Tip_PadRow()
        if tipText and dataCount > 0 then
            payload[dataCount]._padBand = true
        end
    end

    -- Click-to-act row: like Tip_AddDouble, but overlays an insecure button
    -- running onClick(mouseButton) and keeps the tip alive while hovered.
    -- onClick MUST call unprotected functions only (whisper/invite). Unlike
    -- Tip_AddActionDouble, this stays live in combat.
    function mod.Tip_AddClickable(leftX, right, onClick, lr, lg, lb, rr, rg, rb)
        if mod.Tip_AddDouble(leftX, right, lr, lg, lb, rr, rg, rb) and onClick then
            payload[dataCount].onClick = onClick
            clickRow = dataCount
        end
    end

    -- Tip_AddColumns + Tip_AddClickable: sub-column alignment AND a click
    -- overlay -- combinable since the overlay only covers the row's rect and
    -- never cares how the row was laid out.
    function mod.Tip_AddClickableColumns(leftX, tokens, onClick, lr, lg, lb)
        if mod.Tip_AddColumns(leftX, tokens, lr, lg, lb) and onClick then
            payload[dataCount].onClick = onClick
            clickRow = dataCount
        end
    end

    -- Give the row the immediately preceding Tip_AddClickable (or
    -- Tip_AddClickableColumns) call added a mouse wheel handler, onWheel(delta).
    -- When that add was dropped (secret text) nothing is attached, never a
    -- neighbouring row. Same unprotected-only contract as the onClick.
    function mod.Tip_SetRowWheel(onWheel)
        if clickRow > 0 then
            payload[clickRow].onWheel = onWheel
        end
    end

    function mod.Tip_Show()
        if not tipText or not owner then
            return
        end
        -- Re-check the level contest on every show: GameTooltip's level is not constant
        -- (Blizzard raises it, addons reparent/restack it), so a level picked once at
        -- creation could be overtaken. Only ever raises -- TIP_LEVEL is the floor.
        do
            local lvl = TIP_LEVEL
            local gt = GameTooltip and GameTooltip.GetFrameLevel and GameTooltip:GetFrameLevel()
            if gt and gt >= lvl then
                lvl = gt + 10
            end
            if tipText:GetFrameLevel() < lvl then
                tipText:SetFrameLevel(lvl)
            end
        end
        local maxLeft, maxRight, totalH = 0, 0, 0
        local anyRight = false
        local colCount = 0
        -- Wrapped rows (prose: currency descriptions) are measured but NOT laid
        -- out here -- they own the whole inner width, but that width is only
        -- known once rows WITH a right column are measured. Sizing against
        -- their own wrap cap here instead would leave a dead gutter beside
        -- the prose as wide as the widest right value.
        local maxWrap, anyWrap = 0, false
        wipe(colW)
        for i = 1, dataCount do
            local d = payload[i]
            local rowFrame = EnsureRow(i)
            -- Both columns can list players (friends, guild members, their
            -- notes, the account's characters): font families.
            mod.SetFont(rowFrame.left, FONT_SIZE, nil, true)
            -- The right FS needs a font even on left-only rows: SetText("") on a
            -- never-fonted FontString hard-errors, and a pooled row's first use
            -- can be a plain line.
            mod.SetFont(rowFrame.right, FONT_SIZE, nil, true)
            -- Rows are pooled: reset wrap state every pass so a wrapped row
            -- reused as plain measures naturally. Wrapped rows measure
            -- UNWRAPPED here so GetStringWidth reports the natural one-line
            -- width, which the wrap cap is applied to.
            rowFrame.left:SetWordWrap(false)
            rowFrame.left:SetWidth(0)
            rowFrame.left:SetText(d.l)
            rowFrame.left:SetTextColor(d.lr or 1, d.lg or 1, d.lb or 1, 1)
            rowFrame.left:Show()
            local lw = rowFrame.left:GetStringWidth() or 0
            if d.wrap then
                anyWrap = true
                if lw > d.wrap then
                    lw = d.wrap
                end
                if lw > maxWrap then
                    maxWrap = lw
                end
            elseif lw > maxLeft then
                maxLeft = lw
            end
            if d.r then
                anyRight = true
                rowFrame.right:SetText(d.r)
                rowFrame.right:SetTextColor(d.rr or 1, d.rg or 1, d.rb or 1, 1)
                rowFrame.right:Show()
                local rw = rowFrame.right:GetStringWidth() or 0
                if rw > maxRight then
                    maxRight = rw
                end
            else
                rowFrame.right:SetText("")
                rowFrame.right:Hide()
            end
            local colH = 0
            if d.ncols then
                anyRight = true
                if d.ncols > colCount then
                    colCount = d.ncols
                end
                for c = 1, d.ncols do
                    local fontStr = EnsureCol(rowFrame, c)
                    mod.SetFont(fontStr, FONT_SIZE)
                    fontStr:SetWordWrap(false)
                    fontStr:SetWidth(0)
                    fontStr:SetText(d.cols[c])
                    fontStr:Show()
                    local tw = fontStr:GetStringWidth() or 0
                    if tw > (colW[c] or 0) then
                        colW[c] = tw
                    end
                    local th = fontStr:GetStringHeight() or 0
                    if th > colH then
                        colH = th
                    end
                end
            end
            HideCols(rowFrame, (d.ncols or 0) + 1)
            -- Covers whichever of the three row shapes is in play, so a taller
            -- token can't bleed into the next row. Wrapped-row height depends
            -- on final width, so it's filled in below.
            if not d.wrap then
                local hgt = rowFrame.left:GetStringHeight() or FONT_SIZE
                if d.r then
                    local rh = rowFrame.right:GetStringHeight() or 0
                    if rh > hgt then
                        hgt = rh
                    end
                end
                if colH > hgt then
                    hgt = colH
                end
                -- Clickable (or pad-marked) rows carry 2px of breathing room
                -- above and below the text; the padded band is the rect the
                -- overlay button and its hover wash cover.
                if d.action or d.actionToy or d.actionMacro or d.actionHouse or d._padBand then
                    hgt = hgt + 4
                end
                d._h = hgt
            end
        end
        for i = dataCount + 1, #rowList do
            rowList[i].left:Hide()
            rowList[i].right:Hide()
            HideCols(rowList[i], 1)
        end

        -- The sub-column block is as wide as its widest token per column plus
        -- the gaps, and shares the right column with plain right strings.
        local colsW = 0
        for c = 1, colCount do
            colsW = colsW + (colW[c] or 0) + (c > 1 and TOKEN_GAP or 0)
        end
        if colsW > maxRight then
            maxRight = colsW
        end

        local innerW = maxLeft
        if anyRight then
            innerW = maxLeft + COL_GAP + maxRight
        end
        -- Prose spans the whole inner width instead of stopping at the value rows' left
        -- column, wrapping into fewer, fuller lines with no dead gutter. Only widens
        -- the tip when its capped width exceeds what the other rows already need.
        if anyWrap then
            if maxWrap > innerW then
                innerW = maxWrap
            end
            for i = 1, dataCount do
                local d = payload[i]
                if d.wrap then
                    local leftX = rowList[i].left
                    leftX:SetWordWrap(true)
                    leftX:SetWidth(innerW)
                    local hgt = leftX:GetStringHeight() or FONT_SIZE
                    if d.action or d.actionToy or d.actionMacro or d.actionHouse or d._padBand then
                        hgt = hgt + 4
                    end
                    d._h = hgt
                end
            end
        end
        for i = 1, dataCount do
            local d = payload[i]
            d._h = d._h or FONT_SIZE
            totalH = totalH + d._h + (i > 1 and ROW_GAP or 0)
        end

        local wid = innerW + PAD * 2
        local hgt = totalH + PAD * 2
        tipText:SetSize(upper(60, wid), upper(24, hgt))

        local posY = -PAD
        for i = 1, dataCount do
            local d = payload[i]
            local rowFrame = rowList[i]
            -- Text sits 4px into a clickable row's padded band (centered);
            -- d._y keeps the band's top so the overlay covers all of it.
            local ty = posY
            if d.action or d.actionToy or d.actionMacro or d.actionHouse or d._padBand then
                ty = posY - 2
            end
            rowFrame.left:ClearAllPoints()
            rowFrame.left:SetPoint("TOPLEFT", tipText, "TOPLEFT", PAD, ty)
            if d.r then
                rowFrame.right:ClearAllPoints()
                rowFrame.right:SetPoint("TOPRIGHT", tipText, "TOPRIGHT", -PAD, ty)
            end
            if d.ncols then
                -- Walk columns right to left so the block ends flush with the
                -- tip's right edge, where a plain right string would land.
                -- Each token anchors by its own right edge at natural width.
                local offset = PAD
                for c = colCount, 1, -1 do
                    local fontStr = c <= d.ncols and rowFrame.cols[c]
                    if fontStr then
                        fontStr:ClearAllPoints()
                        fontStr:SetPoint("TOPRIGHT", tipText, "TOPRIGHT", -offset, ty)
                    end
                    offset = offset + (colW[c] or 0) + (c > 1 and TOKEN_GAP or 0)
                end
            end
            d._y = posY
            posY = posY - d._h - ROW_GAP
        end

        -- Interactive overlay: one secure spell button per action row, spanning
        -- the full row rect. Skipped in combat (rows degrade to plain text, no
        -- protected touches fire). Rebuilt from scratch each show so a reused
        -- tip never carries stale buttons.
        HideActionButtons()
        interactive = false
        if not InCombatLockdown() then
            for i = 1, dataCount do
                local d = payload[i]
                if d.action or d.actionToy or d.actionMacro or d.actionHouse then
                    interactive = true
                    -- Re-attach the host: REGEN_DISABLED detaches it (and the
                    -- buttons) from the tip at every combat start.
                    if activeActions == 0 then
                        local hostRegion = EnsureActionHost()
                        hostRegion:ClearAllPoints()
                        hostRegion:SetAllPoints(tipText)
                        -- Follow the tip up if it outranked GameTooltip this show.
                        local hw = tipText:GetFrameLevel() + 10
                        if hostRegion:GetFrameLevel() < hw then
                            hostRegion:SetFrameLevel(hw)
                        end
                    end
                    local b = AcquireActionButton()
                    -- Pooled reuse swaps type + payload; the unused payload is
                    -- cleared so a recycled button can never fire a stale one.
                    local hgt = d.actionHouse and not d.actionHouse.returnTrip and d.actionHouse.house
                    b:SetAttribute("house-neighborhood-guid", hgt and hgt.neighborhoodGUID or nil)
                    b:SetAttribute("house-guid", hgt and hgt.houseGUID or nil)
                    b:SetAttribute("house-plot-id", hgt and hgt.plotID or nil)
                    if d.action then
                        b:SetAttribute("type", "spell")
                        b:SetAttribute("spell", d.action)
                        b:SetAttribute("toy", nil)
                        b:SetAttribute("macrotext", nil)
                    elseif d.actionToy then
                        b:SetAttribute("type", "toy")
                        b:SetAttribute("toy", d.actionToy)
                        b:SetAttribute("spell", nil)
                        b:SetAttribute("macrotext", nil)
                    elseif d.actionHouse then
                        b:SetAttribute("type", d.actionHouse.returnTrip and "returnhome" or "teleporthome")
                        b:SetAttribute("spell", nil)
                        b:SetAttribute("toy", nil)
                        b:SetAttribute("macrotext", nil)
                    else
                        b:SetAttribute("type", "macro")
                        b:SetAttribute("macrotext", d.actionMacro)
                        b:SetAttribute("spell", nil)
                        b:SetAttribute("toy", nil)
                    end
                    PlaceRowOverlay(b, i, innerW)
                end
            end
        end

        -- Insecure clickable overlay (social/guild rows): callbacks are
        -- unprotected, so no combat guard. Rebuilt from scratch each show.
        HideClickButtons()
        local anyWheel = false
        for i = 1, dataCount do
            local d = payload[i]
            if d.onClick then
                interactive = true
                local b = AcquireClickButton()
                local cb = d.onClick
                PlaceRowOverlay(b, i, innerW)
                b:SetScript("OnClick", function(_, mouseButton)
                    cb(mouseButton)
                end)
                local wcb = d.onWheel
                if wcb then
                    anyWheel = true
                    b:EnableMouseWheel(true)
                    b:SetScript("OnMouseWheel", function(_, delta)
                        wcb(delta)
                    end)
                end
            end
        end
        -- The tip body swallows the wheel only while a row takes it (see EnsureTip).
        tipText:EnableMouseWheel(anyWheel)

        if forceInteractive then
            interactive = true
        end
        tipText:EnableMouse(interactive)
        if interactive then
            StartKeepAlive()
        else
            StopKeepAlive()
        end

        -- Smart anchoring: opens off the BAR's roomier side (above/below H,
        -- left/right V) with a 6px gap, centered on the hovered block along
        -- the bar axis, clamped to screen. Owner coords convert through
        -- effective scale first since blocks carry their own Content Scale.
        tipText:ClearAllPoints()
        local barFrame = owner:GetParent()
        while barFrame do
            local num = barFrame.GetName and barFrame:GetName()
            if num and num:find("^CludesUIDataBarsBar%d+$") then
                break
            end
            barFrame = barFrame:GetParent()
        end
        local ocx, ocy = owner:GetCenter()
        if barFrame and ocx then
            local os = owner:GetEffectiveScale()
            local ts = tipText:GetEffectiveScale()
            local bcx, bcy = barFrame:GetCenter()
            local bs = barFrame:GetEffectiveScale()
            local uiScale = UIParent:GetEffectiveScale()
            local halfW = UIParent:GetWidth() * uiScale / 2
            local halfH = UIParent:GetHeight() * uiScale / 2
            if barFrame:GetHeight() > barFrame:GetWidth() then
                -- Vertical bar: open toward the roomier horizontal side.
                local oy = (ocy * os - bcy * bs) / ts
                if bcx * bs < halfW then
                    tipText:SetPoint("LEFT", barFrame, "RIGHT", 6, oy)
                else
                    tipText:SetPoint("RIGHT", barFrame, "LEFT", -6, oy)
                end
            else
                local ox = (ocx * os - bcx * bs) / ts
                if bcy * bs < halfH then
                    tipText:SetPoint("BOTTOM", barFrame, "TOP", ox, 6)
                else
                    tipText:SetPoint("TOP", barFrame, "BOTTOM", ox, -6)
                end
            end
        else
            -- Owner not inside a live bar: fall back to above/below by owner's
            -- own screen half.
            local half = UIParent:GetHeight() / 2
            if ocy and ocy < half then
                tipText:SetPoint("BOTTOM", owner, "TOP", 0, 6)
            else
                tipText:SetPoint("TOP", owner, "BOTTOM", 0, -6)
            end
        end
        tipText:Show()
    end

    function mod.Tip_Hide(ownerFrame)
        if not tipText then
            return
        end
        if ownerFrame and owner ~= ownerFrame then
            return
        end
        owner = nil
        HideActionButtons()
        HideClickButtons()
        StopKeepAlive()
        interactive = false
        tipText:EnableMouse(false)
        tipText:EnableMouseWheel(false)
        tipText:Hide()
    end

    -- Owner OnLeave hook: an interactive tip defers to its own keep-alive poll (so the
    -- cursor can move onto it to click a row); a plain tip hides immediately.
    function mod.Tip_HideUnlessInteractive(ownerFrame)
        if not tipText then
            return
        end
        if ownerFrame and owner ~= ownerFrame then
            return
        end
        if interactive then
            return
        end
        mod.Tip_Hide(ownerFrame)
    end

    function mod.Tip_IsOwned(ownerFrame)
        if not tipText then
            return false
        end
        return tipText:IsShown() and owner == ownerFrame
    end

    -- Force the tip into interactive (hover-persistent) mode even with no
    -- clickable row, so OnLeave defers to the keep-alive poll and the cursor
    -- can travel onto the tip to read it. Call between Tip_Begin and Tip_Show.
    function mod.Tip_MarkInteractive()
        forceInteractive = true
    end
end

-------------------------------------------------------------------------------
--  Layout solver (pure)
--
--  Semantics: bar is ALWAYS exactly filled -- segments sum to L, live and
--  preview alike. PER-BAR mode (cfg.sizingMode): "even" = equal share of L,
--  no per-block options. "auto" = content-sized (measured extent + per-side
--  gaps: contentGapL/contentGapR, fallback legacy contentGap then 10;
--  spacers' width IS their two gaps), with ONE Fill Remaining block
--  (cfg.fillBlockId, healed to LAST) absorbing slack so the bar exactly
--  fills (over-full bars scale sized blocks down instead, fill gets 0).
--  Vertical bars: identical solver, L = bar height.
-------------------------------------------------------------------------------
-- Inset between the bar's ends and outermost blocks. ZERO: blocks run flush
-- edge to edge (nonzero pad leaves background visibly past the first/last
-- block). Single tunable ALL layout math derives from.
local EDGE_PAD = 0
mod.EDGE_PAD = EDGE_PAD

-- Per-BAR sizing mode; absent = "auto".
function mod.BarSizingMode(barCfg)
    if barCfg and barCfg.sizingMode == "even" then
        return "even"
    end
    return "auto"
end

-- The auto-mode Fill Remaining block id, healed to the LAST block whenever
-- the stored id is missing or no longer in the bar (removed block, fresh
-- bar). Returns nil only for empty bars.
function mod.EnsureFillBlock(barCfg)
    local blocks = barCfg and barCfg.blocks
    local num = blocks and #blocks or 0
    if num == 0 then
        return nil
    end
    local ident = barCfg.fillBlockId
    if ident ~= nil then
        for i = 1, num do
            if blocks[i].id == ident then
                return ident
            end
        end
    end
    ident = blocks[num].id
    barCfg.fillBlockId = ident
    return ident
end

-- Per-side Auto Sized gaps (leading = left/top, trailing = right/bottom).
-- View over the keys: contentGapL/contentGapR each fall back to the legacy
-- single contentGap (then 10), so old data keeps its symmetric gap.
local function ContentGapsOf(b)
    local baseValue = b.contentGap
    if baseValue == nil then
        baseValue = 10
    end
    local l = b.contentGapL
    if l == nil then
        l = baseValue
    end
    local r = b.contentGapR
    if r == nil then
        r = baseValue
    end
    return l, r
end
mod.ContentGapsOf = ContentGapsOf

-- L = usable content length (px). measure(b) returns the block's live content
-- extent along the bar axis (auto mode only). Every segment carries seg.at
-- (start offset from bar start) as well as seg.px: segments normally chain
-- seamlessly, but a Force Centered block leaves uncovered background beside
-- it, so consumers must position from seg.at, never a running cursor.
function mod.SolveLayout(barCfg, L, measure)
    local segs = {}
    local num = #barCfg.blocks
    if num == 0 then
        return segs
    end

    if mod.BarSizingMode(barCfg) == "even" then
        -- Equal shares among blocks that exist for layout: a collapsed block
        -- (non-spacer measuring 0, e.g. xprep with no XP and no watched
        -- faction) takes no share, same doesn't-exist rule as the auto solver
        -- below. Cumulative rounding telescopes to EXACTLY L.
        local shares, nShare = {}, 0
        for i = 1, num do
            local b = barCfg.blocks[i]
            local hasShare = true
            if b.type ~= "spacer" and measure then
                hasShare = (measure(b) or 0) > 0
            end
            shares[i] = hasShare
            if hasShare then
                nShare = nShare + 1
            end
        end
        if nShare == 0 then
            -- Everything collapsed: fall back to plain equal shares so the
            -- solve stays well-defined.
            nShare = num
            for i = 1, num do
                shares[i] = true
            end
        end
        local prevEdge, k = 0, 0
        for i = 1, num do
            if shares[i] then
                k = k + 1
                local edge = floor(k * L / nShare + 0.5)
                segs[i] = { block = barCfg.blocks[i], at = prevEdge, px = edge - prevEdge }
                prevEdge = edge
            else
                segs[i] = { block = barCfg.blocks[i], at = prevEdge, px = 0 }
            end
        end
        return segs
    end

    -- AUTO: content + per-side gaps everywhere; fill block absorbs the
    -- remainder. Optional Force Centered block (cfg.centerBlockId) pins its
    -- CONTENT at L/2, splitting the solve: blocks before pack LEFT, after
    -- pack RIGHT. Centered block ALSO fill: its slot absorbs the whole middle
    -- span, content pinned via seg.contentShift. Otherwise fill's region
    -- spans edge-to-edge; leftover beside center is plain background.
    local fillId = mod.EnsureFillBlock(barCfg)
    local centerIdx
    do
        local cid = barCfg.centerBlockId
        if cid ~= nil then
            for i = 1, num do
                if barCfg.blocks[i].id == cid then
                    centerIdx = i
                    break
                end
            end
        end
    end

    -- desired slot px for a sized (non-fill) block; also its leading gap
    -- and bare content width (for exact content-centering).
    local function SizedPx(b)
        local wid = 0
        if b.type ~= "spacer" and measure then
            wid = measure(b) or 0
            if wid <= 0 then
                -- Collapsed block (nothing rendered, e.g. xprep with no XP and no
                -- watched faction): contributes nothing, gaps included, as if not
                -- in the bar. Spacers are exempt: their width IS their gaps.
                return 0, 0, 0
            end
        end
        local gl, gr = ContentGapsOf(b)
        return wid + gl + gr, gl, wid
    end

    for i = 1, num do
        local b = barCfg.blocks[i]
        local seg = { block = b, at = 0, px = 0 }
        if b.id == fillId then
            seg.isFill = true
        else
            seg.desired = SizedPx(b)
        end
        segs[i] = seg
    end

    -- Lays a run of segments into [regionStart, regionEnd]: packs left (or
    -- right) with cumulative edge rounding so it telescopes; a fill segment
    -- absorbs the slack so the run spans the region. Bounds may be
    -- fractional; the pinned edge always rounds onto the region bound.
    local function SolveRegion(first, last, regionStart, regionEnd, packRight)
        if first > last then
            return
        end
        local regionLen = regionEnd - regionStart
        if regionLen < 0 then
            regionLen = 0
        end
        local sumFixed, hasFill = 0, false
        for i = first, last do
            if segs[i].isFill then
                hasFill = true
            else
                sumFixed = sumFixed + segs[i].desired
            end
        end
        local scale, fillPx = 1, 0
        if sumFixed > regionLen then
            if sumFixed > 0 then
                scale = regionLen / sumFixed
            end
        elseif hasFill then
            fillPx = regionLen - sumFixed
        end
        if packRight and not hasFill then
            -- Anchor flush to the region's RIGHT edge: cumulate from the
            -- right so the last block's edge lands exactly on regionEnd.
            local cum, prevEdge = 0, 0
            local rEnd = floor(regionEnd + 0.5)
            for i = last, first, -1 do
                cum = cum + segs[i].desired * scale
                local edge = floor(cum + 0.5)
                segs[i].px = edge - prevEdge
                segs[i].at = rEnd - edge
                prevEdge = edge
            end
            return
        end
        local baseValue = floor(regionStart + 0.5)
        local cum, prevEdge = 0, 0
        for i = first, last do
            local s = segs[i]
            local wid
            if s.isFill then
                wid = fillPx
            else
                wid = s.desired * scale
            end
            cum = cum + wid
            local edge = floor(cum + 0.5)
            if hasFill and i == last then
                -- Pin the run's far edge exactly onto the region bound.
                edge = floor(regionEnd + 0.5) - baseValue
            end
            s.px = edge - prevEdge
            s.at = baseValue + prevEdge
            prevEdge = edge
        end
    end

    if not centerIdx then
        SolveRegion(1, num, 0, L, false)
        return segs
    end

    -- Center geometry: the MINIMUM slot spans content + gaps, positioned
    -- so the bare CONTENT midpoint sits at exactly L/2 (gap-aware,
    -- matching the AnchorContent gap stepping).
    local cB = barCfg.blocks[centerIdx]
    local cIsFill = cB.id == fillId
    local cDesired, cGl, cW = SizedPx(cB)
    local cPx = floor(cDesired + 0.5)
    local cAt = floor(L / 2 - cW / 2 - cGl + 0.5)
    if cAt < 0 then
        cAt = 0
    end
    if cAt + cPx > L then
        cAt = floor(upper(0, L - cPx) + 0.5)
    end
    local cSeg = segs[centerIdx]
    cSeg.desired = nil

    SolveRegion(1, centerIdx - 1, 0, cAt, false)
    SolveRegion(centerIdx + 1, num, cAt + cPx, L, true)

    if cIsFill then
        -- Centered fill: slot stretches over the whole middle span (sides packed to the
        -- edges, nothing uncovered); generally asymmetric around L/2, so content pins
        -- to true center via seg.contentShift (consumed by AnchorContent).
        local leftEnd = 0
        if centerIdx > 1 then
            local ls = segs[centerIdx - 1]
            leftEnd = ls.at + ls.px
        end
        local rightStart = floor(L + 0.5)
        if centerIdx < num then
            rightStart = segs[centerIdx + 1].at
        end
        cSeg.isFill = true
        cSeg.at = leftEnd
        cSeg.px = upper(0, rightStart - leftEnd)
        cSeg.contentShift = (L / 2) - (cSeg.at + cSeg.px / 2)
    else
        cSeg.at = cAt
        cSeg.px = cPx
    end
    return segs
end

-------------------------------------------------------------------------------
--  Theme rendering (self-contained window-skin recipe; no BlizzardSkin dep)
--  Three pre-built textures per host, swapped by alpha only:
--    bgAtlas   modern_blizz.png cover-fit          (cui style)
--    bgOverlay black overlay, alpha = theme.cuiAlpha (cui style)
--    modernBg  flat user color                      (modern style)
-------------------------------------------------------------------------------
local BG_ASPECT = 561 / 433
local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T

local function EnsureThemeTextures(hostRegion)
    -- Made once per host. An options preview strip is a frame of the options
    -- page pool that every header build dresses again for another use: the
    -- textures count only for the dress (generation) they were made in. Gen
    -- is nil for every frame the pool did not make (the live bars).
    local gen = POOL.Gen and POOL.Gen(hostRegion)
    if hostRegion._edbBgAtlas and hostRegion._edbThemeGen == gen then
        return
    end
    local bgAtlas = hostRegion:CreateTexture(nil, "BACKGROUND", nil, -8)
    bgAtlas:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    bgAtlas:SetAllPoints(hostRegion)
    local bgOverlay = hostRegion:CreateTexture(nil, "BACKGROUND", nil, -7)
    bgOverlay:SetColorTexture(0, 0, 0, 0.5)
    bgOverlay:SetAllPoints(hostRegion)
    local modernBg = hostRegion:CreateTexture(nil, "BACKGROUND", nil, -7)
    modernBg:SetColorTexture(0.067, 0.067, 0.067, 0.95)
    modernBg:SetAllPoints(hostRegion)
    -- Bar Texture layer: replaces the flat/art background when picked,
    -- tinted by the style's color+opacity knobs.
    local barTex = hostRegion:CreateTexture(nil, "BACKGROUND", nil, -6)
    barTex:SetAllPoints(hostRegion)
    barTex:SetAlpha(0)
    hostRegion._edbBgAtlas = bgAtlas
    hostRegion._edbBgOverlay = bgOverlay
    hostRegion._edbModernBg = modernBg
    hostRegion._edbBarTex = barTex
    hostRegion._edbThemeGen = gen

    -- Cover-fit: crop the atlas so it fills the host without stretching.
    local function UpdateBgTexCoords()
        local fw, fh = hostRegion:GetSize()
        if not fw or fw == 0 or not fh or fh == 0 then
            return
        end
        local fa = fw / fh
        if fa > BG_ASPECT then
            local visV = BASE_V * (BG_ASPECT / fa)
            local trimV = (BASE_V - visV) / 2
            bgAtlas:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
        else
            local visU = BASE_U * (fa / BG_ASPECT)
            local trimU = (BASE_U - visU) / 2
            bgAtlas:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
        end
    end
    hostRegion:HookScript("OnSizeChanged", UpdateBgTexCoords)
    UpdateBgTexCoords()
end

local function ApplyThemeToHost(hostRegion, theme, texKey, showBorder)
    EnsureThemeTextures(hostRegion)
    theme = theme or {}
    -- Bar Texture (per-bar cfg.barTexture): resolved through the shared
    -- key -> path table (built-ins + SharedMedia). nil/"none"/unknown key
    -- falls open to the normal background stack.
    local texPath
    if texKey and texKey ~= "none" and mod.barTextures then
        texPath = mod.barTextures[texKey]
    end
    local op
    if theme.style == "modern" then
        hostRegion._edbBgAtlas:SetAlpha(0)
        hostRegion._edbBgOverlay:SetAlpha(0)
        local c = theme.modernColor or {}
        if texPath then
            -- Tinted by the Modern color; its alpha rides the vertex tint
            -- so Bar Opacity keeps working.
            hostRegion._edbBarTex:SetTexture(texPath)
            hostRegion._edbBarTex:SetVertexColor(c.r or 0.067, c.g or 0.067, c.b or 0.067, c.a or 0.95)
            hostRegion._edbBarTex:SetAlpha(c.a or 0.95)
            hostRegion._edbModernBg:SetAlpha(0)
        else
            hostRegion._edbBarTex:SetAlpha(0)
            hostRegion._edbModernBg:SetColorTexture(c.r or 0.067, c.g or 0.067, c.b or 0.067, c.a or 0.95)
            hostRegion._edbModernBg:SetAlpha(1)
        end
        op = c.a
        if op == nil then
            op = 0.95
        end
    else
        -- cuiOpacity fades the WHOLE background stack (art + dim overlay); cuiAlpha is
        -- the overlay's own darkening amount. Bar Texture never applies here -- the cui
        -- style always renders untextured art (the texture picker is Modern-only).
        op = theme.cuiOpacity
        if op == nil then
            op = 1
        end
        hostRegion._edbBarTex:SetAlpha(0)
        hostRegion._edbBgAtlas:SetAlpha(op)
        hostRegion._edbBgOverlay:SetColorTexture(0, 0, 0, theme.cuiAlpha or 0.5)
        hostRegion._edbBgOverlay:SetAlpha(op)
        hostRegion._edbModernBg:SetAlpha(0)
    end
    -- Bar Opacity carries the border with it: the base border alpha (0.8)
    -- is baked into the strip textures, frame alpha multiplies on top.
    -- SetAlpha is combat-legal even on implicitly protected bars. Off
    -- (cfg.hideBorder == true) zeros it rather than Hide(), same reason.
    if hostRegion._edbBorder then
        if showBorder == false then
            hostRegion._edbBorder:SetAlpha(0)
        else
            hostRegion._edbBorder:SetAlpha(op)
        end
    end
end

-- Exposed so the options preview strip renders the exact same recipe.
function mod.MakePreviewBackdrop(hostRegion, themeCfg, showBorder)
    ApplyThemeToHost(hostRegion, themeCfg, nil, showBorder)
end

-------------------------------------------------------------------------------
--  Live registry + bar factory
-------------------------------------------------------------------------------
local live = {}
mod._live = live
mod._moEligible = {}

-- Hidden park for retired secure frames (never reused, never destroyed).
local parkFrame = CreateFrame("Frame")
parkFrame:Hide()
mod._park = parkFrame

-- Forward declarations
local ApplyLayout
local AfterBarStateChange
local RegisterBarMouseoverProxy

local function MakeBarCtx(ident)
    local context = { id = ident }
    function context.IsVertical()
        local c = context.cfg
        return c ~= nil and c.orientation == "V"
    end
    function context.GetThickness()
        local c = context.cfg
        if c and c.thickness then
            return c.thickness
        end
        return 30
    end
    function context.RequestLayout()
        mod.RequestLayout(ident)
    end
    function context.IsBarAtTop()
        local recd = live[ident]
        if not (recd and recd.bar) then
            return false
        end
        local _, cy = recd.bar:GetCenter()
        if not cy then
            return false
        end
        return cy > (UIParent:GetHeight() / 2)
    end
    return context
end

-- Offset of an anchor point from a rect's BOTTOMLEFT corner.
local function PointXY(anchorPoint, wid, hgt)
    if anchorPoint == "TOPLEFT" then
        return 0, hgt
    end
    if anchorPoint == "TOP" then
        return wid / 2, hgt
    end
    if anchorPoint == "TOPRIGHT" then
        return wid, hgt
    end
    if anchorPoint == "LEFT" then
        return 0, hgt / 2
    end
    if anchorPoint == "RIGHT" then
        return wid, hgt / 2
    end
    if anchorPoint == "BOTTOMLEFT" then
        return 0, 0
    end
    if anchorPoint == "BOTTOM" then
        return wid / 2, 0
    end
    if anchorPoint == "BOTTOMRIGHT" then
        return wid, 0
    end
    return wid / 2, hgt / 2
end

local function ApplyBarPosition(ident)
    local recd = live[ident]
    local conf = mod.GetBar(ident)
    if not (recd and recd.bar and conf) then
        return
    end
    local barFrame = recd.bar
    -- Implicitly protected bar (secure children): reposition is blocked in
    -- combat; keep current position and re-apply once on regen.
    if InCombatLockdown() and barFrame:IsProtected() then
        mod.DeferUntilOOC("pos:" .. ident, function()
            ApplyBarPosition(ident)
        end)
        return
    end
    local vertical = conf.orientation == "V"
    local full = conf.lengthMode == "full"
    local sp = conf.savedPos

    -- Edge snap, ignoring an edge that does not match the orientation
    -- (the options page keeps the setting valid; defense for stale data).
    local edge = conf.snapEdge
    if edge == "none" then
        edge = nil
    end
    if edge then
        if vertical then
            if edge ~= "left" and edge ~= "right" then
                edge = nil
            end
        else
            if edge ~= "bottom" and edge ~= "top" then
                edge = nil
            end
        end
    end

    barFrame:ClearAllPoints()
    if not (full or edge) then
        -- Plain saved position: keep the stored anchor semantics as-is.
        if sp and sp.point then
            barFrame:SetPoint(sp.point, UIParent, sp.relPoint or sp.point, sp.x or 0, sp.y or 0)
        else
            barFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        return
    end

    -- Full-screen length: pin BOTH ends to UIParent so the bar stays exactly
    -- full through resolution/UI-scale changes (a computed-width snapshot
    -- goes stale if taken before final screen metrics land). Only cross-axis
    -- is computed below; ApplyBar's SetSize is a fallback if anchors strip.
    -- Compute the final center ANALYTICALLY, once. Never GetCenter -- if
    -- size/orientation changed earlier this apply, it returns the stale
    -- rect (GetSize is trustworthy since SetSize just ran). Along-axis:
    -- screen-centered when full, else saved position. Cross-axis: flush to
    -- the snapped edge, else saved position.
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local bw, bh = barFrame:GetSize()
    local cx, cy = uw / 2, uh / 2
    if sp and sp.point then
        local rx, ry = PointXY(sp.relPoint or sp.point, uw, uh)
        local px, py = PointXY(sp.point, bw, bh)
        cx = rx + (sp.x or 0) - px + bw / 2
        cy = ry + (sp.y or 0) - py + bh / 2
    end
    if vertical then
        if full then
            cy = uh / 2
        end
        if edge == "left" then
            cx = bw / 2
        elseif edge == "right" then
            cx = uw - bw / 2
        end
    else
        if full then
            cx = uw / 2
        end
        if edge == "bottom" then
            cy = bh / 2
        elseif edge == "top" then
            cy = uh - bh / 2
        end
    end
    if full then
        if vertical then
            barFrame:SetPoint("TOP", UIParent, "TOPLEFT", cx, 0)
            barFrame:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", cx, 0)
        else
            barFrame:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, cy)
            barFrame:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, cy)
        end
    else
        barFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
    end
end

local function EnsureSlot(recd, blockCfg)
    local slotIndex = recd.slots[blockCfg.id]
    if not slotIndex then
        slotIndex = CreateFrame("Frame", nil, recd.bar)
        slotIndex:SetSize(10, 10)
        recd.slots[blockCfg.id] = slotIndex
    end
    if not slotIndex._edbContent then
        local contentFrame = CreateFrame("Frame", nil, slotIndex)
        contentFrame:SetSize(10, 10)
        slotIndex._edbContent = contentFrame
    end
    return slotIndex
end

local function ApplyBlockDecor(slotIndex, blockCfg, barCfg)
    -- Optional block background
    if blockCfg.bg then
        if not slotIndex._edbBg then
            slotIndex._edbBg = slotIndex:CreateTexture(nil, "BACKGROUND", nil, -5)
            slotIndex._edbBg:SetAllPoints(slotIndex)
        end
        local c = blockCfg.bg
        slotIndex._edbBg:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.5)
        slotIndex._edbBg:Show()
    elseif slotIndex._edbBg then
        slotIndex._edbBg:Hide()
    end
    -- Optional hover highlight (4% white), one bar-wide switch. Mouse MOTION
    -- only: clicks pass through to the block's own buttons; off entirely when
    -- disabled (zero cost).
    if barCfg and barCfg.hoverHighlight then
        if not slotIndex._edbHover then
            slotIndex._edbHover = slotIndex:CreateTexture(nil, "OVERLAY", nil, 6)
            slotIndex._edbHover:SetAllPoints(slotIndex)
            slotIndex._edbHover:SetColorTexture(1, 1, 1, 0.04)
            slotIndex._edbHover:Hide()
        end
        if slotIndex.EnableMouseMotion then
            slotIndex:EnableMouseMotion(true)
        end
        slotIndex:SetScript("OnEnter", function(s)
            if s._edbHover then
                s._edbHover:Show()
            end
        end)
        slotIndex:SetScript("OnLeave", function(s)
            if s._edbHover then
                s._edbHover:Hide()
            end
        end)
    else
        if slotIndex._edbHover then
            slotIndex._edbHover:Hide()
        end
        if slotIndex.EnableMouseMotion then
            slotIndex:EnableMouseMotion(false)
        end
        slotIndex:SetScript("OnEnter", nil)
        slotIndex:SetScript("OnLeave", nil)
    end
end

local function AnchorContent(slotIndex, blockCfg, vertical, barCfg)
    local contentFrame = slotIndex._edbContent
    if not contentFrame then
        return
    end
    -- Per-block content scale: the whole content tree (icons + texts) scales
    -- as a group inside its slot. Offsets divide by scale so stored X/Y stay
    -- screen-true regardless.
    local s = (blockCfg.scale or 100) / 100
    if s < 0.25 then
        s = 0.25
    elseif s > 3 then
        s = 3
    end
    contentFrame:SetScale(s)
    contentFrame:ClearAllPoints()
    local a = blockCfg.align or "CENTER"
    local posX = (blockCfg.xOff or 0) / s
    local posY = (blockCfg.yOff or 0) / s
    -- Centered-fill slot: the solver pins CONTENT to the bar's true center via
    -- this along-axis shift (the slot itself is asymmetric). Align is forced
    -- CENTER -- pinning is the whole point.
    local cShift = slotIndex._edbCenterShift
    if cShift then
        a = "CENTER"
        if vertical then
            posY = posY - cShift / s
        else
            posX = posX + cShift / s
        end
    end
    -- Auto-mode slots reserve per-side gaps around content; align steps inward
    -- by the LEADING gap (LEFT otherwise piles the whole reserve on the far
    -- side), CENTER shifts by half the gap DIFFERENCE. Gaps are slot-space px,
    -- so divide by content scale like the offsets. Fill block's slot is the
    -- remainder, not gap-sized: plain align.
    if barCfg and mod.BarSizingMode(barCfg) == "auto" and blockCfg.id ~= mod.EnsureFillBlock(barCfg) then
        local gl, gr = mod.ContentGapsOf(blockCfg)
        gl, gr = gl / s, gr / s
        if vertical then
            if a == "LEFT" then
                posY = posY - gl
            elseif a == "RIGHT" then
                posY = posY + gr
            else
                posY = posY - (gl - gr) / 2
            end
        else
            if a == "LEFT" then
                posX = posX + gl
            elseif a == "RIGHT" then
                posX = posX - gr
            else
                posX = posX + (gl - gr) / 2
            end
        end
    end
    if vertical then
        -- On vertical bars align maps to TOP/CENTER/BOTTOM (same stored keys).
        if a == "LEFT" then
            contentFrame:SetPoint("TOP", slotIndex, "TOP", posX, posY)
        elseif a == "RIGHT" then
            contentFrame:SetPoint("BOTTOM", slotIndex, "BOTTOM", posX, posY)
        else
            contentFrame:SetPoint("CENTER", slotIndex, "CENTER", posX, posY)
        end
    else
        if a == "LEFT" then
            contentFrame:SetPoint("LEFT", slotIndex, "LEFT", posX, posY)
        elseif a == "RIGHT" then
            contentFrame:SetPoint("RIGHT", slotIndex, "RIGHT", posX, posY)
        else
            contentFrame:SetPoint("CENTER", slotIndex, "CENTER", posX, posY)
        end
    end
end

-- Forces every block to fully re-render (inst:Refresh) on the next layout
-- pass by forgetting assigned widths. For options that change how factories
-- anchor internals (e.g. the injected text-only offset), where a plain
-- ApplyBar would see unchanged px and skip.
function mod.ReflowBlocks(ident)
    local recd = live and live[ident]
    if not recd then
        return
    end
    wipe(recd.assigned)
    mod.RequestLayout(ident)
end

-- Coalesced re-layout: one pass per bar per frame at most.
function mod.RequestLayout(ident)
    local recd = live[ident]
    if not recd then
        return
    end
    if recd.layoutQueued then
        return
    end
    recd.layoutQueued = true
    C_Timer.After(0, function()
        local r = live[ident]
        if r then
            r.layoutQueued = false
        end
        ApplyLayout(ident)
    end)
end

ApplyLayout = function(ident)
    local recd = live[ident]
    local conf = mod.GetBar(ident)
    if not (recd and recd.bar and conf) then
        return
    end
    if not recd.enabled then
        return
    end
    -- A bar holding secure children (profession/micromenu passthrough buttons) is
    -- implicitly protected, and so is every ancestor of those buttons: slot geometry on
    -- it is blocked in combat (ADDON_ACTION_BLOCKED on slot:ClearAllPoints). Freeze the
    -- current layout for the fight and run ONE deferred pass on regen.
    if InCombatLockdown() and recd.bar:IsProtected() then
        mod.DeferUntilOOC("layout:" .. ident, function()
            ApplyLayout(ident)
        end)
        return
    end
    local vertical = conf.orientation == "V"
    local barLen
    if vertical then
        barLen = recd.bar:GetHeight()
    else
        barLen = recd.bar:GetWidth()
    end
    local L2 = (barLen or 0) - 2 * EDGE_PAD
    if L2 < 1 then
        L2 = 1
    end

    local function measure(b)
        local instance = recd.insts[b.id]
        if instance and instance.GetAutoLength then
            local wid = instance:GetAutoLength()
            return wid or 0
        end
        return 0
    end

    local segs = mod.SolveLayout(conf, L2, measure)
    for i = 1, #segs do
        local seg = segs[i]
        local slotIndex = recd.slots[seg.block.id]
        if slotIndex then
            local px = seg.px
            if px < 1 then
                px = 1
            end
            -- Positions come from the solver (seg.at), never a running
            -- cursor: a Force Centered block leaves uncovered background
            -- beside it, so segments are not guaranteed contiguous.
            local at = EDGE_PAD + (seg.at or 0)
            slotIndex:ClearAllPoints()
            if vertical then
                slotIndex:SetSize(upper(1, recd.bar:GetWidth()), px)
                slotIndex:SetPoint("TOP", recd.bar, "TOP", 0, -at)
            else
                slotIndex:SetSize(px, upper(1, recd.bar:GetHeight()))
                slotIndex:SetPoint("LEFT", recd.bar, "LEFT", at, 0)
            end
            -- Respect the visibility engine's content gate: a layout pass on
            -- a visibility-hidden bar must not resurrect click-catchers.
            slotIndex:SetShown(recd.contentShown ~= false)
            -- Centered-fill content pinning: re-anchor when the solver's
            -- shift changes (or clears) so the content tracks true center
            -- while its slot spans the whole middle.
            if slotIndex._edbCenterShift ~= seg.contentShift then
                slotIndex._edbCenterShift = seg.contentShift
                AnchorContent(slotIndex, seg.block, vertical, conf)
            end
            -- EVERY block renders INTO its assigned share (sizing is purely
            -- share-based); re-render whenever the assignment changes, e.g.
            -- on a bar resize, so content re-fits its new slot.
            local prev = recd.assigned[seg.block.id]
            if prev == nil or abs(prev - px) > 0.5 then
                recd.assigned[seg.block.id] = px
                local instance = recd.insts[seg.block.id]
                if instance and instance.Refresh then
                    instance:Refresh()
                end
            end
        end
    end
    -- The options page's preview strip solves from these measurements.
    local onLaidOut = mod.OnBarLaidOut
    if onLaidOut then
        onLaidOut(ident)
    end
end

--- "Never" is this module's only disable channel, so every gate that asks it has to ask
--- the EFFECTIVE value: an applied Visibility override replaces the whole setting, the
--- scalar included, so Always or Mouseover has to keep a bar alive whose stored scalar
--- reads never, and an override of Never disables one whose scalar does not.
function mod.VisIsNever(conf)
    if not conf then
        return true
    end
    local shade = CludesUI.VisOverrideValue(conf)
    if shade then
        return shade == "never"
    end
    return conf.visibility == "never"
end

-- Idempotent create-or-update of one bar from its cfg.
function mod.ApplyBar(ident)
    local profile = mod.GetProfile()
    if not profile then
        return
    end
    local conf = mod.GetBar(ident)
    local recd = live[ident]

    -- An existing implicitly-protected bar (secure children) cannot be
    -- sized, positioned, or hidden in combat. Defer the whole apply to
    -- regen; the bar keeps its current state for the fight (runtime
    -- visibility stays alpha-based and unaffected).
    if recd and recd.bar and InCombatLockdown() and recd.bar:IsProtected() then
        mod.DeferUntilOOC("applybar:" .. ident, function()
            mod.ApplyBar(ident)
        end)
        return
    end

    -- "Never" visibility = fully disabled: the bar does NO work (no
    -- instances, no events, no ticks). A stray cfg.enabled key may still
    -- exist in old stored data -- it is deliberately IGNORED everywhere;
    -- visibility is the only disable channel.
    if mod.VisIsNever(conf) then
        if recd and recd.enabled then
            for _, instance in pairs(recd.insts) do
                if instance.Disable then
                    instance:Disable()
                end
            end
            recd.bar:Hide()
            recd.enabled = false
        end
        if AfterBarStateChange then
            AfterBarStateChange()
        end
        return
    end

    if not recd then
        recd = { slots = {}, insts = {}, assigned = {}, enabled = false }
        recd.bar = CreateFrame("Frame", "CludesUIDataBarsBar" .. ident, UIParent)
        recd.bar:SetFrameStrata("MEDIUM")
        recd.bar:SetFrameLevel(10)
        recd.bar:SetMovable(true)
        recd.bar:EnableMouse(false)
        recd.bar:SetClampedToScreen(true)
        recd.bar._edbBorder = Pix.CreateBorder(recd.bar, 0, 0, 0, 0.8, 1, "OVERLAY", 7)
        -- Anchor-driven size changes (full-length bars stretching with the
        -- screen) re-solve the layout; RequestLayout coalesces, and the
        -- combat gate defers protected bars to regen.
        recd.bar:HookScript("OnSizeChanged", function()
            mod.RequestLayout(ident)
        end)
        recd.ctx = MakeBarCtx(ident)
        recd.ctx.frame = recd.bar
        live[ident] = recd
        RegisterBarMouseoverProxy(ident)
    end

    -- Bar Strata (cfg.barStrata, Visibility-row cog). nil = "MEDIUM" (the
    -- hardcoded creation-time value, so an unset bar renders byte-identically).
    -- Applied on EVERY apply, not just creation, so a change lands without a
    -- reload. SetFrameStrata RE-STACKS children's levels too, so they're
    -- re-asserted right after: bar at 10, border at bar + 1 (slots/content
    -- re-stack on their own). Combat-safe: the protected-bar gate above
    -- already returned, so a protected bar never reaches this in lockdown.
    recd.bar:SetFrameStrata(conf.barStrata or "MEDIUM")
    recd.bar:SetFrameLevel(10)
    if recd.bar._edbBorder then
        recd.bar._edbBorder:SetFrameLevel(recd.bar:GetFrameLevel() + 1)
    end

    local wasDisabled = not recd.enabled
    recd.enabled = true
    recd.ctx.cfg = conf

    -- Size (raw px; the border pixel-snaps itself)
    local vertical = conf.orientation == "V"
    local thickness = conf.thickness or 30
    local length
    if conf.lengthMode == "full" then
        if vertical then
            length = UIParent:GetHeight()
        else
            length = UIParent:GetWidth()
        end
    else
        length = conf.length or 400
    end
    if vertical then
        recd.bar:SetSize(thickness, length)
    else
        recd.bar:SetSize(length, thickness)
    end

    ApplyBarPosition(ident)
    -- Back onto its unlock anchor (nil until the unlock core is built).
    if CludesUI.ReapplyUnlockAnchor then
        CludesUI.ReapplyUnlockAnchor("EDB_" .. ident)
    end
    ApplyThemeToHost(recd.bar, conf.theme, conf.barTexture, not conf.hideBorder)

    -- Reconcile block instances against cfg.blocks
    local wanted = {}
    for i = 1, #conf.blocks do
        wanted[conf.blocks[i].id] = conf.blocks[i]
    end
    for blockId, instance in pairs(recd.insts) do
        local b = wanted[blockId]
        if not b or b.type ~= instance._edbType then
            if instance.Disable then
                instance:Disable()
            end
            if instance.Destroy then
                instance:Destroy()
            end
            recd.insts[blockId] = nil
            recd.assigned[blockId] = nil
            local slotIndex = recd.slots[blockId]
            if slotIndex then
                slotIndex:Hide()
                -- The block's frames stay parented to its content, and Destroy
                -- only hides it; a later block with this id (another type, or a
                -- profile switch) would show them again. Retire it so EnsureSlot
                -- builds a fresh one.
                local contentFrame = slotIndex._edbContent
                if contentFrame and not (InCombatLockdown() and contentFrame:IsProtected()) then
                    contentFrame:Hide()
                    slotIndex._edbContent = nil
                end
            end
        end
    end
    for blockId, slotIndex in pairs(recd.slots) do
        if not wanted[blockId] then
            slotIndex:Hide()
        end
    end

    for i = 1, #conf.blocks do
        local b = conf.blocks[i]
        -- A saved block whose type has no factory on this client (a block
        -- from the other client's profile) builds no slot, so it draws no
        -- background or hover region; the layout skips a missing slot.
        if mod.BlockFactories[b.type] then
            local slotIndex = EnsureSlot(recd, b)
            ApplyBlockDecor(slotIndex, b, conf)
            AnchorContent(slotIndex, b, vertical, conf)
            local instance = recd.insts[b.id]
            if not instance then
                local factory = mod.BlockFactories[b.type]
                if factory then
                    instance = factory(b, slotIndex, slotIndex._edbContent, recd.ctx)
                    if instance then
                        instance._edbType = b.type
                        recd.insts[b.id] = instance
                        if instance.Enable then
                            instance:Enable()
                        end
                    end
                end
            elseif wasDisabled then
                -- Re-enabling a previously disabled bar: instance Enable is
                -- idempotent (re-registers events + heartbeat under the same key).
                if instance.Enable then
                    instance:Enable()
                end
            end
        end
    end

    recd.bar:Show()

    for i = 1, #conf.blocks do
        local instance = recd.insts[conf.blocks[i].id]
        if instance and instance.Refresh then
            instance:Refresh()
        end
    end

    mod.RequestLayout(ident)
    if AfterBarStateChange then
        AfterBarStateChange()
    end
    -- Enabled after registration: getFrame was nil, so install the unlock hooks
    -- and bring held followers to the bar.
    if wasDisabled and mod._edbUnlockRegistered then
        mod.RegisterAllUnlockElements()
        if CludesUI.PropagateAnchorChain then
            CludesUI.PropagateAnchorChain("EDB_" .. ident)
        end
    end
end

-- Theme-only fast path (live slider / swatch feedback).
function mod.ApplyTheme(ident)
    local recd = live[ident]
    local conf = mod.GetBar(ident)
    if not (recd and recd.bar and conf) then
        return
    end
    ApplyThemeToHost(recd.bar, conf.theme, conf.barTexture, not conf.hideBorder)
end

function mod.GetLiveAutoLength(barId, blockId)
    local recd = live[barId]
    if not recd then
        return nil
    end
    local instance = recd.insts[blockId]
    if instance and instance.GetAutoLength then
        return instance:GetAutoLength()
    end
    return nil
end

-- Effective share of the TOTAL bar for one block in percentage points,
-- matching SolveLayout. Lives below the live table (unlike the pure solver)
-- since Auto Sized blocks need the real bar length and live content
-- measurements; falls back to configured length for unbuilt bars.
function mod.NormalizedShare(barCfg, blockId)
    if not barCfg or #barCfg.blocks == 0 then
        return 0
    end
    local recd = live[barCfg.id]
    local L
    if recd and recd.bar then
        if barCfg.orientation == "V" then
            L = recd.bar:GetHeight()
        else
            L = recd.bar:GetWidth()
        end
    end
    if not L or L < 2 then
        if barCfg.lengthMode == "full" then
            if barCfg.orientation == "V" then
                L = UIParent:GetHeight()
            else
                L = UIParent:GetWidth()
            end
        else
            L = barCfg.length or 400
        end
    end
    L = L - 2 * EDGE_PAD
    if L < 1 then
        L = 1
    end
    local function measure(b)
        local instance = recd and recd.insts[b.id]
        if instance and instance.GetAutoLength then
            return instance:GetAutoLength() or 0
        end
        return 0
    end
    local segs = mod.SolveLayout(barCfg, L, measure)
    for i = 1, #segs do
        if segs[i].block.id == blockId then
            return segs[i].px * 100 / L
        end
    end
    return 0
end

-------------------------------------------------------------------------------
--  Visibility runtime
--  ERB model: one engine-owned event frame, registered only while at least
--  one enabled bar exists. Mouseover reveal goes through per-bar plain-table
--  poll proxies (never EnableMouse on the real bar).
-------------------------------------------------------------------------------
mod.EDB_VIS_CAPS = { partyIncludesRaid = false, luaDragonriding = true }

-- Bar visibility = ALPHA ONLY. A bar hosting a secure block (micromenu
-- passthrough, travel hearth) is IMPLICITLY PROTECTED: EnableMouse/Show/Hide on it in
-- combat is ADDON_ACTION_BLOCKED (the parent SetElementVisibility helper toggles
-- EnableMouse, so it must never touch these bars). SetAlpha is combat-legal on
-- protected frames, and the bar never has mouse enabled anyway.
local function SetBarAlphaVisible(recd, visible)
    if recd and recd.bar then
        recd.bar:SetAlpha(visible and 1 or 0)
    end
end

-- Alpha alone leaves SECURE travel/micromenu buttons click-interactive while invisible.
-- Slots are OUR insecure frames, so toggling their shown state suppresses every child
-- at once; the bar frame stays shown so the mouseover poll keeps measuring it (layout
-- reads rec.contentShown for the same gate, so relayouts while hidden can't resurrect
-- click-catchers). Slots hosting secure blocks are implicitly protected in combat --
-- those flips defer (rec.contentDeferred) and REGEN_ENABLED re-applies them; alpha 0
-- covers the visual meanwhile, and micromenu buttons self-disable via combatlock.
local function SetBarContentShown(ident, isShown)
    local recd = live[ident]
    if not recd then
        return
    end
    isShown = isShown and true or false
    if (recd.contentShown ~= false) == isShown and not recd.contentDeferred then
        return
    end
    recd.contentShown = isShown
    recd.contentDeferred = nil
    local inCombat = InCombatLockdown()
    local function apply(slotIndex, s)
        if inCombat and slotIndex:IsProtected() then
            recd.contentDeferred = true
        elseif slotIndex:IsShown() ~= s then
            slotIndex:SetShown(s)
        end
    end
    if not isShown then
        for _, slotIndex in pairs(recd.slots) do
            apply(slotIndex, false)
        end
    else
        -- Re-show only the slots belonging to CURRENT blocks; slots orphaned
        -- by block removal stay hidden.
        local conf = recd.ctx and recd.ctx.cfg
        if conf and conf.blocks then
            for i = 1, #conf.blocks do
                local slotIndex = recd.slots[conf.blocks[i].id]
                if slotIndex then
                    apply(slotIndex, true)
                end
            end
        end
    end
end

-- 8 percent white wash on a block's LIVE slot while its settings section is
-- hovered in the options (the options page drives this; nil clears).
local _editHL
function mod.SetBlockEditHighlight(barId, blockId)
    if _editHL then
        local recd = live[_editHL.barId]
        local slotIndex = recd and recd.slots[_editHL.blockId]
        if slotIndex and slotIndex._edbEditHL then
            slotIndex._edbEditHL:Hide()
        end
        _editHL = nil
    end
    if not (barId and blockId) then
        return
    end
    local recd = live[barId]
    local slotIndex = recd and recd.slots[blockId]
    if not slotIndex then
        return
    end
    if not slotIndex._edbEditHL then
        local t = slotIndex:CreateTexture(nil, "OVERLAY", nil, 6)
        t:SetAllPoints(slotIndex)
        t:SetColorTexture(1, 1, 1, 0.15)
        slotIndex._edbEditHL = t
    end
    slotIndex._edbEditHL:Show()
    _editHL = { barId = barId, blockId = blockId }
end

local visRuntime = {}
do
    local visFrame
    local _inCombat = false
    local st = {}

    local VIS_EVENTS = {
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "PLAYER_TARGET_CHANGED",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_MOUNT_DISPLAY_CHANGED",
        "PLAYER_CAN_GLIDE_CHANGED",
        "ZONE_CHANGED_NEW_AREA",
        "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
        "PLAYER_UPDATE_RESTING",
        "UNIT_ENTERED_VEHICLE",
        "UNIT_EXITED_VEHICLE",
    }

    -- Legacy scalar evaluation for the modes the multi engine declines.
    -- in_party and in_raid are disjoint: a raid group only matches in_raid.
    local function LegacyScalar(modeName)
        modeName = modeName or "always"
        if modeName == "always" then
            return true
        end
        if modeName == "never" then
            return false
        end
        if modeName == "mouseover" then
            return "mouseover"
        end
        if modeName == "in_combat" then
            return _inCombat
        end
        if modeName == "out_of_combat" then
            return not _inCombat
        end
        local inRaid = IsInRaid()
        local inGroup = IsInGroup()
        if modeName == "in_raid" then
            return inRaid
        end
        if modeName == "in_party" then
            return inGroup and not inRaid
        end
        if modeName == "solo" then
            return not inGroup
        end
        return true
    end

    function mod.UpdateAllBarVisibility()
        local profile = mod.GetProfile()
        if not profile then
            return
        end
        local barList = profile.bars
        for i = 1, #barList do
            local conf = barList[i]
            local recd = live[conf.id]
            if recd and recd.enabled then
                local vis
                if CludesUI.CheckVisibilityOptions(conf) then
                    vis = false
                else
                    st.inCombat = _inCombat
                    st.inRaid = IsInRaid()
                    st.inParty = (not st.inRaid) and IsInGroup()
                    local ext
                    if CludesUI.EvalVisibilityExtended then
                        ext = CludesUI.EvalVisibilityExtended(conf, "visibility", st, mod.EDB_VIS_CAPS)
                    end
                    if ext ~= nil then
                        vis = ext
                    else
                        vis = LegacyScalar(conf.visibility)
                    end
                end
                if vis == "mouseover" then
                    mod._moEligible[conf.id] = true
                    SetBarAlphaVisible(recd, false)
                    SetBarContentShown(conf.id, false)
                else
                    mod._moEligible[conf.id] = nil
                    SetBarAlphaVisible(recd, vis and true or false)
                    SetBarContentShown(conf.id, vis and true or false)
                end
            else
                mod._moEligible[conf.id] = nil
            end
        end
    end

    local function OnVisEvent(_, evt)
        if evt == "PLAYER_REGEN_DISABLED" then
            _inCombat = true
        elseif evt == "PLAYER_REGEN_ENABLED" then
            _inCombat = false
        elseif evt == "PLAYER_ENTERING_WORLD" then
            _inCombat = InCombatLockdown() and true or false
        end
        mod.UpdateAllBarVisibility()
    end

    local function AnyEnabledBar()
        local profile = mod.GetProfile()
        if not profile then
            return false
        end
        local barList = profile.bars
        for i = 1, #barList do
            if not mod.VisIsNever(barList[i]) then
                return true
            end
        end
        return false
    end

    function visRuntime.UpdateEventRegistration()
        if AnyEnabledBar() then
            if not visFrame then
                visFrame = CreateFrame("Frame")
                visFrame:SetScript("OnEvent", OnVisEvent)
            end
            for _, e in ipairs(VIS_EVENTS) do
                visFrame:RegisterEvent(e)
            end
            if CludesUI._hasGlidingEvent then
                visFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
            end
            _inCombat = InCombatLockdown() and true or false
        elseif visFrame then
            visFrame:UnregisterAllEvents()
        end
    end

    -- Per-bar mouseover poll proxy: plain table, registered once per bar id.
    -- The shared poll only touches the proxy; Show/Hide route through
    -- SetBarAlphaVisible (alpha-only), never EnableMouse on the bar.
    local moRegistered = {}
    RegisterBarMouseoverProxy = function(ident)
        if moRegistered[ident] then
            return
        end
        if not CludesUI.RegisterMouseoverTarget then
            return
        end
        moRegistered[ident] = true
        local proxy = {}
        proxy.GetRect = function()
            local recd = live[ident]
            if recd and recd.bar then
                return recd.bar:GetRect()
            end
            return nil
        end
        proxy.GetEffectiveScale = function()
            local recd = live[ident]
            if recd and recd.bar then
                return recd.bar:GetEffectiveScale()
            end
            return 1
        end
        proxy.SetAlpha = function() end
        proxy.EnableMouse = function() end
        proxy.Show = function()
            local recd = live[ident]
            if recd and recd.bar then
                SetBarAlphaVisible(recd, true)
                SetBarContentShown(ident, true)
            end
        end
        proxy.Hide = function()
            local recd = live[ident]
            if recd and recd.bar then
                SetBarAlphaVisible(recd, false)
                SetBarContentShown(ident, false)
            end
        end
        CludesUI.RegisterMouseoverTarget(proxy, function()
            if mod._moEligible[ident] then
                return true
            end
            return false
        end)
    end
end

-------------------------------------------------------------------------------
--  Display-size events (full-screen-length bars only)
-------------------------------------------------------------------------------
local dispRuntime = {}
do
    local dispFrame

    -- Full-length and edge-snapped bars are placed from UIParent's size.
    local function FollowsScreen(conf)
        return conf.lengthMode == "full" or (conf.snapEdge and conf.snapEdge ~= "none")
    end

    local function AnyScreenBar()
        local profile = mod.GetProfile()
        if not profile then
            return false
        end
        local barList = profile.bars
        for i = 1, #barList do
            if not mod.VisIsNever(barList[i]) and FollowsScreen(barList[i]) then
                return true
            end
        end
        return false
    end

    local function OnDispEvent()
        local profile = mod.GetProfile()
        if not profile then
            return
        end
        mod.WipeFitCache()
        local barList = profile.bars
        for i = 1, #barList do
            if FollowsScreen(barList[i]) then
                mod.ApplyBar(barList[i].id)
            end
        end
    end

    -- UIParent:SetScale (login, scale slider) fires no event: follow its size too.
    -- The two events and the size change all land in one pass on the next frame.
    local sizeQueued
    local function FlushSized()
        sizeQueued = false
        OnDispEvent()
    end
    local function OnUIParentSized()
        if sizeQueued then
            return
        end
        sizeQueued = true
        C_Timer.After(0, FlushSized)
    end

    function dispRuntime.UpdateEventRegistration()
        if AnyScreenBar() then
            if not dispFrame then
                dispFrame = CreateFrame("Frame", nil, UIParent)
                dispFrame:SetAllPoints(UIParent)
                dispFrame:SetScript("OnEvent", OnUIParentSized)
            end
            dispFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
            dispFrame:RegisterEvent("UI_SCALE_CHANGED")
            dispFrame:SetScript("OnSizeChanged", OnUIParentSized)
        elseif dispFrame then
            dispFrame:UnregisterAllEvents()
            dispFrame:SetScript("OnSizeChanged", nil)
        end
    end
end

-- Recompute every cross-cutting gate after any bar state change.
AfterBarStateChange = function()
    visRuntime.UpdateEventRegistration()
    dispRuntime.UpdateEventRegistration()
    mod.UpdateAllBarVisibility()
    if mod.RefreshMicroMenuHider then
        mod.RefreshMicroMenuHider()
    end
end

-------------------------------------------------------------------------------
--  Unlock mode
--  One element per bar, key "EDB_<id>". Elements are NEVER unregistered: a
--  bar deleted mid-session leaves its element with isHidden true / getFrame
--  nil (mover goes dormant, anchors survive); the retired id just is not
--  registered again next login.
-------------------------------------------------------------------------------
local function MakeBarElement(barId, orderIdx)
    local function cfgOf()
        return mod.GetBar(barId)
    end
    local cfgNow = cfgOf()
    local labelText = "DataBar " .. barId
    if cfgNow and cfgNow.name then
        labelText = cfgNow.name
    end
    -- Unlock resize: ApplyBar moved the bar to its stored spot, so return it to
    -- the mover. Snapped and anchored bars keep their edge or link.
    local function holdAtMover(conf)
        if conf.snapEdge and conf.snapEdge ~= "none" then
            return
        end
        local key = "EDB_" .. barId
        if CludesUI._unlockActive and not CludesUI.IsUnlockAnchored(key) then
            CludesUI.RepositionBarToMover(key)
        end
    end
    return CludesUI.MakeUnlockElement({
        key = "EDB_" .. barId,
        label = labelText,
        group = "Info Bar",
        order = 700 + orderIdx,
        -- ApplyBarPosition is the sole position authority: full-screen/edge-snap
        -- recompute the anchor from cfg, so re-applying the stored CENTER
        -- position here would clobber it (a bar switched H->V would re-pin at
        -- the old horizontal center every login/resize). Delegates to
        -- applyPosition instead; mover, save/load, anchors are unaffected.
        noInitHook = true,
        getFrame = function()
            local recd = live[barId]
            local conf = cfgOf()
            if recd and recd.enabled and conf then
                return recd.bar
            end
            return nil
        end,
        getSize = function()
            local recd = live[barId]
            if recd and recd.bar then
                return recd.bar:GetSize()
            end
            return 0, 0
        end,
        savePos = function(_, pt, rpt, posX, posY)
            local conf = cfgOf()
            if not conf then
                return
            end
            local sp = conf.savedPos
            local moved = not (
                sp
                and sp.point == pt
                and (sp.relPoint or sp.point) == rpt
                and sp.x == posX
                and sp.y == posY
            )
            conf.savedPos = { point = pt, relPoint = rpt, x = posX, y = posY }
            -- A real move un-snaps the bar: it is no longer flush to the edge,
            -- so the setting reverting to None reflects reality (and applyPos
            -- would otherwise fight the drag). A Cancel restores the same spot.
            if moved and conf.snapEdge and conf.snapEdge ~= "none" then
                conf.snapEdge = "none"
            end
        end,
        loadPos = function()
            local conf = cfgOf()
            local sp = conf and conf.savedPos
            if not (sp and sp.point) then
                return nil
            end
            return { point = sp.point, relPoint = sp.relPoint, x = sp.x, y = sp.y }
        end,
        clearPos = function()
            local conf = cfgOf()
            if conf then
                conf.savedPos = nil
            end
        end,
        applyPos = function()
            ApplyBarPosition(barId)
        end,
        -- Width/height matches NEVER override full-screen mode on the along-axis:
        -- ApplyAllWidthHeightMatches re-applies stored matches on EVERY login,
        -- so flipping lengthMode to custom here would silently revert a Full
        -- Screen bar every /reload. Full wins; turn Full Screen off first to
        -- use the match. Cross-axis (thickness) always applies.
        setWidth = function(_, wid)
            local conf = cfgOf()
            if not conf then
                return
            end
            wid = floor((wid or 0) + 0.5)
            if wid < 16 then
                wid = 16
            end
            if conf.orientation == "V" then
                conf.thickness = wid
            else
                if conf.lengthMode == "full" then
                    return
                end
                conf.length = wid
            end
            mod.ApplyBar(barId)
            holdAtMover(conf)
        end,
        setHeight = function(_, hgt)
            local conf = cfgOf()
            if not conf then
                return
            end
            hgt = floor((hgt or 0) + 0.5)
            if hgt < 16 then
                hgt = 16
            end
            if conf.orientation == "V" then
                if conf.lengthMode == "full" then
                    return
                end
                conf.length = hgt
            else
                conf.thickness = hgt
            end
            mod.ApplyBar(barId)
            holdAtMover(conf)
        end,
        isHidden = function()
            return cfgOf() == nil
        end,
        allowMatchSource = true,
    })
end

function mod.RegisterAllUnlockElements()
    if not (CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then
        return
    end
    local profile = mod.GetProfile()
    if not profile then
        return
    end
    local elements = {}
    for i = 1, #profile.bars do
        local barId = profile.bars[i].id
        elements[#elements + 1] = MakeBarElement(barId, i)
        -- Cog deep-link: unlock cog on this element opens the DataBars page.
        CludesUI._ELEMENT_SETTINGS_MAP = CludesUI._ELEMENT_SETTINGS_MAP or {}
        CludesUI._ELEMENT_SETTINGS_MAP["EDB_" .. barId] = { module = "CludesUIDataBars", page = "Info Bar" }
    end
    if #elements > 0 then
        CludesUI:RegisterUnlockElements(elements, "CludesUIDataBars")
    end
    mod._edbUnlockRegistered = true
end

-------------------------------------------------------------------------------
--  Templates + CRUD
-------------------------------------------------------------------------------
local TEMPLATES = {
    bottom = {
        -- 40px gaps, coin-colored gold, accent professions (left-aligned), 90% clock
        -- with 12-hour time, random-hearthstone travel block on the right edge.
        name = "Bottom Info Bar",
        orientation = "H",
        lengthMode = "full",
        length = 1200,
        thickness = 30,
        theme = "cui",
        snapEdge = "top",
        sizingMode = "auto",
        fillType = "clock",
        centerType = "clock",
        savedPos = { point = "BOTTOM", relPoint = "BOTTOM", x = 0, y = 0 },
        blocks = {
            {
                type = "micromenu",
                textYOff = 8,
                contentGapR = 40,
                settings = { help = false },
            },
            { type = "xprep", contentGapL = 40, contentGapR = 40 },
            { type = "spec", contentGapL = 40, contentGapR = 40 },
            {
                type = "durability",
                contentGapL = 40,
                contentGapR = 40,
                useIconDefaultColor = true,
                iconColor = { r = 1, g = 0.62, b = 0.25 },
            },
            { type = "clock", scale = 90, settings = { twentyFour = false } },
            {
                type = "profession",
                contentGapL = 40,
                contentGapR = 40,
                align = "LEFT",
                textXOff = 0,
                useIconAccentColor = true,
                iconColor = { r = 1, g = 0.55, b = 0.25 },
            },
            {
                type = "gold",
                contentGapL = 40,
                contentGapR = 40,
                useCoinColor = true,
                coinForced = true,
                useIconDefaultColor = true,
                color = { r = 1, g = 1, b = 1 },
                iconColor = { r = 1, g = 1, b = 1 },
            },
            { type = "fps", contentGapL = 40, contentGapR = 0 },
            { type = "ms", contentGapL = 0, contentGapR = 40 },
            {
                type = "travel",
                align = "RIGHT",
                xOff = -5,
                contentGapL = 40,
                useIconDefaultColor = true,
                iconColor = { r = 0.35, g = 0.72, b = 1 },
                settings = { hsChoice = "random" },
            },
        },
    },
    minimapc = {
        name = "Minimap Companion",
        orientation = "H",
        lengthMode = "custom",
        length = 220,
        thickness = 24,
        theme = "modern",
        sizingMode = "even",
        savedPos = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -4, y = -240 },
        blocks = { { type = "clock" }, { type = "fps" }, { type = "ms" } },
    },
    microstrip = {
        name = "Micro Menu Strip",
        orientation = "H",
        lengthMode = "custom",
        length = 420,
        thickness = 28,
        theme = "modern",
        sizingMode = "auto",
        savedPos = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -4, y = 4 },
        blocks = { { type = "micromenu" } },
    },
    empty = {
        name = "New DataBar",
        orientation = "H",
        lengthMode = "custom",
        length = 400,
        thickness = 30,
        theme = "cui",
        sizingMode = "auto",
        savedPos = nil,
        blocks = {},
    },
}

local function UniqueBarName(baseValue)
    local profile = mod.GetProfile()
    if not profile then
        return baseValue
    end
    local function taken(num)
        for i = 1, #profile.bars do
            if profile.bars[i].name == num then
                return true
            end
        end
        return false
    end
    if not taken(baseValue) then
        return baseValue
    end
    local num = 2
    while taken(baseValue .. " " .. num) do
        num = num + 1
    end
    return baseValue .. " " .. num
end

-- Appends a block of typeKey to the bar and applies. Returns the blockCfg.
function mod.AddBlock(barId, typeKey)
    local conf = mod.GetBar(barId)
    if not conf then
        return nil
    end
    if not mod.BLOCK_DEFAULTS[typeKey] then
        return nil
    end
    conf.nextBlockId = (conf.nextBlockId or 0) + 1
    local b = {
        id = conf.nextBlockId,
        type = typeKey,
        align = "CENTER",
        xOff = 0,
        yOff = 0,
        bg = nil,
        settings = DeepCopy(mod.BLOCK_DEFAULTS[typeKey]),
    }
    -- Micro menu counters default 8px above their buttons via the SAME
    -- textYOff the Text Position cog edits, so ONE value owns the counter
    -- position (anchor is plain button-center).
    if typeKey == "micromenu" then
        b.textYOff = 8
    end
    conf.blocks[#conf.blocks + 1] = b
    mod.ApplyBar(barId)
    return b
end

function mod.RemoveBlock(barId, blockId)
    local conf = mod.GetBar(barId)
    if not conf then
        return
    end
    for i = 1, #conf.blocks do
        if conf.blocks[i].id == blockId then
            tremove(conf.blocks, i)
            break
        end
    end
    -- Center is optional: removing the centered block just clears the
    -- designation (fill heals to the last block via EnsureFillBlock).
    if conf.centerBlockId == blockId then
        conf.centerBlockId = nil
    end
    mod.ApplyBar(barId)
end

function mod.MoveBlock(barId, blockId, delta)
    local conf = mod.GetBar(barId)
    if not conf then
        return
    end
    local _, position = GetBlock(conf, blockId)
    if not position then
        return
    end
    local targetUnit = position + (delta or 0)
    if targetUnit < 1 or targetUnit > #conf.blocks then
        return
    end
    conf.blocks[position], conf.blocks[targetUnit] = conf.blocks[targetUnit], conf.blocks[position]
    mod.ApplyBar(barId)
end

-- Designates blockId as the bar's Fill Remaining block (auto mode). The
-- previous fill block simply stops being it -- one fill per bar always.
-- A block may fill AND be Force Centered: its slot then absorbs the whole
-- middle span with the content pinned at true center.
function mod.SetFillBlock(barId, blockId)
    local conf = mod.GetBar(barId)
    local b = GetBlock(conf, blockId)
    if not b then
        return
    end
    conf.fillBlockId = blockId
    mod.ApplyBar(barId)
end

-- Designates blockId as the bar's Force Centered block (auto mode; nil
-- clears). At most one per bar.
function mod.SetCenterBlock(barId, blockId)
    local conf = mod.GetBar(barId)
    if not conf then
        return
    end
    if blockId ~= nil then
        local b = GetBlock(conf, blockId)
        if not b then
            return
        end
    end
    conf.centerBlockId = blockId
    mod.ApplyBar(barId)
end

-- Drag-reorder commit: move a block to boundary index newIndex (1-based,
-- in the PRE-removal indexing of the blocks array, n+1 = after the last).
function mod.MoveBlockTo(barId, blockId, newIndex)
    local conf = mod.GetBar(barId)
    if not conf then
        return
    end
    local from
    for i = 1, #conf.blocks do
        if conf.blocks[i].id == blockId then
            from = i
            break
        end
    end
    if not from then
        return
    end
    local b = table.remove(conf.blocks, from)
    local to = newIndex or (from + 1)
    if to > from then
        to = to - 1
    end
    if to < 1 then
        to = 1
    end
    if to > #conf.blocks + 1 then
        to = #conf.blocks + 1
    end
    table.insert(conf.blocks, to, b)
    mod.ApplyBar(barId)
end

-- Divider commit: A gets newAWeight, B gets (frozen pair budget - A).
function mod.TransferPct(barId, aBlockId, bBlockId, newAWeight)
    local conf = mod.GetBar(barId)
    local a = GetBlock(conf, aBlockId)
    local b = GetBlock(conf, bBlockId)
    if not (a and b) then
        return
    end
    local budget = (a.widthPct or 10) + (b.widthPct or 10)
    local wid = newAWeight or (budget / 2)
    if wid < 0 then
        wid = 0
    end
    if wid > budget then
        wid = budget
    end
    a.widthPct = wid
    b.widthPct = budget - wid
    mod.RequestLayout(barId)
end

-- Creates a bar from a template ("bottom"|"minimapc"|"microstrip"|"empty"),
-- applies it, registers its unlock element and selects it.
function mod.CreateBar(templateKey)
    local profile = mod.GetProfile()
    if not profile then
        return nil
    end
    local t = TEMPLATES[templateKey]
    if not t then
        t = TEMPLATES.empty
    end
    profile.nextBarId = (profile.nextBarId or 0) + 1
    local ident = profile.nextBarId
    local sp = nil
    if t.savedPos then
        sp = { point = t.savedPos.point, relPoint = t.savedPos.relPoint, x = t.savedPos.x, y = t.savedPos.y }
    end
    local conf = {
        id = ident,
        name = UniqueBarName(t.name),
        orientation = t.orientation,
        lengthMode = t.lengthMode,
        length = t.length,
        thickness = t.thickness,
        snapEdge = t.snapEdge,
        sizingMode = t.sizingMode,
        fontScale = 100,
        theme = {
            style = t.theme,
            cuiAlpha = 0.5,
            modernColor = { r = 0.067, g = 0.067, b = 0.067, a = 0.95 },
        },
        visibility = "always",
        savedPos = sp,
        nextBlockId = 0,
        blocks = {},
    }
    profile.bars[#profile.bars + 1] = conf
    -- Template block entries may carry per-block overrides beyond the
    -- seeded defaults (gaps, align, offsets, color, settings tweaks).
    for _, bt in ipairs(t.blocks) do
        local b = mod.AddBlock(ident, bt.type)
        if b then
            for k, v in pairs(bt) do
                if k == "settings" then
                    for sk, sv in pairs(v) do
                        b.settings[sk] = DeepCopy(sv)
                    end
                elseif k ~= "type" then
                    b[k] = DeepCopy(v)
                end
            end
        end
    end
    -- Template-designated Fill Remaining block (first block of fillType);
    -- otherwise EnsureFillBlock heals to the last block on first solve.
    if t.fillType then
        for i = 1, #conf.blocks do
            if conf.blocks[i].type == t.fillType then
                conf.fillBlockId = conf.blocks[i].id
                break
            end
        end
    end
    -- Template-designated Force Centered block (first block of centerType).
    -- Center and fill are combinable, so the fill block is a legal pick.
    if t.centerType then
        for i = 1, #conf.blocks do
            local tb = conf.blocks[i]
            if tb.type == t.centerType then
                conf.centerBlockId = tb.id
                break
            end
        end
    end
    profile.selectedBarId = ident
    mod.ApplyBar(ident)
    mod.RegisterAllUnlockElements()
    return conf
end

-- Removes the bar's cfg and tears the runtime down. Does NOT confirm (the
-- options UI shows the confirmation popup). The unlock element stays
-- registered and goes dormant; the id is never reused.
function mod.DeleteBar(ident)
    local profile = mod.GetProfile()
    if not profile then
        return
    end
    for i = 1, #profile.bars do
        if profile.bars[i].id == ident then
            tremove(profile.bars, i)
            break
        end
    end
    local recd = live[ident]
    if recd then
        for _, instance in pairs(recd.insts) do
            if instance.Disable then
                instance:Disable()
            end
            if instance.Destroy then
                instance:Destroy()
            end
        end
        wipe(recd.insts)
        recd.bar:Hide()
        recd.enabled = false
        live[ident] = nil
    end
    mod._moEligible[ident] = nil
    if profile.selectedBarId == ident then
        profile.selectedBarId = nil
    end
    AfterBarStateChange()
end

function mod.RenameBar(ident, name)
    local conf = mod.GetBar(ident)
    if not conf then
        return
    end
    if type(name) ~= "string" then
        return
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        return
    end
    conf.name = name
    -- Re-registration is a safe overwrite; it refreshes the mover label.
    mod.RegisterAllUnlockElements()
end

-------------------------------------------------------------------------------
--  Currency discovery (searchable picker source)
--  Expand collapsed headers, scan, restore in reverse order.
-------------------------------------------------------------------------------
function mod.BuildCurrencyList()
    local values, sequence = {}, {}
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then
        return values, sequence
    end
    local collapsed = {}
    local position = 1
    while position <= C_CurrencyInfo.GetCurrencyListSize() do
        local details = C_CurrencyInfo.GetCurrencyListInfo(position)
        if details and details.isHeader and not details.isHeaderExpanded then
            collapsed[#collapsed + 1] = position
            C_CurrencyInfo.ExpandCurrencyList(position, true)
        end
        position = position + 1
    end
    for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
        local details = C_CurrencyInfo.GetCurrencyListInfo(i)
        if details and not details.isHeader then
            local itemLink = C_CurrencyInfo.GetCurrencyListLink(i)
            local cID = nil
            if itemLink then
                cID = C_CurrencyInfo.GetCurrencyIDFromLink(itemLink)
            end
            if cID and not values[cID] then
                local cInfo = C_CurrencyInfo.GetCurrencyInfo(cID)
                local cName = details.name
                if cInfo and cInfo.name then
                    cName = cInfo.name
                end
                if not cName then
                    cName = tostring(cID)
                end
                values[cID] = cName
                sequence[#sequence + 1] = cID
            end
        end
    end
    for i = #collapsed, 1, -1 do
        C_CurrencyInfo.ExpandCurrencyList(collapsed[i], false)
    end
    return values, sequence
end

-------------------------------------------------------------------------------
--  LibDataBroker access (the "ldb" block type)
-------------------------------------------------------------------------------
-- The suite ships the library itself (CludesUI parent, beside the
-- CallbackHandler it needs) rather than borrowing it from whichever broker addon
-- happens to load: every broker we read sorts after CludesUIDataBars, so
-- borrowing would hand back nil at our load time. Resolved lazily all the same --
-- a half-updated install must go quiet here, not error.
local _ldb
function mod.GetLDB()
    if _ldb then
        return _ldb
    end
    if not LibStub then
        return nil
    end
    _ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
    return _ldb
end

-- Display label for one data object. The registered NAME is what the block
-- stores, so it always leads; a self-declared label that differs rides along in
-- grey, so a plugin that calls itself something other than its name is still
-- findable in the picker.
function mod.LDBLabel(name, object)
    if not object then
        return name
    end
    local labelFS = object.label
    if type(labelFS) == "string" and labelFS ~= "" and labelFS ~= name then
        return name .. " |cff808080(" .. labelFS .. ")|r"
    end
    return name
end

-- Every data source registered right now, sorted case-insensitively. Rebuilt at
-- each dropdown open (never cached): plugins register on their own schedule, and
-- some appear only after their addon finishes loading.
function mod.BuildLDBList()
    local values, sequence = {}, {}
    local LDB = mod.GetLDB()
    if not LDB then
        return values, sequence
    end
    for name, object in LDB:DataObjectIterator() do
        values[name] = mod.LDBLabel(name, object)
        sequence[#sequence + 1] = name
    end
    tsort(sequence, function(a, b)
        return a:lower() < b:lower()
    end)
    return values, sequence
end

-------------------------------------------------------------------------------
--  Lifecycle
-------------------------------------------------------------------------------
function WB:OnInitialize()
    self.db = CludesUI.Lite.NewDB("CludesUIDataBarsDB", defaultSet)
    -- Cross-character gold ledger is account data (CludesUIDB.goldLedger,
    -- CludesUI.GetGoldLedger()), not profile -- a profile-scoped copy would leak every
    -- character's name/realm/balance into export strings. Drop any old
    -- profile copy (don't migrate): on an imported profile it holds the
    -- exporter's characters, and the account store refills from play anyway.
    self.db.profile.characters = nil
end

function WB:OnEnable()
    local profile = mod.GetProfile()
    if not profile then
        return
    end
    for i = 1, #profile.bars do
        mod.ApplyBar(profile.bars[i].id)
    end
    -- Mid-combat /reload: lockdown has NOT re-engaged yet (same technique the suite
    -- uses elsewhere to position elements during the load screen), but RequestLayout's
    -- next-frame timer fires AFTER it does, so the protected-bar gate would freeze bars
    -- whose slots were never placed (blank until regen). Lay out synchronously NOW
    -- while still legal; the queued pass coalesces harmlessly.
    for i = 1, #profile.bars do
        ApplyLayout(profile.bars[i].id)
    end
    mod.RegisterAllUnlockElements()
    -- Zero-bars case: ApplyBar never ran, so recompute the gates once here.
    AfterBarStateChange()
end

function WB:OnDisable()
    local profile = mod.GetProfile()
    if not profile then
        return
    end
    for i = 1, #profile.bars do
        local recd = live[profile.bars[i].id]
        if recd and recd.enabled then
            for _, instance in pairs(recd.insts) do
                if instance.Disable then
                    instance:Disable()
                end
            end
            recd.bar:Hide()
            recd.enabled = false
        end
    end
end

-------------------------------------------------------------------------------
--  Profile-swap apply hook. Profile system re-points db.profile then calls
--  this: retire live records whose bar ids are absent from the incoming
--  profile (ApplyBar treats missing cfg as disable), build the incoming
--  set, re-register unlock movers, re-sync every gate.
-------------------------------------------------------------------------------
_G._CUDB_Apply = function()
    if not (WB.db and WB.db.profile) then
        return
    end
    if mod.WipeFitCache then
        mod.WipeFitCache()
    end
    for ident in pairs(live) do
        mod.ApplyBar(ident)
    end
    local profile = mod.GetProfile()
    for i = 1, #profile.bars do
        mod.ApplyBar(profile.bars[i].id)
    end
    mod.RegisterAllUnlockElements()
    AfterBarStateChange()
end

_G._CUDB_RegisterUnlock = function()
    mod.RegisterAllUnlockElements()
end

-------------------------------------------------------------------------------
--  Party Mode: spinning data bars. Each block orbits its own bar's centre,
--  like the action bar spin. Driver, combat pause and rest tracking live in
--  the shared engine (CludesUI.PartySpin_Create, CludesUI_PartyMode.lua).
-------------------------------------------------------------------------------
do
    local groups = {}
    local groupOf = setmetatable({}, { __mode = "k" }) -- bar rec -> reused group
    CludesUI.PartySpin_Create({
        target = "dataBars",
        collect = function()
            wipe(groups)
            for _, recd in pairs(live) do
                if recd.enabled and recd.bar and recd.slots then
                    local grp = groupOf[recd]
                    if not grp then
                        grp = { frames = {} }
                        groupOf[recd] = grp
                    end
                    grp.pivot = recd.bar
                    local entries = grp.frames
                    wipe(entries)
                    for _, slotIndex in pairs(recd.slots) do
                        entries[#entries + 1] = slotIndex
                    end
                    groups[#groups + 1] = grp
                end
            end
            return groups
        end,
    })
end

-- Party Mode visibility axis (Visibility > Party Mode): no game event, so the
-- core fires its own edge.
if CludesUI.RegisterVisEdge then
    CludesUI.RegisterVisEdge(function()
        if mod.UpdateAllBarVisibility then
            mod.UpdateAllBarVisibility()
        end
    end)
end
