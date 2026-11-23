if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin.lua
--  Umbrella addon for themed Blizzard UI frames. Hosts the Character Sheet
--  rework (CludesUIBlizzardSkin_CharacterSheet.lua) plus the tooltip,
--  context menu and static popup reskinning (CUI_BlizzardSkin_*.lua).
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if
    not (
        CUI
        and CUI._ModuleNS
        and CUI.NewInternals
        and CUI.NewCombatQueue
        and CUI.FriendsKit
        and CUI.FriendsList
        and CUI.CreateQuantityDialog
        and CUI.NewFrameData
        and CUI.GetFontFamily
        and CUI.SetFontFamily
        and CUI.BorderPlacement
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (FriendsForever reads the parent's friends kit and starts its custom friends list, Merchant Bulk Buy its quantity window; the tooltip lines, chat bubbles, mail alt list, the window packs' names and mail lines and the WoW Forever friends and Looking For Group texts that show other players' writing take the parent's font families, and the engine aura tooltip's border takes the parent's border placement)
CUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CUI.NewCombatQueue(CreateFrame("Frame"))

-- External weak-keyed lookup table for frame state (prevents tainting Blizzard frames)
local FFD, GetFFD = CUI.NewFrameData()

-------------------------------------------------------------------------------
--  Per-window skin style ("cui"|"modern"|"blizzard"|"off"). Enable keys are
--  the on/off source of truth (key false = "off"; a STOCK_WINDOWS key is "off"
--  until it is true); blizzWindowSkinStyles only
--  records WHICH style an enabled window uses (nil = "cui"). "blizzard" is the
--  Character Sheet's Blizz Default: Blizzard's own sheet with the CludesUI
--  stats, slot text and socket panel. Its "off" leaves the sheet untouched.
-------------------------------------------------------------------------------
local WINDOW_ENABLE_KEYS = {
    charsheet = "themedCharacterSheet",
    inspect = "themedInspectSheet",
    lfg = "reskinLFGMenu",
    greatvault = "reskinGreatVault",
    collections = "reskinCollections",
    playerspells = "reskinPlayerSpells",
    adventureguide = "reskinAdventureGuide",
    professionsbook = "reskinProfessionsBook",
    guild = "reskinGuild",
    calendar = "reskinCalendar",
    achievements = "reskinAchievements",
    mail = "reskinMail",
    catalyst = "reskinCatalyst",
    socket = "reskinSocket",
    itemupgrade = "reskinItemUpgrade",
    loot = "reskinLoot",
    loottoast = "reskinLootToast",
    bnettoast = "reskinBNetToast",
    lootroll = "reskinLootRoll",
    loothistory = "reskinLootHistory",
    groupinvite = "reskinGroupInvite",
    readycheck = "reskinReadyCheck",
    micromenu = "reskinMicroMenu",
    housing = "reskinHousing",
    professions = "reskinProfessions",
    worldmap = "reskinWorldMap",
    dressup = "reskinDressUp",
    transmog = "reskinTransmog",
    merchant = "reskinMerchant",
    auctionhouse = "reskinAuctionHouse",
    macros = "reskinMacros",
    settings = "reskinSettings",
    addonlist = "reskinAddonList",
    craftorders = "reskinCraftOrders",
    trainer = "reskinTrainer",
    gossip = "reskinGossip",
    quest = "reskinQuest",
    inspectrecipe = "reskinInspectRecipe",
    delves = "reskinDelves",
    socialui = "reskinSocialUI",
    -- delvepicker is the Delves TIER PICKER, a separate frame from the
    -- companion configuration window that `delves` above covers.
    queuestatus = "reskinQueueStatus",
    delvepicker = "reskinDelvePicker",
    playerchoice = "reskinPlayerChoice",
    trade = "reskinTrade",
    flagcarrier = "reskinFlagCarriers",
}
-- WoW Forever's own windows: the bag bar and Progress Legacy skins exist only there.
if CUI.IS_FOREVER then
    WINDOW_ENABLE_KEYS.bagbar = "reskinBagBar"
    WINDOW_ENABLE_KEYS.legacysystem = "reskinLegacySystem"
end

-- Windows whose skin starts at Blizz Default (owner 2026-10-29: the Flag
-- Carriers). Their enable key reads on only when true, where every other
-- window's reads on until it is false, so a fresh install, a module reset, an
-- import from a build before the card and the first visit of every look all
-- leave them off; their card writes true or false. Enable keys are read and
-- written through EnabledValue / OnValue, never `~= false` / `= nil` directly.
local STOCK_WINDOWS = { flagcarrier = true }
local function EnabledValue(windowKey, val)
    if STOCK_WINDOWS[windowKey] then return val == true end
    return val ~= false
end
-- What "on" is stored as: nil (the install default) or, for a stock window, true.
local function OnValue(windowKey)
    if STOCK_WINDOWS[windowKey] then return true end
    return nil
end
--- Master PER-PROFILE kill switch for ALL Blizzard window skinning: window engine
--- + every pack, plus CharacterSheet/Inspect, SocketPanel, LFG skins. Lives at
--- profiles[name].disableWindowSkins, resolved live (follows profile switches,
--- rides exports); nil/false = enabled. Per-window enable keys and style picks are
--- PRESERVED while killed. Skins install at load, so crossings need a reload
--- (callers show the popup). Queue Popup, Pause Menu, and Dragon Riding are not windows and stay untouched.
function CUI.BlizzWindowSkinsKilled()
    local profileTbl = CUI.GetActiveProfileData()
    return (profileTbl and profileTbl.disableWindowSkins) and true or false
end

-------------------------------------------------------------------------------
--  One-time style seed for window keys added after the fact: each adopts
--  whichever style (CUI/Modern/off) the user already runs MOST windows with,
--  instead of defaulting ON in CUI. Counts RAW stored state (not GetBlizzWindowStyle)
--  so the kill switch cannot skew the vote; touched keys are left alone; ties fall to
--  CUI. Marker-gated to once per account, at ADDON_LOADED (parent SVs are in by then, before PLAYER_LOGIN apply).
--
--  One BATCH per shipment, each with its OWN marker: a spent marker is never
--  revisited, so a later batch riding the older one would silently skip every
--  account that already ran it.
-------------------------------------------------------------------------------
do
    local BATCHES = {
        { marker = "lootSkinStyleSeeded", keys = { "lootroll", "loothistory", "groupinvite" } },
        { marker = "readyCheckStyleSeeded", keys = { "readycheck" } },
        {
            marker = "queueChoiceTradeStyleSeeded",
            keys = { "queuestatus", "delvepicker", "playerchoice", "trade" },
        },
        { marker = "bnetToastStyleSeeded", keys = { "bnettoast" } },
    }
    -- Retail only: this shipment is when the Friends List card started
    -- skinning retail's friends window. WoW Forever's card has driven its own
    -- friends skin since that file shipped, so those accounts stay as set.
    if not CUI.IS_FOREVER then
        BATCHES[#BATCHES + 1] = { marker = "socialLegacySkinSeeded", keys = { "socialui" } }
    else
        -- WoW Forever: the shipment where the LFG Menu card began skinning
        -- that client's Looking For Group window.
        BATCHES[#BATCHES + 1] = { marker = "foreverLfgSkinSeeded", keys = { "lfg" } }
        -- WoW Forever: the micro menu and the bag bar began skinning there.
        BATCHES[#BATCHES + 1] = { marker = "foreverMicroBagSkinSeeded", keys = { "micromenu", "bagbar" } }
        -- WoW Forever: the Progress Legacy window began skinning there.
        BATCHES[#BATCHES + 1] = { marker = "foreverLegacySkinSeeded", keys = { "legacysystem" } }
    end
    local function SeedBatch(markerTex, newKeys)
        if CludesUIDB[markerTex] then return end
        CludesUIDB[markerTex] = true
        local styleMap = CludesUIDB.blizzWindowSkinStyles
        local isNew = {}
        for _, key in ipairs(newKeys) do
            isNew[key] = true
        end
        local isOff, modernStyle, ownStyle = 0, 0, 0
        for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
            -- A window that starts at Blizz Default says nothing of the
            -- player's taste.
            if not isNew[windowKey] and not STOCK_WINDOWS[windowKey] then
                -- A Blizz Default character sheet keeps Blizzard's look.
                if CludesUIDB[engineKey] == false or (styleMap and styleMap[windowKey] == "blizzard") then
                    isOff = isOff + 1
                elseif styleMap and styleMap[windowKey] == "modern" then
                    modernStyle = modernStyle + 1
                else
                    ownStyle = ownStyle + 1
                end
            end
        end
        for _, windowKey in ipairs(newKeys) do
            local engineKey = WINDOW_ENABLE_KEYS[windowKey]
            local touched = CludesUIDB[engineKey] ~= nil or (styleMap and styleMap[windowKey] ~= nil)
            if not touched then
                if isOff > ownStyle and isOff > modernStyle then
                    CludesUIDB[engineKey] = false
                elseif modernStyle > ownStyle and modernStyle >= isOff then
                    if not styleMap then
                        styleMap = {}
                        CludesUIDB.blizzWindowSkinStyles = styleMap
                    end
                    styleMap[windowKey] = "modern"
                end
                -- CUI majority (or tie): nil already means CUI-on.
            end
        end
    end
    -- The font look record a whole-UI style switch writes beside the window
    -- swap (fonts._styleSlots.active); the active profile's lives in the live
    -- font store, every other profile's in its own snapshot.
    local function FontLookOf(store, name, profileTbl)
        local fonts = (name == (store.activeProfile or "Default")) and store.fonts or profileTbl.fonts
        local fontStr = type(fonts) == "table" and fonts._styleSlots
        local style = type(fontStr) == "table" and fontStr.active
        if style == "cui" or style == "blizzard" or style == "classic" then return style end
        return nil
    end

    -- Once per account: windows on a stock look with NO profile recording a
    -- look (no windowSkinLook, no font look record -- a glyph-fallback locale
    -- never writes the latter) -- the active profile adopts the look its
    -- windows are on, so nothing moves.
    local function AdoptLegacyWindowLook(store)
        if store.windowLookPerProfile then return end
        store.windowLookPerProfile = true
        local slotMap = store.windowSkinStyleSlots
        local live = type(slotMap) == "table" and slotMap.active
        if not live or live == "cui" or type(store.profiles) ~= "table" then return end
        for name, p in pairs(store.profiles) do
            if type(p) == "table" and (p.windowSkinLook or FontLookOf(store, name, p)) then return end
        end
        local p = store.profiles[store.activeProfile or "Default"]
        if type(p) == "table" then p.windowSkinLook = live end
    end

    -- Once per account: the Character Sheet's Blizz Default used to be the
    -- Style page's Character Sheet row (profile-root flags; copies an older
    -- build left on the account root count too). The profile the live
    -- windows belong to hands its choice to the sheet's card, and the look
    -- slots give every other look its own default. A WoW Forever profile
    -- from before that row existed there follows its stock look, as the
    -- row's own adoption did. When the live look is a stock one, the skin the
    -- sheet wore before (CludesUI or Modern) is kept for the CludesUI
    -- look.
    local function AdoptCharSheetCardStyle(store)
        if store.charSheetCardStyleAdopted then return end
        store.charSheetCardStyleAdopted = true
        local name = store.activeProfile or "Default"
        local p = type(store.profiles) == "table" and store.profiles[name]
        if type(p) ~= "table" then p = nil end
        local stock = store.charSheetUseBlizzardStyle
            or store.charSheetUseClassicStyle
            or (p and (p.charSheetUseBlizzardStyle or p.charSheetUseClassicStyle))
        if
            not stock
            and p
            and CUI.IS_FOREVER
            and not store.foreverCharSheetStyleAdopted
            and p.charSheetUseBlizzardStyle == nil
            and p.charSheetUseClassicStyle == nil
        then
            local style = p.windowSkinLook or FontLookOf(store, name, p)
            stock = style == "blizzard" or style == "classic"
        end
        if not stock then return end
        local styleMap = store.blizzWindowSkinStyles
        if type(styleMap) ~= "table" then
            styleMap = {}
            store.blizzWindowSkinStyles = styleMap
        end
        local slotMap = store.windowSkinStyleSlots
        if
            type(slotMap) == "table"
            and slotMap.active
            and slotMap.active ~= "cui"
            and type(slotMap.cui) == "table"
            and slotMap.cui.charsheetStyle == nil
        then
            slotMap.cui.charsheetStyle = styleMap.charsheet or "cui"
        end
        styleMap.charsheet = "blizzard"
    end

    -- Apply to All with CludesUI (the Style page, the first-install picker):
    -- every window in the CludesUI skin. The whole-UI switch only swaps the
    -- look's saved slots, so a window left at Blizz Default there (or by the
    -- new-key seeding above) stayed so; this turns every window skin on in
    -- the CludesUI style and clears the profile's kill switch. dryRun: only
    -- whether anything would change. Called with the look already on CludesUI.
    function CUI.CludesUIWindowsAllOn(dryRun)
        local store = CludesUIDB
        if type(store) ~= "table" then return false end
        local styleMap = store.blizzWindowSkinStyles
        local needed = CUI.BlizzWindowSkinsKilled() or (type(styleMap) == "table" and next(styleMap) ~= nil)
        for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
            if not EnabledValue(windowKey, store[engineKey]) then needed = true end
        end
        if dryRun or not needed then return needed end
        local profileTbl = CUI.GetActiveProfileData()
        if type(profileTbl) == "table" then profileTbl.disableWindowSkins = nil end
        for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
            store[engineKey] = OnValue(windowKey)
        end
        store.blizzWindowSkinStyles = nil
        return true
    end

    local seedFrame = CreateFrame("Frame")
    seedFrame:RegisterEvent("ADDON_LOADED")
    -- Registered here, first among this addon's frames, so the login pass
    -- runs after the spec profile pre-seed and before any window skin or
    -- character sheet reads its settings.
    seedFrame:RegisterEvent("PLAYER_LOGIN")
    seedFrame:SetScript("OnEvent", function(self, evt, name)
        if evt == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            CUI.ReconcileWindowSkinLook()
            return
        end
        if name ~= ADDON_NAME then return end
        self:UnregisterEvent("ADDON_LOADED")
        if not CludesUIDB then CludesUIDB = {} end
        for _, batch in ipairs(BATCHES) do
            SeedBatch(batch.marker, batch.keys)
        end
        AdoptLegacyWindowLook(CludesUIDB)
        AdoptCharSheetCardStyle(CludesUIDB)
        CUI.ReconcileWindowSkinLook()
    end)
end

function CUI.GetBlizzWindowStyle(windowKey)
    -- Third-party virtual keys ("tp:<AddonName>", RegisterSkin API) resolve by majority
    -- vote and bypass the kill switch: third-party skinning is its own opt-in, so window-skin settings only pick WHICH theme, never whether it runs.
    if type(windowKey) == "string" and windowKey:sub(1, 3) == "tp:" then
        return CUI.GetThirdPartySkinStyle()
    end
    if CUI.BlizzWindowSkinsKilled() then return "off" end
    local engineKey = WINDOW_ENABLE_KEYS[windowKey]
    if engineKey and not EnabledValue(windowKey, CludesUIDB and CludesUIDB[engineKey]) then return "off" end
    local styleMap = CludesUIDB and CludesUIDB.blizzWindowSkinStyles
    local s = styleMap and styleMap[windowKey]
    if s == "modern" or s == "blizzard" then return s end
    return "cui"
end

--- Style for third-party addon skins: majority vote across the user's own window
--- styles. Modern majority -> "modern"; else (CUI majority, tie, or nothing skinned,
--- incl. under the kill switch where every window reports "off") -> "cui". Never
--- returns "off": whether third-party skinning runs is decided by its own toggles in
--- the SkinAPI dispatcher (reload-bound there), so live refreshes only ever swap between the two themes.
function CUI.GetThirdPartySkinStyle()
    local ownStyle, modernStyle = 0, 0
    local styleMap = CludesUIDB and CludesUIDB.blizzWindowSkinStyles
    -- Under a stock look (windowSkinStyleSlots.active) a window still votes
    -- as it stands in the CludesUI look's slot, so switching the whole UI
    -- leaves the vote where it was.
    local slotMap = CludesUIDB and CludesUIDB.windowSkinStyleSlots
    local cuiSlot = type(slotMap) == "table"
            and slotMap.active
            and slotMap.active ~= "cui"
            and type(slotMap.cui) == "table"
            and slotMap.cui
        or nil
    local killed = CUI.BlizzWindowSkinsKilled()
    for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
        -- The inspect sheet renders in the character sheet's style: one vote.
        if windowKey ~= "inspect" then
            local s = CUI.GetBlizzWindowStyle(windowKey)
            -- A Blizz Default character sheet wears no skin: it votes like
            -- a window that is off.
            if s == "blizzard" then s = "off" end
            if s == "off" and not killed and cuiSlot and EnabledValue(windowKey, cuiSlot[engineKey]) then
                s = (styleMap and styleMap[windowKey] == "modern") and "modern" or "cui"
            end
            if s == "modern" then
                modernStyle = modernStyle + 1
            elseif s == "cui" then
                ownStyle = ownStyle + 1
            end
        end
    end
    return (modernStyle > ownStyle) and "modern" or "cui"
end

-- Turn off every window reskin at once (feature-intro popup's "Disable"). Writes explicit
-- false to each enable key (GetBlizzWindowStyle -> "off"); blizzWindowSkinStyles is left intact so re-enable restores styles. Reskins install at load, so the caller must reload.
function CUI.DisableAllBlizzWindowSkins()
    if not CludesUIDB then CludesUIDB = {} end
    for _, engineKey in pairs(WINDOW_ENABLE_KEYS) do
        CludesUIDB[engineKey] = false
    end
end

-- A style chosen for the whole UI (the first-install picker, the Style page's
-- Apply to All) swaps the window skins through per-style slots:
-- CludesUIDB.windowSkinStyleSlots = { active = the look whose windows are
-- live, cui/blizzard/classic/forever = that look's enable keys }. Leaving a
-- look saves its windows into its slot; entering one loads its slot, so each
-- look comes back as it was left, per-window picks included. First visit:
-- Blizzard Style and Classic WoW UI keep Blizzard's own windows, every one at
-- Blizz Default; the CludesUI look and WoW Forever put every one back to
-- its default (on), the character sheet on its CludesUI skin -- except
-- that WoW Forever keeps the micro menu and the bag bar at Blizz Default, and
-- no look turns on a window that starts there (STOCK_WINDOWS). The Friends List window rides them whatever the
-- Friends module's state (its pack stands down by itself under a stock
-- Friends style), so a key saved in one swap is always loaded back in the
-- next. A slot holds on/off booleans; a window a slot never recorded (one
-- added later) takes the look's first-visit value. Styles
-- (blizzWindowSkinStyles) are never touched, so a window turned back on keeps
-- its skin -- except the character sheet's, which the slots carry as
-- `charsheetStyle`: Blizz Default is a style there (Blizzard Style's and
-- Classic WoW UI's first visit), and its Off (with the inspect sheet riding
-- its card) stays out of the slots, so a sheet turned off stays off in every
-- look. A one-way seed record from before the slots
-- (windowSkinsStockSeeded) converts on the first swap: its windows were on
-- under the CludesUI look, and legacyStock names the look it belongs to.
-- dryRun: only report whether the whole UI's window look would change.
local function WindowInSlots(windowKey) return windowKey ~= "charsheet" and windowKey ~= "inspect" end
-- The looks whose first visit skins the windows (winKey nil: the look as a
-- whole). WoW Forever leaves the micro menu and the bag bar at Blizz Default,
-- every look a window that starts there.
local FOREVER_STOCK = { micromenu = true, bagbar = true }
local function LookSkinsWindows(style, windowKey)
    if windowKey and STOCK_WINDOWS[windowKey] then return false end
    if style == "forever" then return not (windowKey and FOREVER_STOCK[windowKey]) end
    return style == "cui"
end
function CUI.SwapWindowSkinStyle(to, dryRun, legacyStock)
    if not CludesUIDB then CludesUIDB = {} end
    local slotMap = CludesUIDB.windowSkinStyleSlots
    if type(slotMap) ~= "table" then slotMap = nil end
    local rec = CludesUIDB.windowSkinsStockSeeded
    local from = (slotMap and slotMap.active)
        or (type(rec) == "table" and (legacyStock or "blizzard"))
        or "cui"
    if from == to then return false end
    if dryRun then return true end
    if not slotMap then
        slotMap = {}
        if type(rec) == "table" then
            local ownStyle = {}
            for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
                if WindowInSlots(windowKey) then
                    ownStyle[engineKey] = rec[windowKey] and true
                        or EnabledValue(windowKey, CludesUIDB[engineKey])
                end
            end
            slotMap.cui = ownStyle
        end
        CludesUIDB.windowSkinStyleSlots = slotMap
    end
    CludesUIDB.windowSkinsStockSeeded = nil
    local styleMap = CludesUIDB.blizzWindowSkinStyles
    if type(styleMap) ~= "table" then styleMap = nil end
    local result = {}
    for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
        if WindowInSlots(windowKey) then
            result[engineKey] = EnabledValue(windowKey, CludesUIDB[engineKey])
        end
    end
    result.charsheetStyle = (styleMap and styleMap.charsheet) or "cui"
    slotMap[from] = result
    local saved = slotMap[to]
    if type(saved) ~= "table" then saved = nil end
    for windowKey, engineKey in pairs(WINDOW_ENABLE_KEYS) do
        if WindowInSlots(windowKey) then
            local val = saved and saved[engineKey]
            if val == nil then val = LookSkinsWindows(to, windowKey) end
            -- On = OnValue (nil, the install default, or true for a stock
            -- window), off = false. An explicit branch: `x and false or nil`
            -- can only ever yield nil.
            if val then
                CludesUIDB[engineKey] = OnValue(windowKey)
            else
                CludesUIDB[engineKey] = false
            end
        end
    end
    -- The character sheet's style. A look's first visit (or a slot saved
    -- before the sheet rode them): Blizz Default on Blizzard Style and
    -- Classic WoW UI; on the CludesUI look and WoW Forever a Blizz Default
    -- goes back to the CludesUI skin and any other pick stays.
    local classStyle = saved and saved.charsheetStyle
    if classStyle == nil then
        if not LookSkinsWindows(to) then
            classStyle = "blizzard"
        elseif styleMap and styleMap.charsheet == "blizzard" then
            classStyle = "cui"
        end
    end
    if classStyle == "cui" then
        if styleMap then styleMap.charsheet = nil end
    elseif classStyle then
        if not styleMap then
            styleMap = {}
            CludesUIDB.blizzWindowSkinStyles = styleMap
        end
        styleMap.charsheet = classStyle
    end
    slotMap.active = to
    return true
end

-- The whole-UI window look belongs to a PROFILE: the look the whole-UI
-- switch last gave it (profile-root windowSkinLook; a profile from before
-- that key falls back to its font look record, written by the same switch).
-- A profile no whole-UI switch ever touched is on the CludesUI look --
-- once the account's windows have been switched at all; before that there
-- is nothing to follow (nil). liveFonts: the live font store, for the
-- active profile (its own snapshot is stale until the next switch).
function CUI.ProfileWindowSkinLook(profileTbl, liveFonts)
    if type(profileTbl) ~= "table" then return nil end
    local style = profileTbl.windowSkinLook
    -- WoW Forever's own window look; a Forever profile imported on retail
    -- renders Blizzard Style there, so it takes that look's windows.
    if style == "forever" then return CUI.IS_FOREVER and "forever" or "blizzard" end
    if style == "cui" or style == "blizzard" or style == "classic" then return style end
    local fonts = liveFonts or profileTbl.fonts
    local fontStr = type(fonts) == "table" and fonts._styleSlots
    style = type(fontStr) == "table" and fontStr.active
    if style == "cui" or style == "blizzard" or style == "classic" then return style end
    if CludesUIDB and type(CludesUIDB.windowSkinStyleSlots) == "table" then return "cui" end
    return nil
end

-- Swap the account-wide window skins to the active profile's look (a no-op
-- when they are on it already). Runs at this addon's load, at login after the
-- spec profile pre-seed, and on every profile switch (RepointAllDBs), so each
-- profile keeps its own window look and a per-window pick always banks into
-- the look it was made under. Skins install at load: a switch that changes
-- the look offers the reload (ProfileChangesWindowSkins).
function CUI.ReconcileWindowSkinLook()
    local store = CludesUIDB
    if type(store) ~= "table" then return end
    local profileTbl = CUI.GetActiveProfileData()
    local style = CUI.ProfileWindowSkinLook(profileTbl, store.fonts)
    if style then CUI.SwapWindowSkinStyle(style, false, style ~= "cui" and style or nil) end
end

-- Main-chunk locals the CUI_BlizzardSkin_*.lua files re-import by name.
-- last: the file of the chain that most recently loaded to its end. Every
-- CUI_BlizzardSkin_*.lua file returns at its first lines unless the file
-- before it got there, so one that errors, does not compile or is missing
-- stops the files behind it.
CUI.NewInternals(mod, "_internals", {
    FFD = FFD,
    GetFFD = GetFFD,
    last = "main",
})
