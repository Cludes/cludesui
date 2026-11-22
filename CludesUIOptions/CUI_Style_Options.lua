if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Style_Options.lua
--
--  Global Settings > Style: per-module choice between the CludesUI look
--  and two stock looks that keep every CludesUI feature: Blizzard Style
--  (the current stock art) and Classic WoW UI (the vanilla art). The page
--  assigns modules with one checkbox dropdown under each look card, written
--  together by Apply Styles. A module's choice is a write-through mirror of
--  its own profile flags: a Blizzard flag and
--  a sibling Classic flag, both default off; a style key is read as classic
--  when the Classic flag is set, else blizzard when the Blizzard flag is set,
--  else cui, and a write sets exactly one of the two. Every flag is
--  reload-gated: the values are written ONLY inside the reload popup's
--  confirm handler, so a cancelled popup leaves the profile untouched and the
--  runtime never sees a half-applied style mid-session. The header's look
--  cards (the first-install picker's, CludesUI_StyleCards.lua) each
--  push their style to every enabled module through the same single prompt.
--
--  CludesUI.BlizzStyle is the shared helper set the module options pages
--  use to gate rows that only apply to the CludesUI look (Gate) and to
--  show the "<style> is active" banner (Note). Both are build-time decisions:
--  each module latches its style once per session (the flags it read at
--  load), so the rendered look cannot change without a reload. The helpers
--  read that latched value; the Style rows show the profile's flags. Get()
--  answers the shared question -- is a stock look dictating the geometry --
--  and is true for both stock styles; Active() names the one that is.
--
--  WoW Forever (the Forever client only) adds a fourth value, "forever": a
--  VARIANT of Blizzard Style, not a style of its own. It is a third sibling
--  flag per row (the Blizzard flag's name with "Forever" in place of
--  "Blizzard": useForeverStyle, useForeverStyleBars) written TOGETHER with
--  the Blizzard flag, so every module, reader and older build that does not
--  know it renders Blizzard Style. The rows read "forever" when both are set;
--  Active() still answers "blizzard" (the module latches do too), and
--  Forever() says whether the variant renders. Retail never reads or writes
--  the Forever flags.
-------------------------------------------------------------------------------

local GLOBAL_KEY = "_CUIGlobal"
local PAGE_STYLE = "Style"

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame. BlizzStyle.Note and BlockInline build on
-- other modules' pages through it too.
local CreateFrame = CUI._Pool.CreateFrame

local function ModuleNS(folder) return CUI._ModuleNS and CUI._ModuleNS[folder] end

-------------------------------------------------------------------------------
--  Module registry: one entry per styleable surface. get/set read and write
--  the module's own per-profile flag and are nil-safe while the module is
--  disabled (get returns nil, set is a no-op).
-------------------------------------------------------------------------------

local function ABProfile()
    local mod = ModuleNS("CludesUIActionBars")
    local ABAR = mod and mod.EAB
    return ABAR and ABAR.db and ABAR.db.profile
end
local function UFProfile()
    local mod = ModuleNS("CludesUIUnitFrames")
    return mod and mod.db and mod.db.profile
end
local function PABProfile()
    local p = UFProfile()
    return p and p.playerAuraBars
end
local function NPProfile()
    local mod = ModuleNS("CludesUINameplates")
    return mod and mod.db and mod.db.profile
end
local function CDMProfile()
    local d = _G._CUCME_AceDB
    return d and d.profile
end
local function CastBarProfile()
    local d = _G._CURB_AceDB
    return d and d.profile and d.profile.castBar
end
local function ERBProfile()
    local d = _G._CURB_AceDB
    return d and d.profile
end
local function MinimapProfile()
    local db = _G._CUMM_DB
    return db and db.profile and db.profile.minimap
end
local function DMProfile()
    local db = _G._CUDM_DB
    return db and db.profile and db.profile.dm
end
local function QTProfile()
    local db = _G._CUQT_DB
    return db and db.profile and db.profile.questTracker
end
local function ChatProfile()
    local db = _G._CUCHAT_DB
    return db and db.profile and db.profile.chat
end
local function FriendsProfile()
    local db = _G._CUFR_DB
    return db and db.profile and db.profile.friends
end
-- The Skyriding HUD keeps its own per-profile DB inside Blizz UI Enhanced
-- (created at PLAYER_LOGIN, even while the HUD itself is off).
local function DragonRidingProfile()
    local num = ModuleNS("CludesUIBlizzardSkin")
    local d = num and num.edrDB
    return d and d.profile
end
local function RFProfile()
    local num = ModuleNS("CludesUIRaidFrames")
    return num and num.db and num.db.profile
end

local IS_FOREVER = CUI.IS_FOREVER == true

-- The WoW Forever variant is Blizzard Style everywhere a base style is
-- asked for (module seeds, the whole-UI font slots, Active()); the window
-- slots are the exception, where it is a look of its own.
local function StockBase(styleKey)
    if styleKey == "forever" then return "blizzard" end
    return styleKey
end

-- Profile flags -> style key and back. The Classic flag wins a read when both
-- are set; a write sets exactly one of them (or neither, for cui). The Forever
-- flag (nil off the Forever client) only ever rides a set Blizzard flag.
local function StyleKeyOf(profile, flag, classicFlag, foreverFlag)
    if not profile then return "cui" end
    if profile[classicFlag] then return "classic" end
    if profile[flag] then
        if foreverFlag and profile[foreverFlag] then return "forever" end
        return "blizzard"
    end
    return "cui"
end
local function FlagAccessors(profileFn, flag, classicFlag, foreverFlag)
    return function() return StyleKeyOf(profileFn(), flag, classicFlag, foreverFlag) end, function(styleKey)
        local p = profileFn()
        if p then
            p[flag] = (styleKey == "blizzard" or styleKey == "forever") or false
            p[classicFlag] = (styleKey == "classic") or false
            -- Never a default written: set while chosen, cleared otherwise.
            if foreverFlag then
                if styleKey == "forever" then
                    p[foreverFlag] = true
                else
                    p[foreverFlag] = nil
                end
            end
        end
    end
end

-- The style a module is RENDERING this session: its latched key getter on
-- the module ns ("cui" while the module is not loaded). Action Bars has no
-- latch and reads its profile flags instead (the Forever variant as
-- "blizzard", like every latch).
local function ActiveFn(folder, fnName)
    return function()
        local num = ModuleNS(folder)
        local func = num and num[fnName]
        local val = func and func()
        if val == "blizzard" or val == "classic" then return val end
        return "cui"
    end
end

-- WoW Forever: the module getter that says whether the variant renders this
-- session, for the modules whose variant draws differently (latched with the
-- style; Action Bars reads its flags live like AB_Style). A module missing
-- here draws Blizzard Style under the variant.
local FOREVER_LATCH = {
    actionbars = "AB_Forever",
    unitframes = "UF_Forever",
    nameplates = "NP_Forever",
    minimap = "MinimapForever",
    cdmicons = "CdmIconsForever",
    cdmbars = "CdmBarsForever",
    castbar = "ERB_CastForever",
    damagemeters = "DMForever",
    chat = "ChatForever",
    threatmeter = "TM_Forever",
}

local MODULES = {}
local BY_KEY = {}
-- onEnable (optional): the style's defaults, run on the profile the first
-- time the module switches to that stock style (before the reload) as
-- onEnable(p, styleKey, isForever): styleKey is "blizzard" or "classic" (the
-- WoW Forever variant passes "blizzard" with isForever true). A later visit
-- loads the style's saved slot instead (see the per-style slots below).
local function Register(key, folder, display, profileFn, flag, classicFlag, activeFnName, onEnable)
    -- The Forever sibling flag, on the Forever client only.
    local foreverFlag = IS_FOREVER and (flag:gsub("Blizzard", "Forever", 1)) or nil
    local get, set = FlagAccessors(profileFn, flag, classicFlag, foreverFlag)
    local m = {
        key = key,
        folder = folder,
        display = display,
        get = get,
        set = set,
        active = activeFnName and ActiveFn(folder, activeFnName) or function() return StockBase(get()) end,
        profile = profileFn,
        onEnable = onEnable,
        foreverFlag = foreverFlag,
        foreverLatch = foreverFlag and FOREVER_LATCH[key] or nil,
    }
    MODULES[#MODULES + 1] = m
    BY_KEY[key] = m
end

Register("actionbars", "CludesUIActionBars", "Action Bars", ABProfile, "useBlizzardStyle", "useClassicStyle")
Register(
    "unitframes",
    "CludesUIUnitFrames",
    "Unit Frames",
    UFProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "UF_Style",
    -- Either stock style seeds the "Blizzard" cast fill as the cast bar
    -- texture once per profile, and the player frame's combat indicator in
    -- the style's own icon on the portrait per switch; Classic also seeds
    -- the Plating health bar texture once per profile (the module's own
    -- seed; it also runs at enable for a profile that arrives already
    -- switched). WoW Forever's own seed rides its Forever-only slots below.
    function(p, styleKey)
        local uf = ModuleNS("CludesUIUnitFrames")
        if uf and uf.UF_SeedStock then uf.UF_SeedStock(p, styleKey) end
    end
)
Register(
    "playerauras",
    "CludesUIUnitFrames",
    "Player Aura Bars",
    PABProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "PAB_Style"
)
Register(
    "nameplates",
    "CludesUINameplates",
    "Nameplates",
    NPProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "NP_Style",
    -- Either stock style seeds the game's own nameplate bar fill on the
    -- health and cast bars once per profile; Classic also seeds the vanilla
    -- cast background and a light uninterruptible grey (the module's own
    -- seeds; they also run at enable for a profile that arrives already
    -- switched). WoW Forever's own seed rides its Forever-only slots below.
    function(p, styleKey)
        local np = ModuleNS("CludesUINameplates")
        if np and np.NP_SeedStock then np.NP_SeedStock(p) end
        if styleKey == "classic" and np and np.NP_SeedClassic then np.NP_SeedClassic(p) end
    end
)
Register(
    "cdmicons",
    "CludesUICooldownManager",
    "Cooldown Manager Icons",
    CDMProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "CdmIconStyle"
)
Register(
    "cdmbars",
    "CludesUICooldownManager",
    "Tracked Buff Bars",
    CDMProfile,
    "useBlizzardStyleBars",
    "useClassicStyleBars",
    "CdmBarStyle"
)
Register(
    "castbar",
    "CludesUIResourceBars",
    "Player Cast Bar",
    CastBarProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "ERB_CastStyle",
    -- Either stock style seeds the "Blizzard" fill as the bar texture once
    -- per profile (the module's own seed; it also runs at enable for a
    -- profile that arrives already switched).
    function(p)
        local erb = ModuleNS("CludesUIResourceBars")
        if erb and erb.ERB_SeedStockCast then erb.ERB_SeedStockCast(p) end
    end
)
Register(
    "resourcebars",
    "CludesUIResourceBars",
    "Resource Bars",
    ERBProfile,
    "useBlizzardStyleBars",
    "useClassicStyleBars",
    "ERB_BarsStyle",
    -- Classic WoW UI turns Border Around All on when the shown bars already
    -- sit as one anchored stack, and seeds the "Plating" bar texture, once
    -- per profile (the module's own seed; it also runs at enable for a
    -- profile that arrives already switched).
    function(p, styleKey)
        local erb = ModuleNS("CludesUIResourceBars")
        if erb and erb.ERB_SeedStockBars then erb.ERB_SeedStockBars(p, styleKey) end
    end
)
Register(
    "minimap",
    "CludesUIMinimap",
    "Minimap",
    MinimapProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "MinimapStyle",
    -- Either stock style, at each switch (the controls stay the user's
    -- afterwards): the Omnium Folio on the ring's bottom right spot (WoW
    -- Forever builds no folio), and the clock inside the map at the top,
    -- 10px down, or, on a square (the WoW Forever look's Forever Square, its
    -- default there, or Slim Square, or Blizzard Style's Square on the Forever
    -- client, its default there), at the map's bottom with no offset, its title bar
    -- holding the zone name up top. The Border Style rows move the clock the
    -- same way when a pick changes. Classic WoW UI also centres the zone text
    -- in the banner's text slot (its X/Y offsets back to 0).
    function(profile, styleKey, isForever)
        if not CUI.IS_FOREVER then profile.omniumFolioCorner = "BOTTOMRIGHT" end
        local square
        if isForever then
            if profile.foreverBorder == "slim" then
                square = CUI.ForeverBorderOK()
            else
                square = profile.foreverBorder ~= "circle" and CUI.ForeverHeavyOK()
            end
        else
            square = styleKey == "blizzard" and CUI.IS_FOREVER and profile.blizzBorder ~= "circle"
        end
        if square then
            profile.clockMode, profile.clockPosition, profile.clockOffsetY = "inside", "bottom", 0
        else
            profile.clockMode, profile.clockPosition, profile.clockOffsetY = "inside", "top", -10
        end
        if styleKey == "classic" then
            profile.locationOffsetX, profile.locationOffsetY = 0, 0
        end
    end
)
Register(
    "damagemeters",
    "CludesUIDamageMeters",
    "Damage Meters",
    DMProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "DMStyle",
    -- The stock panel reads best lighter: the first switch to Blizzard Style
    -- seeds Background Opacity at 0.4 (once per profile; the slider stays
    -- the user's), WoW Forever at the chat panel's 0.65 (both wear the same
    -- bronze frame). The first switch to Classic WoW UI runs the module's own
    -- seed (the near-black window, the quarter-black bar track; once per
    -- profile, the module also runs it at login for a profile that arrives
    -- already switched).
    function(profile, styleKey, isForever)
        if styleKey == "blizzard" and not profile.blizzBgAlphaSeeded then
            profile.blizzBgAlphaSeeded = true
            profile.bgAlpha = isForever and 0.65 or 0.4
        elseif styleKey == "classic" then
            local dm = CUI._ModuleNS and CUI._ModuleNS.CludesUIDamageMeters
            if dm and dm.DMSeedClassic then dm.DMSeedClassic(profile) end
        end
    end
)
-- The threat meter exists only on WoW Forever (Forever Essentials). Its
-- settings are account-wide (CludesUIDB.threatMeter), so its flags, slots
-- and seed stamps live in that table, not in a profile: a profile switch
-- never changes its look, and Apply to All and the first-install picker set
-- it for the whole account. The row reads without creating the table
-- (opening this page writes nothing); a style write creates it. nil while
-- Forever Essentials is disabled.
if CUI.IS_FOREVER then
    local function TMStore(create)
        if not ModuleNS("CludesUIForeverEssentials") or not CludesUIDB then return nil end
        local t = CludesUIDB.threatMeter
        if type(t) ~= "table" then
            if not create then return nil end
            t = {}
            CludesUIDB.threatMeter = t
        end
        return t
    end
    Register(
        "threatmeter",
        "CludesUIForeverEssentials",
        "Threat Meter",
        function() return TMStore(true) end,
        "useBlizzardStyle",
        "useClassicStyle",
        "TM_Style",
        -- The module's own seeds, once each: Blizzard Style's lighter window
        -- (WoW Forever's at the Damage Meters variant's 0.65), Classic WoW UI's
        -- near-black window and quarter-black bar track (the module also runs
        -- Classic's at login for a table that arrives already switched).
        function(p, styleKey, isForever)
            local fe = ModuleNS("CludesUIForeverEssentials")
            if fe and fe.TM_SeedStock then fe.TM_SeedStock(p, styleKey, isForever) end
        end
    )
    BY_KEY.threatmeter.get = FlagAccessors(
        function() return TMStore(false) end,
        "useBlizzardStyle",
        "useClassicStyle",
        BY_KEY.threatmeter.foreverFlag
    )
    BY_KEY.threatmeter.enableName = "Forever Tools"
end
Register(
    "questtracker",
    "CludesUIQuestTracker",
    "Quest Tracker",
    QTProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "QT_Style"
)
Register("chat", "CludesUIChat", "Chat", ChatProfile, "useBlizzardStyle", "useClassicStyle", "ChatStyle")
-- Bags has only the Forever art so far. While a profile has no Bags style
-- picked, Bags follows the look most of its modules use (the Bags ns'
-- BagsForeverWanted), so the first-install look reaches it with no write and
-- ApplyAll leaves it out; a pick here is saved either way (false = the
-- CludesUI style), so it holds against that majority.
if IS_FOREVER then
    local function BagsProfileOf()
        local db = CUI._bagsDB
        return db and db.profile
    end
    local bags = {
        key = "bags",
        folder = "CludesUIBags",
        display = "Bags",
        styles = { cui = true, forever = true },
        firstInstall = false,
        profile = BagsProfileOf,
        foreverFlag = "useForeverStyle",
        foreverLatch = "BagsForever",
        get = function()
            local p = BagsProfileOf()
            local num = p and ModuleNS("CludesUIBags")
            return (num and num.BagsForeverWanted(p)) and "forever" or "cui"
        end,
        set = function(styleKey)
            local p = BagsProfileOf()
            if p then p.useForeverStyle = (styleKey == "forever") end
        end,
        active = function()
            local num = ModuleNS("CludesUIBags")
            return num and num.BagsForever and num.BagsForever() and "blizzard" or "cui"
        end,
    }
    MODULES[#MODULES + 1] = bags
    BY_KEY.bags = bags
end
-- One row covers raid, party (in its Raid Frames layout), Friendly Boss and
-- Extra Frames, on both clients (WoW Forever draws Blizzard Style here).
-- Either stock style's first visit seeds the stock raid fill (the 12.1 flat
-- fill, or Classic's Blizzard Raid Bar), flush spacing, the stock role icons
-- and absorb looks (the module's own seed; it also runs at enable for a
-- profile that arrives already switched).
Register(
    "raidframes",
    "CludesUIRaidFrames",
    "Raid & Party Frames",
    RFProfile,
    "useBlizzardStyle",
    "useClassicStyle",
    "RF_Style",
    function(p, styleKey)
        local rf = ModuleNS("CludesUIRaidFrames")
        if rf and rf.RF_SeedStock then rf.RF_SeedStock(p, styleKey) end
    end
)
if not CUI.IS_FOREVER then
    -- WoW Forever has no skyriding (no HUD, no row there).
    Register(
        "dragonriding",
        "CludesUIBlizzardSkin",
        "Skyriding HUD",
        DragonRidingProfile,
        "useBlizzardStyle",
        "useClassicStyle",
        "EDR_Style"
    )
    BY_KEY.dragonriding.enableName = "Window Skins"
    -- The Friends List module never loads on WoW Forever (no row there).
    Register(
        "friends",
        "CludesUIFriends",
        "Friends List",
        FriendsProfile,
        "useBlizzardStyle",
        "useClassicStyle",
        "FR_Style"
    )
end

-------------------------------------------------------------------------------
--  Per-style slots. Every setting a style's defaults write (the onEnable
--  seeds above) is kept once per style: switching a module from style A to
--  style B saves those keys into A's slot and loads B's, so each look comes
--  back exactly as it was left, tweaks included. The first visit to a style
--  has no slot: a stock style clears its "seeded" markers and runs its
--  defaults (onEnable), the CludesUI look clears the keys back to the
--  install defaults (the reload every switch ends in refills them from the
--  module's defaults). A slot holds these keys only, in the module's own
--  profile table (p._styleSlots), so it follows profile copies and imports.
--  keys: dotted paths into the module's profile table;
--  stamps: the markers that make a seed once per profile; seededBy(key):
--  the stamp whose seed writes that key (true = only this build ever writes
--  it, nil = no seed does). A first visit to the CludesUI look with no
--  saved slot (a profile from before the slots) clears only the keys whose
--  stamp is set: every other value there is still the user's own.
-------------------------------------------------------------------------------
local SLOT_KEYS = {
    unitframes = {
        stamps = { "stockCastTextureSeeded", "classicTextureSeeded", "stockCombatSeededStyle" },
        keys = function()
            local keyName = {
                "castBarTexture",
                "healthBarTexture",
                "player.combatIndicatorStyle",
                "player.combatIndicatorPosition",
            }
            local uf = ModuleNS("CludesUIUnitFrames")
            local units = uf and uf.UF_TEXTURE_UNITS
            if units then
                for idx = 1, #units do
                    keyName[#keyName + 1] = units[idx] .. ".healthBarTexture"
                end
            end
            return keyName
        end,
        seededBy = function(key)
            if key == "castBarTexture" then return "stockCastTextureSeeded" end
            if key:find("combatIndicator", 1, true) then return "stockCombatSeededStyle" end
            return "classicTextureSeeded"
        end,
    },
    nameplates = {
        stamps = { "stockBarTextureSeeded", "classicCastSeeded" },
        keys = {
            "healthBarTexture",
            "castBarTexture",
            "castBgColor",
            "castBgAlpha",
            "castBarUninterruptible",
        },
        seededBy = function(key)
            if key == "healthBarTexture" or key == "castBarTexture" then return "stockBarTextureSeeded" end
            return "classicCastSeeded"
        end,
    },
    castbar = {
        stamps = { "stockTextureSeeded" },
        keys = { "texture" },
        prefix = "castBar",
        seededBy = function() return "stockTextureSeeded" end,
    },
    -- Border Around All (one key set shared by both stock styles) rides the
    -- slots too, so each style keeps its own choice. So do the health and power
    -- bars' own textures (the Texture cog) with splitTex, which keeps them in
    -- effect (the Classic seed writes those). splitTex shares their stamp so a first
    -- CludesUI visit with no saved slot clears it with them: one texture,
    -- never the split with empty per-bar keys.
    resourcebars = {
        stamps = { "general.classicTextureSeeded", "general.borderAllSeeded" },
        keys = {
            "general.barTexture",
            "splitTex",
            "health.barTexture",
            "primary.barTexture",
            "general.classicBorderAll",
            "general.classicBorderAllSepSize",
            "general.classicBorderAllSepR",
            "general.classicBorderAllSepG",
            "general.classicBorderAllSepB",
        },
        seededBy = function(key)
            if key == "swingTimer.texture" then return "swingTimer.classicTextureSeeded" end
            if key == "splitTex" or key:find("barTexture", 1, true) then
                return "general.classicTextureSeeded"
            end
            return true
        end,
    },
    damagemeters = {
        stamps = { "blizzBgAlphaSeeded", "classicSeeded" },
        keys = {
            "bgAlpha",
            "bgR",
            "bgG",
            "bgB",
            "barTexture",
            "barBgR",
            "barBgG",
            "barBgB",
            "barBgAlpha",
            "barBgUseClassColor",
        },
        seededBy = function(key)
            if key == "bgAlpha" then return "blizzBgAlphaSeeded" end
            return "classicSeeded"
        end,
    },
    minimap = {
        keys = {
            "omniumFolioCorner",
            "clockMode",
            "clockPosition",
            "clockOffsetY",
            "locationOffsetX",
            "locationOffsetY",
        },
    },
    -- The Party page's Frame Style and the Party Frames layout's own scale
    -- and spacing ride the slots too, so each stock style keeps its own
    -- (they exist only under a stock style: back to CludesUI clears them).
    raidframes = {
        stamps = { "stockRaidSeeded" },
        keys = {
            "healthBarTexture",
            "party_healthBarTexture",
            "cellSpacing",
            "groupSpacing",
            "partyCellSpacing",
            "roleIconStyle",
            "party_roleIconStyle",
            "absorbStyle",
            "party_absorbStyle",
            "absorbOpacity",
            "party_absorbOpacity",
            "absorbGlowLine",
            "party_absorbGlowLine",
            "healAbsorbStyle",
            "party_healAbsorbStyle",
            "partyFrameStyle",
            "partyKitScale",
            "partyKitSpacing",
            "partyKitDebuffSize",
            "partyKitDebuffX",
            "partyKitDebuffY",
            "partyKitBuffSize",
            "partyKitBuffX",
            "partyKitBuffY",
            "partyKitBuffAnchor",
        },
        seededBy = function(key)
            if key == "partyFrameStyle" or key:find("^partyKit") then return true end
            return "stockRaidSeeded"
        end,
    },
}
-- The threat meter's seeds write into its appearance groups, two levels down
-- in its account table; the stamps sit at the top.
if CUI.IS_FOREVER then
    SLOT_KEYS.threatmeter = {
        stamps = { "blizzBgAlphaSeeded", "classicSeeded" },
        keys = {
            "appearance.colors.bgAlpha",
            "appearance.colors.bgR",
            "appearance.colors.bgG",
            "appearance.colors.bgB",
            "appearance.bars.barTexture",
            "appearance.colors.barBgR",
            "appearance.colors.barBgG",
            "appearance.colors.barBgB",
            "appearance.colors.barBgAlpha",
            "appearance.colors.barBgUseClassColor",
        },
        seededBy = function(key)
            if key == "appearance.colors.bgAlpha" then return "blizzBgAlphaSeeded" end
            return "classicSeeded"
        end,
    }
    -- The Swing Timer follows the Resource Bars row: its texture (the Classic
    -- seed's, under a stamp of its own) rides that row's slots.
    local rb = SLOT_KEYS.resourcebars
    rb.keys[#rb.keys + 1] = "swingTimer.texture"
    rb.stamps[#rb.stamps + 1] = "swingTimer.classicTextureSeeded"
end
-- WoW Forever's own seeds (the Nameplates Left Text its level box stands in
-- for and the Elite/Rare Indicator box it starts unchecked, the Unit Frames
-- class resource its combo point arc takes) swap only
-- across the variant (foreverOnly), in a spec of their own (m.fvSlots) kept
-- apart from the module's slots above (store): the other looks share one
-- "cui" slot for them, banked on the way in and restored on the way out, and
-- the variant keeps none, so every visit seeds them again (seed). A switch
-- between the other looks never touches them. The modules bank the same
-- store at enable for a profile that arrives already switched.
if IS_FOREVER then
    local FOREVER_SLOT_KEYS = {
        nameplates = {
            keys = { "textSlotLeft", "classificationHideRare" },
            stamps = { "foreverLevelSlotSeeded", "foreverRareSeeded" },
            seededBy = function(key)
                if key == "classificationHideRare" then return "foreverRareSeeded" end
                return "foreverLevelSlotSeeded"
            end,
            seed = function(p)
                local num = ModuleNS("CludesUINameplates")
                if num and num.NP_SeedForever then num.NP_SeedForever(p) end
            end,
        },
        unitframes = {
            keys = { "player.classPowerStyle", "player.showClassPowerBar" },
            stamps = { "foreverClassPowerSeeded" },
            seededBy = function() return "foreverClassPowerSeeded" end,
            seed = function(p)
                local num = ModuleNS("CludesUIUnitFrames")
                if num and num.UF_SeedForever then num.UF_SeedForever(p) end
            end,
        },
    }
    for key, specInfo in pairs(FOREVER_SLOT_KEYS) do
        specInfo.foreverOnly, specInfo.store = true, "_foreverStyleSlots"
        BY_KEY[key].fvSlots = specInfo
    end
    -- Action Bars' queue eye position swaps only across the variant
    -- (foreverOnly): the other looks share one spot as before, banked on the
    -- way in and restored on the way out, and the variant keeps none, so
    -- every visit clears it and the eye goes back onto the minimap's ring (a
    -- drag there wins until the look changes).
    SLOT_KEYS.actionbars = { keys = { "barPositions.QueueStatus" }, foreverOnly = true }
    BY_KEY.actionbars.onEnable = function(profile, _, isForever)
        if isForever and type(profile.barPositions) == "table" then profile.barPositions.QueueStatus = nil end
    end
end
for key, specInfo in pairs(SLOT_KEYS) do
    if BY_KEY[key] then BY_KEY[key].slots = specInfo end
end

-- A missing table on the way reads nil and makes a write a no-op.
local function PathGet(tbl, filePath)
    local a, b = filePath:match("^([^.]+)%.(.+)$")
    if not a then return tbl[filePath] end
    local s = tbl[a]
    if type(s) ~= "table" then return nil end
    return PathGet(s, b)
end
local function PathSet(tbl, filePath, val)
    local a, b = filePath:match("^([^.]+)%.(.+)$")
    if not a then
        tbl[filePath] = val
        return
    end
    local s = tbl[a]
    if type(s) == "table" then PathSet(s, b, val) end
end

-- The slot keys a spec or conditional override holds (spec.prefix = the
-- module profile's subtable path, e.g. the cast bar's): nil when none.
local function OverriddenKeys(m, specInfo, keyList)
    local isCap = CUI.SpecOverrides_IsCaptured
    if not isCap then return nil end
    local pre, entries = specInfo.prefix, nil
    for idx = 1, #keyList do
        local filePath = keyList[idx]
        local a, b = filePath:match("^([^.]+)%.(.+)$")
        local hit
        if pre then
            if a then
                hit = isCap(m.folder, pre, a, b)
            else
                hit = isCap(m.folder, pre, filePath)
            end
        elseif a then
            hit = isCap(m.folder, a, b)
        else
            hit = isCap(m.folder, filePath)
        end
        if hit then
            entries = entries or {}
            entries[#entries + 1] = filePath
        end
    end
    return entries
end

-- One slot spec's swap for module `m` going `from` -> `to` on its profile
-- `p` (see SwitchModuleStyle). Returns whether a saved slot loaded, then the
-- keys a spec or conditional override holds and their live values.
local function SwapSlots(m, profile, specInfo, from, to)
    -- The slots the swap reads and writes: the looks themselves, except for
    -- a foreverOnly spec, whose non-Forever looks share the "cui" slot.
    local fromK, toK = from, to
    if specInfo.foreverOnly then
        if from ~= "forever" then fromK = "cui" end
        if to ~= "forever" then toK = "cui" end
    end
    if fromK == toK then return false end
    local loaded = false
    local keep, keepVals
    local keyList = specInfo.keys
    if type(keyList) == "function" then keyList = keyList() end
    keep = OverriddenKeys(m, specInfo, keyList)
    if keep then
        keepVals = {}
        for idx = 1, #keep do
            keepVals[idx] = PathGet(profile, keep[idx])
        end
    end
    local stamps = specInfo.stamps
    local storage = specInfo.store or "_styleSlots"
    local slots = profile[storage]
    if type(slots) ~= "table" then
        slots = {}
        profile[storage] = slots
    end
    local result = {}
    for idx = 1, #keyList do
        result[keyList[idx]] = PathGet(profile, keyList[idx])
    end
    if stamps then
        for idx = 1, #stamps do
            result[stamps[idx]] = PathGet(profile, stamps[idx])
        end
    end
    if not (specInfo.foreverOnly and fromK == "forever") then slots[fromK] = result end
    local saved = slots[toK]
    if type(saved) == "table" then
        loaded = true
        for idx = 1, #keyList do
            PathSet(profile, keyList[idx], saved[keyList[idx]])
        end
        if stamps then
            for idx = 1, #stamps do
                PathSet(profile, stamps[idx], saved[stamps[idx]])
            end
        end
    else
        if toK == "cui" then
            -- Only what a seed wrote goes back to the install default
            -- (read before the stamps clear below).
            local by = specInfo.seededBy
            if by then
                for idx = 1, #keyList do
                    local st = by(keyList[idx])
                    if st == true or (st and PathGet(profile, st)) then
                        PathSet(profile, keyList[idx], nil)
                    end
                end
            end
        elseif fromK ~= "cui" then
            -- From another stock style: start from the CludesUI
            -- look's values, so a first visit gives the same result
            -- whichever look it is reached from. A profile that reached
            -- its first stock style before the slots existed never banked
            -- that look: bank it now as the CludesUI first visit would
            -- leave the profile (what a seed wrote goes back to the install
            -- default, read before the stamps clear below), so the return
            -- to CludesUI can load it instead of keeping this style's
            -- seeds.
            local base = slots.cui
            if type(base) ~= "table" then
                base = {}
                local by = specInfo.seededBy
                for idx = 1, #keyList do
                    local keyName = keyList[idx]
                    local st = by and by(keyName)
                    if not (st == true or (st and PathGet(profile, st))) then
                        base[keyName] = PathGet(profile, keyName)
                    end
                end
                slots.cui = base
            end
            for idx = 1, #keyList do
                PathSet(profile, keyList[idx], base[keyList[idx]])
            end
        end
        if stamps then
            for idx = 1, #stamps do
                PathSet(profile, stamps[idx], nil)
            end
        end
    end
    return loaded, keep, keepVals
end

-- One module to `to`: its slots swap, then its flags. Every Style write goes
-- through here (a row, Apply to All, the first-install picker). A setting a
-- spec or conditional override holds keeps its live value through all of
-- it: the override wins over both a saved slot and a style's defaults.
local function SwitchModuleStyle(m, to)
    local p = m.profile and m.profile()
    local from = m.get()
    if from == to then return end
    local loaded, keep, keepVals = false, nil, nil
    if p and m.slots then
        loaded, keep, keepVals = SwapSlots(m, p, m.slots, from, to)
    end
    -- WoW Forever's own spec (the Forever client only; it swaps only into
    -- or out of the variant).
    local fv = m.fvSlots
    local fvLoaded, fvKeep, fvKeepVals = false, nil, nil
    if p and fv then
        fvLoaded, fvKeep, fvKeepVals = SwapSlots(m, p, fv, from, to)
    end
    m.set(to)
    -- A style's defaults run only on its first visit: a loaded slot already
    -- holds what the user had there. WoW Forever keeps its own slot and runs
    -- Blizzard Style's defaults (told it is the variant), and its own seed
    -- on every visit (its Forever-only slot is never banked).
    if p and to ~= "cui" and m.onEnable and not loaded then m.onEnable(p, StockBase(to), to == "forever") end
    if p and fv and to == "forever" and not fvLoaded then fv.seed(p) end
    if keep then
        for idx = 1, #keep do
            PathSet(p, keep[idx], keepVals[idx])
        end
    end
    if fvKeep then
        for idx = 1, #fvKeep do
            PathSet(p, fvKeep[idx], fvKeepVals[idx])
        end
    end
end

-- The stock style most loaded modules use ("blizzard" on a tie or none):
-- names the look a font or window record from before the slots belongs to.
-- WoW Forever counts as Blizzard Style (it shares that look's font slot, and
-- such records predate its own window slot).
local function GuessStockStyle()
    local b, c = 0, 0
    for idx = 1, #MODULES do
        local module = MODULES[idx]
        if ModuleNS(module.folder) ~= nil then
            local keyName = StockBase(module.get())
            if keyName == "blizzard" then
                b = b + 1
            elseif keyName == "classic" then
                c = c + 1
            end
        end
    end
    return (c > b) and "classic" or "blizzard"
end

-------------------------------------------------------------------------------
--  Shared helpers (CludesUI.BlizzStyle)
-------------------------------------------------------------------------------

local BlizzStyle = {}
CUI.BlizzStyle = BlizzStyle

local STYLE_VALUES = { cui = "CludesUI Style", blizzard = "Blizzard Style", classic = "Classic WoW UI" }
-- The WoW Forever variant exists on the Forever client only.
if IS_FOREVER then STYLE_VALUES.forever = "WoW Forever" end

local function SupportsStyle(m, styleKey) return not m.styles or m.styles[styleKey] end

-- The style the module currently RENDERS (its session latch, not the profile
-- flags): "cui", "blizzard" or "classic" -- "blizzard" under the WoW Forever
-- variant too (ask Forever()). "cui" for unknown keys and for disabled
-- modules.
function BlizzStyle.Active(key)
    local m = BY_KEY[key]
    return m and m.active() or "cui"
end
-- True when the module renders the WoW Forever variant of Blizzard Style
-- this session (always false off the Forever client): its latched Forever
-- getter; a module with no Forever-only pieces draws Blizzard Style either
-- way and answers from its flags, so its gates and banner name the look
-- that was picked.
function BlizzStyle.Forever(key)
    local m = BY_KEY[key]
    if not (m and m.foreverFlag) or m.active() ~= "blizzard" then return false end
    local latch = m.foreverLatch
    if latch then
        local num = ModuleNS(m.folder)
        local func = num and num[latch]
        return (func ~= nil and func()) and true or false
    end
    return m.get() == "forever"
end
-- The display name of the rendering style (the requirement text on gated rows).
function BlizzStyle.Label(key)
    if BlizzStyle.Forever(key) then return STYLE_VALUES.forever end
    return STYLE_VALUES[BlizzStyle.Active(key)] or STYLE_VALUES.cui
end
-- True when a stock look (Blizzard Style or Classic WoW UI) dictates the
-- module's geometry this session: the question every gate asks. False for
-- unknown keys and for disabled modules.
function BlizzStyle.Get(key) return BlizzStyle.Active(key) ~= "cui" end
-- A style chosen for the whole UI at once (the first-install picker, Apply to
-- All) also swaps the global font through per-style slots in the per-profile
-- fonts DB (fonts._styleSlots: `active` = the look whose font is live, plus
-- one { global } per look). First visit to a look: the stock styles take
-- Blizzard Default in place of the install default Expressway, and the
-- CludesUI look takes Expressway back from Blizzard Default; any other
-- font stays. Glyph-restricted locales already render the client's own font,
-- so nothing changes there. Both callers reload right after. WoW Forever
-- shares Blizzard Style's font slot (the same stock font).
-- legacy: the stock look a record from before the slots belongs to, taken
-- before any module flag changes (nil = infer it now).
local function FontSlots(legacy)
    if CUI.LOCALE_FONT_FALLBACK or not CUI.GetFontsDB then return nil end
    local db = CUI.GetFontsDB()
    local s = db._styleSlots
    if type(s) ~= "table" then
        -- A one-way seed from before the slots (fontStockSeeded): the live
        -- font belongs to a stock look, and Expressway was the one it replaced.
        if db.fontStockSeeded then
            s = { active = legacy or GuessStockStyle(), cui = { global = "Expressway" } }
        else
            s = { active = "cui" }
        end
    end
    return db, s
end
local function FontPending(styleKey)
    local db, s = FontSlots()
    return db ~= nil and (s.active or "cui") ~= StockBase(styleKey)
end
local function ApplyWholeUIFont(styleKey, legacy)
    styleKey = StockBase(styleKey)
    local db, s = FontSlots(legacy)
    if not db then return end
    local from = s.active or "cui"
    if from == styleKey then return end
    s[from] = { global = db.global }
    local saved = s[styleKey]
    if type(saved) == "table" and saved.global then
        db.global = saved.global
    else
        local blizz = CUI.BLIZZARD_FONT_KEY or "__blizzard"
        local current = db.global or CUI.DEFAULT_FONT_NAME
        if styleKey ~= "cui" then
            if current == CUI.DEFAULT_FONT_NAME then db.global = blizz end
        elseif current == blizz then
            db.global = CUI.DEFAULT_FONT_NAME
        end
    end
    s.active = styleKey
    db._styleSlots = s
    db.fontStockSeeded = nil
    CUI.InvalidateFontCache()
end
-- The same two callers also swap the Blizz UI Enhanced window skins through
-- their own per-style slots (CludesUI.SwapWindowSkinStyle: first visit
-- to a stock style = every window at Blizz Default, the character sheet's
-- with the CludesUI features it keeps there). A style picks only these
-- defaults: each window's own card decides how it renders. A disabled Blizz
-- UI Enhanced module has no swapper and is left
-- alone. The look is the active PROFILE's (profile-root windowSkinLook), so
-- the account's windows swap back to each profile's look on a profile switch
-- (CludesUI.ReconcileWindowSkinLook). WoW Forever has a window slot of
-- its own, whose first visit skins every window as the CludesUI look's
-- does but the micro menu and the bag bar (Blizz Default); a window look
-- recorded before that slot existed stays as it is.
local function WholeUIWindowsPending(styleKey)
    local swap = CUI.SwapWindowSkinStyle
    return swap ~= nil and swap(styleKey, true, GuessStockStyle())
end
local function ApplyWholeUIWindows(styleKey, legacy)
    local swap = CUI.SwapWindowSkinStyle
    if not swap then return end
    swap(styleKey, false, legacy or GuessStockStyle())
    local prof = CUI.GetActiveProfileData()
    if prof then prof.windowSkinLook = styleKey end
end

-- Every loaded module taking part in first-install, no prompt: the first-install
-- style picker (CludesUI_StyleChoicePopup.lua) writes the flags and
-- reloads itself, and on the Forever client so does the module picker (the
-- WoW Forever look a fresh install starts on, written as its reload is
-- confirmed). The same writes as Apply to All's confirm; a module with no
-- profile (disabled at the picker) is left alone. The first-install stamp
-- is its callers' to settle. Takes a style key (true stands for blizzard,
-- false for cui; "forever" only on the Forever client, cui elsewhere).
function BlizzStyle.ApplyAll(styleKey)
    if styleKey == true then
        styleKey = "blizzard"
    elseif not STYLE_VALUES[styleKey] then
        styleKey = "cui"
    end
    local legacy = GuessStockStyle()
    for idx = 1, #MODULES do
        local module = MODULES[idx]
        if module.firstInstall ~= false and SupportsStyle(module, styleKey) and module.profile() then
            SwitchModuleStyle(module, styleKey)
        end
    end
    ApplyWholeUIFont(styleKey, legacy)
    ApplyWholeUIWindows(styleKey, legacy)
end
-- The rendered style never changes during a session, so gating a row is a
-- build-time decision: when a stock style is active the row is disabled
-- with the standard requirement tooltip naming it. Returns cfg for inline use.
function BlizzStyle.Gate(key, rowConf, keepRow)
    if not rowConf or not BlizzStyle.Get(key) then return rowConf end
    rowConf.disabled = function() return true end
    rowConf.disabledTooltip = BlizzStyle.Label(key)
    rowConf.requireState = "disabled"
    rowConf.rawTooltip = nil
    rowConf._blizzGated = true
    -- keepRow: an inline control hung on this slot (a cog) still works under
    -- the style, so the row must stay on the page even if fully gated.
    rowConf._blizzKeepRow = keepRow or nil
    return rowConf
end

-- Classic WoW UI: a bar's Border Size slider, which sizes the vanilla frame
-- round it as a percentage of the frame's full size (CludesUI.ClassicFrame.
-- BORDER_DEFAULT when unset). get() returns the stored percentage (nil =
-- default); set(v) stores it (nil for the default) and repaints. opts, when
-- given, carries disabled / disabledTooltip. Returns the slider cfg.
function BlizzStyle.ClassicBorderSizeCfg(get, set, options)
    local CF = CUI.ClassicFrame
    local def = (CF and CF.BORDER_DEFAULT) or 60
    return {
        type = "slider",
        text = "Border Size",
        min = 25,
        max = 100,
        step = 5,
        tooltip = "Size of the Classic frame around the bar.",
        disabled = options and options.disabled,
        disabledTooltip = options and options.disabledTooltip,
        getValue = function() return get() or def end,
        setValue = function(val) set((val ~= def) and val or nil) end,
    }
end

-- A slot's gate state: nil = blank (no control: nil, spacer, empty label),
-- true = gated for the active style (a multiSwatch counts when every swatch
-- is), false = a live control.
local function SlotGated(rowConf)
    if not rowConf then return nil end
    local t = rowConf.type
    if t == "spacer" or (t == "label" and (rowConf.text == nil or rowConf.text == "")) then return nil end
    if rowConf._blizzGated then return true end
    if t == "multiSwatch" and rowConf.swatches then
        local num = #rowConf.swatches
        for idx = 1, num do
            if not rowConf.swatches[idx]._blizzGated then return false end
        end
        return num > 0
    end
    return false
end

-- A row whose every control is gated for the active style is not shown at
-- all: the widget factory builds it (callers still hang cogs and sync icons
-- on its regions) but hides it and gives it no height. Blank slots do not
-- count; one live control keeps the row, its gated neighbour disabled.
function BlizzStyle.RowHidden(a, b, cfg)
    if (a and a._blizzKeepRow) or (b and b._blizzKeepRow) or (cfg and cfg._blizzKeepRow) then return false end
    local ga, gb, gc = SlotGated(a), SlotGated(b), SlotGated(cfg)
    if ga == false or gb == false or gc == false then return false end
    return (ga or gb or gc) and true or false
end

-- Inline widget (swatch, cog) with no disabled state of its own: dims it and
-- blocks clicks with the standard requirement tooltip while a stock style is
-- active for the module. No-op otherwise, so existing pages are untouched.
function BlizzStyle.BlockInline(key, widget, dimAlpha)
    -- The search prebuild only indexes rows: no blocker (the widget is a stand-in there).
    if CUI._prebuilding then return false end
    if not widget or not BlizzStyle.Get(key) then return false end
    widget:SetAlpha(dimAlpha or 0.3)
    local block = CUI.NewSwatchBlocker(widget)
    local labelText = BlizzStyle.Label(key)
    block:SetScript(
        "OnEnter",
        function() CUI.ShowWidgetTooltip(widget, CUI.DisabledTooltip(labelText, "disabled")) end
    )
    block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
    return true
end

-- Banner row under a section header: explains why rows are disabled and
-- links back to the Style page. Adds nothing (returns y unchanged) while
-- the module renders the CludesUI look, so existing pages are untouched.
function BlizzStyle.Note(hostFrame, cursorY, key)
    local m = BY_KEY[key]
    -- The latched rendering state, like Gate: a profile whose flags differ
    -- from the running look (reload declined) must not banner live rows.
    if not m or m.active() == "cui" then return cursorY end
    local ROW_H = 40
    -- The search prebuild only indexes rows: same y advance, no frames.
    if CUI._prebuilding then return cursorY - ROW_H end
    local Pix = CUI.PanelPP
    local row = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(row, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, ROW_H)
    Pix.Point(row, "TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, cursorY)
    row._skipRowDivider = true
    CUI.RowBg(row, hostFrame)

    local labelFS = CUI.MakeFont(row, 12, nil, 1, 1, 1)
    labelFS:SetAlpha(0.6)
    labelFS:SetPoint("LEFT", row, "LEFT", 20, 0)
    labelFS:SetPoint("RIGHT", row, "RIGHT", -160, 0)
    labelFS:SetJustifyH("LEFT")
    labelFS:SetWordWrap(false)
    labelFS:SetText(
        CUI.Lf(
            "%1$s is active. Settings that only apply to the CludesUI look are hidden.",
            CUI.L(BlizzStyle.Label(key))
        )
    )

    local button = CreateFrame("Button", nil, row)
    Pix.Size(button, 122, 26)
    button:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    button:SetFrameLevel(row:GetFrameLevel() + 2)
    CUI.MakeStyledButton(
        button,
        "Open Style",
        11,
        CUI.WB_COLOURS,
        function() CUI:NavigateToElementSettings(GLOBAL_KEY, PAGE_STYLE) end
    )
    return cursorY - ROW_H
end

-- Reload prompt: the flags are written only on confirm, right before the
-- reload, so cancelling (button, escape or click-outside) changes nothing.
-- `changes` lists { m = module, key = styleKey } pairs: every module Apply
-- Styles moves, or every differing module for Apply to All (one prompt each).
-- `wholeUIStyle` (Apply to All only) also applies the matching global font
-- and window skins, either of which alone is reason enough to prompt.
local function PromptStyleChanges(changes, wholeUIStyle)
    if
        #changes == 0
        and not (wholeUIStyle and (FontPending(wholeUIStyle) or WholeUIWindowsPending(wholeUIStyle)))
    then
        return
    end
    CUI:ShowConfirmPopup({
        title = "Reload Required",
        message = "Changing the style requires a UI reload to apply.",
        confirmText = "Reload Now",
        cancelText = "Cancel",
        reload = true,
        onConfirm = function()
            -- Close any editing-as session first, as a profile switch does:
            -- these writes then land on the profile itself, where an open
            -- session's logout sweep would have turned them into overrides
            -- for the group being edited.
            CUI.SpecOverrides_CloseEditSessions()
            -- WoW Forever: a look committed here settles the first-install
            -- picker, so it never asks again over a choice already made.
            if CUI.IS_FOREVER and CludesUIDB then CludesUIDB.styleChoicePending = nil end
            local legacy = wholeUIStyle and GuessStockStyle()
            for idx = 1, #changes do
                SwitchModuleStyle(changes[idx].m, changes[idx].key)
            end
            if wholeUIStyle then
                ApplyWholeUIFont(wholeUIStyle, legacy)
                ApplyWholeUIWindows(wholeUIStyle, legacy)
            end
        end,
    })
end
-- Apply to All's batch for `styleKey`: every loaded module that supports it
-- and whose flag differs.
local function StyleChangesFor(styleKey)
    local changes = {}
    for idx = 1, #MODULES do
        local module = MODULES[idx]
        if
            SupportsStyle(module, styleKey)
            and ModuleNS(module.folder) ~= nil
            and module.get() ~= styleKey
        then
            changes[#changes + 1] = { m = module, key = styleKey }
        end
    end
    return changes
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------

function _G._CUI_BuildStylePage(page, hostFrame, yOffset)
    local Pix = CUI.PanelPP
    local cursorY = yOffset

    -- Header: the first-install picker's look cards (three; four with WoW
    -- Forever on that client; CludesUI_StyleCards.lua), each one Apply
    -- to All for its look through the single reload prompt. The card for the
    -- look every loaded module already uses is marked IN USE, and its button
    -- stays live only while that look still has a font or window-skin change
    -- to apply. Under each card, a checkbox dropdown of the modules that use
    -- its look, and under those Apply Styles.
    -- Sized host + single TOPLEFT point per the search framework's geometry
    -- contract; the search prebuild only needs the y advance.
    local CARDS_TOP = 140
    local DD_GAP, DD_H, BTN_GAP, BTN_W, BTN_H = 14, 30, 26, 252, 45
    local DD_TOP = CARDS_TOP + (CUI.STYLE_CARD_H or 296) + DD_GAP
    local BTN_TOP = DD_TOP + DD_H + BTN_GAP
    local HERO_H = BTN_TOP + BTN_H + 4
    local hasHero = CUI.BuildStyleCards ~= nil
    if hasHero and not CUI._prebuilding then
        local FONT = CUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local ACC = CUI.CLUDES_GREEN
        local host = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(host, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, HERO_H)
        host:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, cursorY - 20)

        local eyebrow = host:CreateFontString(nil, "OVERLAY")
        eyebrow:SetFont(FONT, 13, "")
        eyebrow:SetTextColor(ACC.r, ACC.g, ACC.b, 0.9)
        Pix.Point(eyebrow, "TOP", host, "TOP", 0, -4)
        eyebrow:SetText(CUI.L("CHOOSE YOUR LOOK"))

        local title = host:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 25, "")
        title:SetTextColor(1, 1, 1, 1)
        Pix.Point(title, "TOP", eyebrow, "BOTTOM", 0, -6)
        title:SetText(CUI.L("Your UI, Restyled in Seconds"))

        local desc = host:CreateFontString(nil, "OVERLAY")
        desc:SetFont(FONT, 14, "")
        desc:SetTextColor(1, 1, 1, 0.5)
        desc:SetWidth(620)
        desc:SetJustifyH("CENTER")
        desc:SetWordWrap(true)
        Pix.Point(desc, "TOP", title, "BOTTOM", 0, -10)
        desc:SetText(
            CUI.L(
                "Your setup and every CludesUI feature carry over; only the look changes. Apply a style to every module in one click, or set each module below. Changing a style reloads the UI."
            )
        )

        local cards = CUI.BuildStyleCards(host, -CARDS_TOP, {
            buttonText = "Apply to All",
            -- The card in use fades to half; its larger badge stays whole.
            inUseAlpha = 0.5,
            badgeSize = 13,
            onPick = function(styleKey) PromptStyleChanges(StyleChangesFor(styleKey), styleKey) end,
        })
        if cards then
            local function RefreshCards()
                for key, handle in pairs(cards) do
                    local loaded, differ = 0, 0
                    for idx = 1, #MODULES do
                        local module = MODULES[idx]
                        if SupportsStyle(module, key) and ModuleNS(module.folder) ~= nil then
                            loaded = loaded + 1
                            if module.get() ~= key then differ = differ + 1 end
                        end
                    end
                    local inUse = loaded > 0 and differ == 0
                    local pickable = differ > 0 or FontPending(key) or WholeUIWindowsPending(key)
                    -- "In Use" only on the card that is; with no styleable
                    -- module loaded a card with nothing to apply just dims.
                    handle:SetState(inUse, pickable, (inUse and not pickable) and "In Use" or nil)
                end
            end
            RefreshCards()
            -- Re-run on every page refresh and cached-page restore: a font or
            -- window skin set elsewhere changes what a card has to apply.
            CUI.RegisterWidgetRefresh(RefreshCards)

            -- Module picks: every module sits in exactly one look's dropdown,
            -- its saved style until moved, and shows there checked and locked:
            -- it moves only by being picked under another look (picking it
            -- under its saved look again undoes a move). Nothing is written
            -- until Apply Styles, whose reload prompt writes every move at
            -- once; leaving the page drops the picks.
            local pending = {} -- module key -> picked style, only where it differs
            local function Loaded(m) return ModuleNS(m.folder) ~= nil end
            local function PickOf(m) return pending[m.key] or m.get() end
            local function Pick(m, styleKey) pending[m.key] = (styleKey ~= m.get()) and styleKey or nil end
            local refreshers, applyBtn = {}, nil
            local function RefreshPicks()
                -- A profile switch can make a pick match its module again.
                for keyName, s in pairs(pending) do
                    local m = BY_KEY[keyName]
                    if not m or s == m.get() then pending[keyName] = nil end
                end
                for idx = 1, #refreshers do
                    refreshers[idx]()
                end
                if applyBtn then
                    local enabled = next(pending) ~= nil
                    applyBtn:SetAlpha(enabled and 1 or 0.3)
                    applyBtn:EnableMouse(enabled)
                end
            end
            for styleKey, handle in pairs(cards) do
                local itemList = {}
                for idx = 1, #MODULES do
                    local module = MODULES[idx]
                    if SupportsStyle(module, styleKey) then
                        local function Off() return not Loaded(module) end
                        itemList[#itemList + 1] = {
                            key = module.key,
                            label = module.display,
                            excludeFromSummaryFn = Off,
                            lockedFn = function() return Off() or PickOf(module) == styleKey end,
                            -- Only a disabled module explains itself; a checked one
                            -- just reads as fixed here.
                            lockedTooltip = function()
                                if not Off() then return nil end
                                return CUI.Lf(
                                    "Enable %1$s to change its style.",
                                    CUI.L(module.enableName or module.display)
                                )
                            end,
                        }
                    end
                end
                local dropdown, ddRefresh = CUI.BuildVisOptsCBDropdown(
                    host,
                    handle.card:GetWidth(),
                    host:GetFrameLevel() + 3,
                    itemList,
                    function(key) return PickOf(BY_KEY[key]) == styleKey end,
                    function(key, checked)
                        if checked then Pick(BY_KEY[key], styleKey) end
                    end,
                    RefreshPicks,
                    10,
                    nil,
                    nil,
                    nil,
                    { dimLocked = true }
                )
                Pix.Point(dropdown, "TOP", handle.card, "BOTTOM", 0, -DD_GAP)
                refreshers[#refreshers + 1] = ddRefresh
            end

            applyBtn = CreateFrame("Button", nil, host)
            applyBtn:SetFrameLevel(host:GetFrameLevel() + 3)
            Pix.Size(applyBtn, BTN_W, BTN_H)
            Pix.Point(applyBtn, "TOP", host, "TOP", 0, -BTN_TOP)
            CUI.MakeStyledButton(applyBtn, "Apply Styles", 16, CUI.WB_COLOURS, function()
                local changes = {}
                for idx = 1, #MODULES do
                    local module = MODULES[idx]
                    local s = pending[module.key]
                    if s and Loaded(module) and s ~= module.get() then
                        changes[#changes + 1] = { m = module, key = s }
                    end
                end
                PromptStyleChanges(changes)
            end)
            RefreshPicks()
            CUI.RegisterWidgetRefresh(RefreshPicks)
            host:HookScript("OnHide", function()
                if next(pending) then
                    wipe(pending)
                    RefreshPicks()
                end
            end)
        end
    end
    cursorY = cursorY - 20 - (hasHero and (HERO_H + 20) or 0)

    -- Framework contract: return the positive total content height.
    return math.abs(cursorY)
end
