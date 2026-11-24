if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Fonts.lua
--  Font tables and LSM registration, font resolution cache and per-module
--  getters, outline/slug/shadow helpers, font families, game-text font. Loads after
--  CludesUI_Colors.lua.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI

local MEDIA_PATH = CUI.MEDIA_PATH

-------------------------------------------------------------------------------
--  Global Font System
-------------------------------------------------------------------------------
-- Canonical font name -> filename mapping (shared across all addons)
CUI.FONT_FILES = {
    ["Barlow Condensed"] = "Barlow Condensed.ttf",
    ["Expressway"] = "Expressway.TTF",
    ["Expressway Bold"] = "Expressway Bold.ttf",
    ["Expressway CAPS"] = "Expressway CAPS.ttf",
    ["Avant Garde"] = "Avant Garde.ttf",
    ["Arial Bold"] = "Arial Bold.TTF",
    ["Poppins"] = "Poppins.ttf",
    ["Fira Sans Medium"] = "FiraSans Medium.ttf",
    ["Arial Narrow"] = "Arial Narrow.ttf",
    ["Changa"] = "Changa.ttf",
    ["Cinzel Decorative"] = "Cinzel Decorative.ttf",
    ["Exo"] = "Exo.otf",
    ["Fira Sans Bold"] = "FiraSans Bold.ttf",
    ["Fira Sans Light"] = "FiraSans Light.ttf",
    ["Future X Black"] = "Future X Black.otf",
    ["Gotham Narrow Ultra"] = "Gotham Narrow Ultra.otf",
    ["Gotham Narrow"] = "Gotham Narrow.otf",
    ["Russo One"] = "Russo One.ttf",
    ["Ubuntu"] = "Ubuntu.ttf",
    ["Homespun"] = "Homespun.ttf",
    ["HWT Artz"] = "HWT Artz.ttf",
    ["KMT Kimberley"] = "KMT Kimberley.otf",
    ["KMT Ninja Naruto"] = "KMT Ninja Naruto.ttf",
    ["Friz Quadrata"] = nil, -- Blizzard font
    ["Arial"] = nil, -- Blizzard font
    ["Morpheus"] = nil, -- Blizzard font
    ["Skurri"] = nil, -- Blizzard font
}
-- Bundled faces whose cmap covers the FULL Russian alphabet (U+0410-U+044F plus U+0401
-- and U+0451, i.e. the Yo pair): these stay
-- usable in ruRU instead of being swapped for the system glyph font. Verified per file
-- against its cmap table -- everything omitted here (Poppins, Exo, Gotham, Changa, Cinzel,
-- Future X Black, Homespun, HWT Artz, KMT Ninja Naruto, Barlow Condensed) has ZERO Cyrillic
-- and would render boxes. Re-check coverage before adding a face; a wrong entry ships
-- unreadable text. Expressway CAPS: cmap checked, 66/66 Russian letters (Yo pair included).
-- Deliberately NOT extended to FONT_BLIZZARD: the Cyrillic-capable Blizzard face is
-- FRIZQT___CYR (already the fallback), and the plain ones vary by installed client locale.
CUI.FONT_CYRILLIC = {
    ["Expressway"] = true,
    ["Expressway Bold"] = true,
    ["Expressway CAPS"] = true,
    ["Avant Garde"] = true,
    ["Arial Bold"] = true,
    ["Arial Narrow"] = true,
    ["Fira Sans Medium"] = true,
    ["Fira Sans Bold"] = true,
    ["Fira Sans Light"] = true,
    ["KMT Kimberley"] = true,
    ["Russo One"] = true,
    ["Ubuntu"] = true,
}

-- Blizzard built-in font paths (not in our media folder)
CUI.FONT_BLIZZARD = {
    ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
    ["Arial"] = "Fonts\\ARIALN.TTF",
    ["Morpheus"] = "Fonts\\MORPHEUS.TTF",
    ["Skurri"] = "Fonts\\skurri.ttf",
}
-- The global font a fresh install uses, and the fallback wherever none is stored.
CUI.DEFAULT_FONT_NAME = "Expressway"
CUI.FONT_ORDER = {
    "Expressway",
    "Expressway Bold",
    "Expressway CAPS",
    "Barlow Condensed",
    "Avant Garde",
    "Arial Bold",
    "Poppins",
    "Fira Sans Medium",
    "---",
    "Arial Narrow",
    "Changa",
    "Cinzel Decorative",
    "Exo",
    "Fira Sans Bold",
    "Fira Sans Light",
    "Future X Black",
    "Gotham Narrow Ultra",
    "Gotham Narrow",
    "Russo One",
    "Ubuntu",
    "Homespun",
    "HWT Artz",
    "KMT Kimberley",
    "KMT Ninja Naruto",
    "Friz Quadrata",
    "Arial",
    "Morpheus",
    "Skurri",
}
-- Display name overrides for the font dropdown (key = FONT_ORDER name)
CUI.FONT_DISPLAY_NAMES = {}

-- Sentinel key = "use the locale system font", offered in the picker for glyph-restricted
-- locales (CJK, Cyrillic). Resolves to LOCALE_FONT_FALLBACK in ResolveFontName.
CUI.SYSTEM_FONT_KEY = "__system"

-- Sentinel forcing bundled Expressway in glyph-restricted locales. Distinct from the
-- stored name "Expressway" ON PURPOSE: untouched defaults keep mapping to the system
-- font, and only an explicit pick takes the Latin face (non-Latin renders unglyphed).
CUI.EXPRESSWAY_FORCED_KEY = "__expressway"

-- Register bundled fonts with LSM (other addons get them; SM's HashTable("font")
-- includes them for our dropdowns) and populate _smFontPaths for ResolveFontName.
do
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        for label, fontFile in pairs(CUI.FONT_FILES) do
            if fontFile then LSM:Register(LSM.MediaType.FONT, label, MEDIA_PATH .. "fonts\\" .. fontFile) end
        end
        -- Snapshot all currently registered SM fonts into the path lookup
        local smFonts = LSM:HashTable("font")
        if smFonts then
            CUI._smFontPaths = {}
            for label, filePath in pairs(smFonts) do
                CUI._smFontPaths[label] = filePath
            end
        end
        -- Listen for late-registered fonts from other addons
        LSM.RegisterCallback(CUI, "LibSharedMedia_Registered", function(_, mediatype, key)
            if mediatype == "font" then
                if not CUI._smFontPaths then CUI._smFontPaths = {} end
                local filePath = LSM:Fetch("font", key)
                if filePath then CUI._smFontPaths[key] = filePath end
                CUI.InvalidateFontCache()
            end
        end)
    end
end

-------------------------------------------------------------------------------
--  Font resolution cache -- GetFontPath / GetFontName / GetFontOutlineFlag /
--  GetIconTextOutlineFlag all walk the same chain (GetFontsDB -> GetModuleFontEntry ->
--  ResolveFontName -> SlugFlag -> IsSlugDisabled); recomputing it per text update was
--  ~44% of this addon's CPU. Results depend on the fonts DB, the addon key, AND
--  _smFontPaths (read by ResolveFontName), so they are memoized per key.
--  Invalidation is explicit and deliberately coarse (drop everything):
--    * every font setting funnels through the options page's FontReload()
--    * applying or importing a profile rewrites the fonts DB in place
--    * the fonts reset nils the table outright
--    * a late LibSharedMedia_Registered font updates _smFontPaths
--  Anything else writing the fonts DB OR _smFontPaths MUST call InvalidateFontCache():
--  omitting it cached the Expressway fallback for the session when an SM font registered
--  late. Memoizing in front of ResolveFontName DISABLES its own late-load LSM re-fetch (a
--  cache hit never reaches it), so this cache is the only recovery path. Table fields, not
--  file-scope locals: this file sits on the 200-local limit.
-------------------------------------------------------------------------------
CUI._fontCache = { path = {}, name = {}, outline = {}, icon = {} }
CUI._fontCacheDirty = true
-- Stand-in key for a nil addonKey (the global font), which cannot index a table.
CUI._FONT_KEY_GLOBAL = "\1global"
-- Dropdown sentinel for "Blizzard Default": resolves to the client's own
-- standard UI font (STANDARD_TEXT_FONT, locale-aware) in ResolveFontName.
CUI.BLIZZARD_FONT_KEY = "__blizzard"
-- The client's standard UI font, read when used (another addon may set the global
-- after this file loads). "Apply to All Game Text" overwrites STANDARD_TEXT_FONT,
-- so the value it replaced is kept (_clientFontPath, ApplyGlobalFontToGameText) and wins.
function CUI.GetBlizzardFontPath()
    return CUI._clientFontPath or _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

function CUI.InvalidateFontCache() CUI._fontCacheDirty = true end

--- Returns the cache, cleared first if a font setting changed since last use.
function CUI._FontCacheReady()
    local c = CUI._fontCache
    if CUI._fontCacheDirty then
        wipe(c.path)
        wipe(c.name)
        wipe(c.outline)
        wipe(c.icon)
        c.slug = nil
        CUI._fontCacheDirty = false
    end
    return c
end

-- Get the fonts DB table (lazy-init)
function CUI.GetFontsDB()
    if not CludesUIDB then CludesUIDB = {} end
    if not CludesUIDB.fonts then
        CludesUIDB.fonts = {
            -- Cyrillic locales seed the system glyph font, not Expressway: the FONT_CYRILLIC
            -- faces do render ruRU correctly, but they stay an explicit opt-in so a fresh
            -- install looks exactly like every prior version. Existing installs are pinned
            -- by the ru_cyrillic_font_optin_v1 migration.
            global = (CUI.LOCALE_SCRIPT == "cyrillic") and CUI.SYSTEM_FONT_KEY or CUI.DEFAULT_FONT_NAME,
            outlineMode = "shadow",
        }
    end
    local f = CludesUIDB.fonts
    return f
end

-- Resolve a font name to a full file path
local function ResolveFontName(faceName)
    -- Blizzard Default: the client's own standard UI font. Handled before the
    -- glyph-restriction branch because STANDARD_TEXT_FONT is already
    -- locale-aware (the engine picks the right face per client language).
    if faceName == CUI.BLIZZARD_FONT_KEY then return CUI.GetBlizzardFontPath() end
    -- Explicit Expressway override: bypasses the glyph-restriction mapping below.
    if faceName == CUI.EXPRESSWAY_FORCED_KEY then return MEDIA_PATH .. "fonts\\Expressway.TTF" end
    -- Glyph-restricted locales (CJK, Cyrillic): bundled fonts without coverage for the
    -- script, and the System Default sentinel, map to the system glyph font. Only an
    -- external SharedMedia font (or a FONT_CYRILLIC face in ruRU, handled first) may
    -- override. Bundled names are excluded below because they are LSM-registered too and
    -- would otherwise resolve to their Latin file.
    if CUI.LOCALE_FONT_FALLBACK then
        -- Cyrillic locales: a bundled face with verified Cyrillic coverage renders ruRU
        -- text correctly, so honour the pick instead of forcing the system glyph font.
        -- Gated on LOCALE_SCRIPT, not on the fallback alone: CJK has no bundled coverage.
        if CUI.LOCALE_SCRIPT == "cyrillic" and faceName and CUI.FONT_CYRILLIC[faceName] then
            local cyrFile = CUI.FONT_FILES[faceName]
            if cyrFile then return MEDIA_PATH .. "fonts\\" .. cyrFile end
        end
        if faceName and not CUI.FONT_FILES[faceName] and not CUI.FONT_BLIZZARD[faceName] then
            local smPath = CUI._smFontPaths and CUI._smFontPaths[faceName]
            if smPath then return smPath end
            local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
            if LSM and LSM:IsValid("font", faceName) then
                local fetched = LSM:Fetch("font", faceName)
                if fetched then
                    if not CUI._smFontPaths then CUI._smFontPaths = {} end
                    CUI._smFontPaths[faceName] = fetched
                    return fetched
                end
            end
        end
        return CUI.LOCALE_FONT_FALLBACK
    end
    local bliz = CUI.FONT_BLIZZARD[faceName]
    if bliz then return bliz end
    local fontFile = CUI.FONT_FILES[faceName]
    if fontFile then return MEDIA_PATH .. "fonts\\" .. fontFile end
    -- SharedMedia fonts: path from _smFontPaths (populated at init)
    local smPath = CUI._smFontPaths and CUI._smFontPaths[faceName]
    if smPath then return smPath end
    -- LSM fallback for late-loading SM addons not yet in _smFontPaths
    if faceName then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("font", faceName)
            if fetched then
                if not CUI._smFontPaths then CUI._smFontPaths = {} end
                CUI._smFontPaths[faceName] = fetched
                return fetched
            end
        end
    end
    return MEDIA_PATH .. "fonts\\Expressway.TTF"
end
CUI.ResolveFontName = ResolveFontName

-- Floating combat text is in the client's language, not CUI's display language. On a
-- glyph-restricted client, a Combat Text Font key counts only if it can draw that script:
-- a SharedMedia font or a Blizzard file LSM registers (LSM keeps just the ones flagged
-- for the client), or a FONT_CYRILLIC face on ruRU.
function CUI.CombatTextFontCoversLocale(key)
    local locale = GetLocale()
    if not CUI.LocaleGlyphFont(locale) or key:match("^smf:") then return true end
    if locale == "ruRU" then
        for label, fontFile in pairs(CUI.FONT_FILES) do
            if CUI.FONT_CYRILLIC[label] and key == MEDIA_PATH .. "fonts\\" .. fontFile then return true end
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    for _, filePath in pairs(LSM and LSM:HashTable("font") or {}) do
        if filePath == key then return true end
    end
    return false
end

-- Per-module font overrides: all state stored on the CludesUI table
-- to stay under the 200-local / 60-upvalue Lua 5.1 caps.
CUI._addonKeyToFolder = {
    actionBars = "CludesUIActionBars",
    nameplates = "CludesUINameplates",
    unitFrames = "CludesUIUnitFrames",
    cdm = "CludesUICooldownManager",
    resourceBars = "CludesUIResourceBars",
    auraBuff = "CludesUIAuraBuffReminders",
    extras = "CludesUIQoL",
    essentials = "CludesUIForeverEssentials",
    friends = "CludesUIFriends",
    minimap = "CludesUIMinimap",
    chat = "CludesUIChat",
    questTracker = "CludesUIQuestTracker",
    mythicTimer = "CludesUIMythicTimer",
    blizzardSkin = "CludesUIBlizzardSkin",
    damageMeters = "CludesUIDamageMeters",
    dataBars = "CludesUIDataBars",
    raidFrames = "CludesUIRaidFrames",
    bags = "CludesUIBags",
    quickdraw = "CludesUIQuickdraw",
    lootCouncil = "CludesUISimpleLootCouncil",
}
CUI._moduleFontCache = {}
CUI._moduleFontCacheVer = 0

-- Resolve an addonKey to a moduleFonts entry (nil = global). Cached per-key, zero-alloc.
function CUI.GetModuleFontEntry(moduleKey)
    if not moduleKey then return nil end
    local saved = CUI.GetFontsDB()
    local mfList = saved.moduleFonts
    if not mfList or #mfList == 0 then return nil end

    local cache = CUI._moduleFontCache
    local ver = #mfList
    if ver ~= CUI._moduleFontCacheVer then
        wipe(cache)
        CUI._moduleFontCacheVer = ver
    end

    local cached = cache[moduleKey]
    if cached ~= nil then return cached ~= false and cached or nil end

    local folder = CUI._addonKeyToFolder[moduleKey] or moduleKey

    for _, record in ipairs(mfList) do
        if record.folder == folder then
            cache[moduleKey] = record
            return record
        end
    end
    cache[moduleKey] = false
    return nil
end

-- Resolved font path for an addon key; falls back to the global font with no override.
function CUI.GetFontPath(moduleKey)
    local c = CUI._FontCacheReady().path
    local k = moduleKey or CUI._FONT_KEY_GLOBAL
    local matched = c[k]
    if matched then return matched end

    local saved = CUI.GetFontsDB()
    local overrideFont = CUI.GetModuleFontEntry(moduleKey)
    local filePath
    if overrideFont and overrideFont.font and overrideFont.font ~= "__global" then
        filePath = ResolveFontName(overrideFont.font)
    else
        filePath = ResolveFontName(saved.global or CUI.DEFAULT_FONT_NAME)
    end
    c[k] = filePath
    return filePath
end

-- Get the font name (not path) for an addon key.
function CUI.GetFontName(moduleKey)
    local c = CUI._FontCacheReady().name
    local k = moduleKey or CUI._FONT_KEY_GLOBAL
    local matched = c[k]
    if matched then return matched end

    local saved = CUI.GetFontsDB()
    local overrideFont = CUI.GetModuleFontEntry(moduleKey)
    local label
    if overrideFont and overrideFont.font and overrideFont.font ~= "__global" then
        label = overrideFont.font
    else
        label = saved.global or CUI.DEFAULT_FONT_NAME
    end
    c[k] = label
    return label
end

-- Get the WoW font flag string for the outline mode.
-- Pass an addonKey to get per-module override; nil returns the global setting.
-- Returns: "OUTLINE, SLUG", "THICKOUTLINE, SLUG", or "" (none/shadow)
function CUI.GetFontOutlineFlag(moduleKey)
    local c = CUI._FontCacheReady().outline
    local k = moduleKey or CUI._FONT_KEY_GLOBAL
    -- "" (no outline) is a legitimate result and truthy in Lua, so a presence test is a correct cache hit.
    local matched = c[k]
    if matched then return matched end

    local saved = CUI.GetFontsDB()
    local overrideFont = CUI.GetModuleFontEntry(moduleKey)
    local mode
    if overrideFont and overrideFont.outline and overrideFont.outline ~= "__global" then
        mode = overrideFont.outline
    else
        mode = saved.outlineMode or "none"
    end
    local outlineFlag = CUI.OutlineFlagForMode(mode)
    c[k] = outlineFlag
    return outlineFlag
end

-- The WoW font flag for one outline mode ("outline", "thick"; anything else is
-- none/shadow), slug-gated. For a feature with its own outline choice; resolve
-- "__global" through GetFontOutlineFlag first.
function CUI.OutlineFlagForMode(mode)
    local outlineFlag
    if mode == "outline" then
        outlineFlag = "OUTLINE, SLUG"
    elseif mode == "thick" then
        outlineFlag = "THICKOUTLINE, SLUG"
    else
        outlineFlag = ""
    end
    return CUI.SlugFlag(outlineFlag)
end

-- Per-profile "Never Show Slug": ON strips the SLUG token from every outline flag the
-- UI produces (body + icon/aura text across all modules, plus the global Outline Mode).
-- Lives in the per-profile fonts DB so it rides profile export/import, falling back to
-- the account-global CludesUIDB.neverShowSlug. OFF by default.
function CUI.IsSlugDisabled()
    local c = CUI._FontCacheReady()
    -- Cached value is a boolean, so nil is the only safe "not yet computed".
    if c.slug ~= nil then return c.slug end

    local fontsDB = CUI.GetFontsDB()
    local val = fontsDB and fontsDB.neverShowSlug
    if val == nil then val = CludesUIDB and CludesUIDB.neverShowSlug end
    val = (val == true)
    c.slug = val
    return val
end

-- Strip the SLUG token from a font outline flag:
-- "OUTLINE, SLUG" -> "OUTLINE", "THICKOUTLINE, SLUG" -> "THICKOUTLINE", "" -> "".
function CUI.StripSlugFlag(outlineFlag)
    if not outlineFlag or outlineFlag == "" then return outlineFlag or "" end
    return (outlineFlag:gsub("%s*,%s*SLUG", ""))
end

-- Central gate: strips SLUG from `flag` when "Never Show Slug" is on. Use at EVERY point
-- a slug outline flag is produced (outline helpers, hardcoded icon-text literals).
function CUI.SlugFlag(outlineFlag)
    if CUI.IsSlugDisabled() then return CUI.StripSlugFlag(outlineFlag) end
    return outlineFlag
end

-- Returns true when the outline mode uses drop shadow instead of outline.
-- Pass an addonKey to get per-module override; nil returns the global setting.
function CUI.GetFontUseShadow(moduleKey)
    local saved = CUI.GetFontsDB()
    local overrideFont = CUI.GetModuleFontEntry(moduleKey)
    local mode
    if overrideFont and overrideFont.outline and overrideFont.outline ~= "__global" then
        mode = overrideFont.outline
    else
        mode = saved.outlineMode or "none"
    end
    return mode == "none" or mode == "shadow"
end

-- Runtime FontString:SetShadowOffset/SetShadowColor does NOT render a drop shadow;
-- shadows only render when carried by a FontObject. Prime each string with a shared
-- shadow (or no-shadow) FontObject via SetFontObject, THEN SetFont for the typeface:
-- the inherited shadow survives SetFont and instance text color is preserved.
do
    local shadowObj = CreateFont("CludesUIShadowFont")
    shadowObj:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    shadowObj:SetShadowColor(0, 0, 0, 1)
    shadowObj:SetShadowOffset(1, -1)
    local noShadowObj = CreateFont("CludesUINoShadowFont")
    noShadowObj:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    noShadowObj:SetShadowColor(0, 0, 0, 0)
    noShadowObj:SetShadowOffset(0, 0)
    -- Prime a FontString so its drop shadow renders. Call BEFORE SetFont.
    function CUI.PrimeFontShadow(fontStr, useShadow)
        if not (fontStr and fontStr.SetFontObject) then return end
        fontStr:SetFontObject(useShadow and shadowObj or noShadowObj)
    end
end

-------------------------------------------------------------------------------
--  Font families. A text that can show other players' writing (unit names,
--  guild names, Battle.net names and notes, chat bubbles, meter rows, tooltip
--  lines) takes a FONT FAMILY instead of one font file. The engine draws a whole
--  string with ONE member, chosen by its content: any Cyrillic letter takes the
--  russian member (Latin letters in that string included), Latin-only text the
--  roman one. The chosen font is the roman member, the russian member when it
--  carries Cyrillic and the client's own CJK alphabet's member; Blizzard's own
--  Cyrillic, Korean and Chinese faces draw the scripts it lacks. Every member has
--  the same size and flags, so Latin text draws exactly as with a plain SetFont.
--  A family carries face, size, flags and its shadow (a drop shadow renders only
--  from a font object), never a text colour or justification: SetFontObject
--  pushes only what the object defines, so a string keeps its own.
--  A plain fs:SetFont pins that string's face for good (a later SetFontObject no
--  longer changes it), so a string takes its family from its FIRST font write
--  and every later write to it goes through SetFontFamily, never SetFont,
--  ApplyModuleFont, ApplyIconTextFont or PrimeFontShadow.
--  Blizzard's own font OBJECTS (families or plain) change member by member
--  through SetFontObjectFace. A family object's own SetFont changes only its own
--  font, the one GetFont() reads and copies take (Blizzard's guild chat copies the
--  main chat window's), never a member; SetFontObjectFace sets it too, where the
--  client's own alphabet takes the face.
--  Built once per path / size / flags / shadow; a hit reads four table fields and
--  builds nothing. Table fields, not file-scope locals (200-local limit).
-------------------------------------------------------------------------------
CUI._FONT_ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
-- The client language whose stock face draws each CJK alphabet.
CUI._FONT_CJK_LOCALE = { korean = "koKR", simplifiedchinese = "zhCN", traditionalchinese = "zhTW" }
-- The client's own CJK alphabet (nil on other clients) keeps the chosen font, as
-- every text in the client's language draws with it.
CUI._FONT_CLIENT_ALPHABET = ({
    koKR = "korean",
    zhCN = "simplifiedchinese",
    zhTW = "traditionalchinese",
})[GetLocale()]
-- On a Russian client the russian member keeps the path, as every text in Russian draws with it.
CUI._FONT_CLIENT_RU = (GetLocale() == "ruRU")
-- The alphabet the client's own language draws with.
CUI._FONT_CLIENT_OWN = CUI._FONT_CLIENT_ALPHABET or (CUI._FONT_CLIENT_RU and "russian") or "roman"
CUI._FONT_CYR_FILE = "Fonts\\FRIZQT___CYR.TTF"
-- path -> size -> flags ("" for none) -> shadow (true / false) -> family, or false
-- when the client has no families or the creation failed (never retried).
CUI._fontFamilies = {}
CUI._fontFamilyCount = 0
-- Our families and their member objects: the game text passes skip them.
CUI._fontFamilySet = setmetatable({}, { __mode = "k" })
CUI._fontPathCyr = {} -- path -> it draws the Russian alphabet
CUI._fontPathOK = {} -- path -> the client loads it
CUI._fontObjIsFamily = setmetatable({}, { __mode = "k" }) -- font object -> is a family
CUI._fontFaceDone = {} -- the members one SetFontObjectFace call has set (reused)

-- True when `path` draws the full Russian alphabet: a FONT_CYRILLIC face's file,
-- Blizzard's Cyrillic Friz, or any path on a Russian client. Cached per path.
function CUI._FontPathCyrillic(filePath)
    if type(filePath) ~= "string" then return false end
    local c = CUI._fontPathCyr
    local matched = c[filePath]
    if matched ~= nil then return matched end
    local accepted = CUI._FONT_CLIENT_RU
    if not accepted then
        local low = filePath:lower():gsub("/", "\\")
        accepted = (low == CUI._FONT_CYR_FILE:lower())
        if not accepted then
            local dir = (MEDIA_PATH .. "fonts\\"):lower()
            for label in pairs(CUI.FONT_CYRILLIC) do
                local fontFile = CUI.FONT_FILES[label]
                if fontFile and low == dir .. fontFile:lower() then
                    accepted = true
                    break
                end
            end
        end
    end
    c[filePath] = accepted
    return accepted
end

-- Whether a member of `alphabet` takes the face `path` (else it keeps a stock face):
-- roman always, russian when the path draws Russian, the client's own CJK alphabet.
function CUI._FontMemberTakesPath(alphabet, filePath)
    if alphabet == "roman" or alphabet == CUI._FONT_CLIENT_ALPHABET then return true end
    if alphabet == "russian" then return CUI._FontPathCyrillic(filePath) end
    return false
end

-- Whether the client loads the font file at `path`: a hidden scratch string's
-- SetFont returns false for a file it cannot load. Tested once per path, except
-- that failures are retested until the loading screen after the first one ends
-- (see below).
function CUI._FontPathLoads(filePath)
    local c = CUI._fontPathOK
    local matched = c[filePath]
    if matched ~= nil then return matched end
    local probe = CUI._fontProbe
    if not probe then
        local holderFrame = CreateFrame("Frame")
        holderFrame:Hide()
        probe = holderFrame:CreateFontString()
        CUI._fontProbe = probe
    end
    local success, loaded = pcall(probe.SetFont, probe, filePath, 12, "")
    matched = success and loaded ~= false
    -- On a fresh game start a file can fail before it is read: retested at login (see below).
    if matched or CUI._fontRetryDone then
        c[filePath] = matched
    else
        CUI._FontRetryArm(filePath)
    end
    return matched
end

-- Paths that failed before login finished, and the families built without them.
CUI._fontPathPending = {}
CUI._fontFamPending = {}
-- Retests each pending path at the login stages; a path that loads goes into the
-- families that fell back, member by member, so their texts update in place.
function CUI._FontRetryArm(filePath)
    CUI._fontPathPending[filePath] = true
    local frame = CUI._fontRetryFrame
    if frame then return end
    frame = CreateFrame("Frame")
    CUI._fontRetryFrame = frame
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("LOADING_SCREEN_DISABLED")
    frame:SetScript("OnEvent", function(self, evt)
        local pending, c = CUI._fontPathPending, CUI._fontPathOK
        local final = evt == "LOADING_SCREEN_DISABLED"
        for p in pairs(pending) do
            local success, loaded = pcall(CUI._fontProbe.SetFont, CUI._fontProbe, p, 12, "")
            if success and loaded ~= false then
                c[p], pending[p] = true, nil
                CUI._FontFamiliesTakePath(p)
            elseif final then
                c[p], pending[p] = false, nil
            end
        end
        if final or not next(pending) then
            CUI._fontRetryDone = final or nil
            if final then
                self:UnregisterAllEvents()
                wipe(CUI._fontFamPending)
            end
        end
    end)
end

-- The families built while `path` failed get it now, on the members that take it,
-- and as their own font (a family built with the path has its roman member's).
function CUI._FontFamiliesTakePath(filePath)
    local entries = CUI._fontFamPending
    local alphabetList = CUI._FONT_ALPHABETS
    for idx = #entries, 1, -1 do
        local entry = entries[idx]
        if entry.path == filePath then
            for a = 1, #alphabetList do
                local memberKey = CUI._FontMemberTakesPath(alphabetList[a], filePath)
                    and entry.fam:GetFontObjectForAlphabet(alphabetList[a])
                if memberKey then pcall(memberKey.SetFont, memberKey, filePath, entry.size, entry.flags) end
            end
            pcall(entry.fam.SetFont, entry.fam, filePath, entry.size, entry.flags)
            table.remove(entries, idx)
        end
    end
end

-- The shadow on the family and on each member (PrimeFontShadow's values), and the
-- family and its members into the set the game text passes skip. Once, at creation.
function CUI._DressFontFamily(fam, shadow)
    local set = CUI._fontFamilySet
    set[fam] = true
    local a, posX, posY = 0, 0, 0
    if shadow then
        a, posX, posY = 1, 1, -1
    end
    fam:SetShadowColor(0, 0, 0, a)
    fam:SetShadowOffset(posX, posY)
    local alphabetList = CUI._FONT_ALPHABETS
    for idx = 1, #alphabetList do
        local memberKey = fam:GetFontObjectForAlphabet(alphabetList[idx])
        if memberKey then
            set[memberKey] = true
            memberKey:SetShadowColor(0, 0, 0, a)
            memberKey:SetShadowOffset(posX, posY)
        end
    end
end

-- Builds and caches the family for one key. A path the client cannot load takes the
-- client's standard font.
function CUI._BuildFontFamily(filePath, size, outlineFlags, shadow)
    if type(filePath) ~= "string" or type(size) ~= "number" or not (size > 0) then return nil end
    local cache = CUI._fontFamilies
    local bySize = cache[filePath]
    if not bySize then
        bySize = {}
        cache[filePath] = bySize
    end
    local byFlags = bySize[size]
    if not byFlags then
        byFlags = {}
        bySize[size] = byFlags
    end
    local byShadow = byFlags[outlineFlags]
    if not byShadow then
        byShadow = {}
        byFlags[outlineFlags] = byShadow
    end
    local create = CreateFontFamily
    if type(create) ~= "function" then
        byShadow[shadow] = false
        return nil
    end
    local fontFace = filePath
    if not CUI._FontPathLoads(filePath) then fontFace = CUI.GetBlizzardFontPath() end
    local alphabetList = CUI._FONT_ALPHABETS
    local members = {}
    for idx = 1, #alphabetList do
        local alphabet = alphabetList[idx]
        local fontFile = fontFace
        if not CUI._FontMemberTakesPath(alphabet, fontFace) then
            if alphabet == "russian" then
                fontFile = CUI._FONT_CYR_FILE
            else
                fontFile = CUI.LocaleGlyphFont(CUI._FONT_CJK_LOCALE[alphabet])
            end
        end
        members[idx] = { alphabet = alphabet, file = fontFile, height = size, flags = outlineFlags }
    end
    CUI._fontFamilyCount = CUI._fontFamilyCount + 1
    local success, fam = pcall(create, "CUIFontFamily" .. CUI._fontFamilyCount, members)
    if success and fam then success = pcall(CUI._DressFontFamily, fam, shadow) end
    if not (success and fam) then
        byShadow[shadow] = false
        return nil
    end
    byShadow[shadow] = fam
    if fontFace ~= filePath and CUI._fontPathPending[filePath] then
        local entries = CUI._fontFamPending
        entries[#entries + 1] = { fam = fam, path = filePath, size = size, flags = outlineFlags }
    end
    return fam
end

-- The family font object for a face, size, outline flags and shadow, or nil when the
-- client has no font families (or this one could not be made): the caller then sets
-- the font the plain way. One family per key for the session.
function CUI.GetFontFamily(filePath, size, outlineFlags, shadow)
    outlineFlags = outlineFlags or ""
    shadow = shadow and true or false
    -- Scaled texts (raid and party auto-resize, size offsets) hand fractional sizes:
    -- families are kept per quarter point, so a slider drag reuses a few of them (a
    -- font object is never freed), at most an eighth of a point off.
    if type(size) == "number" then size = math.floor(size * 4 + 0.5) / 4 end
    local tbl = CUI._fontFamilies[filePath]
    tbl = tbl and tbl[size]
    tbl = tbl and tbl[outlineFlags]
    local fam = tbl and tbl[shadow]
    if fam then return fam end
    if fam == false then return nil end
    return CUI._BuildFontFamily(filePath, size, outlineFlags, shadow)
end

-- Sets a font string's font as a family (see the block above). A string already on
-- that family is not touched. Its first switch from a font object that is not one
-- of ours keeps the string's justification and text colour, which a template object
-- may have given it. With no family: PrimeFontShadow, then a plain SetFont.
function CUI.SetFontFamily(fontStr, filePath, size, outlineFlags, shadow)
    if not (fontStr and fontStr.SetFontObject) then return end
    local fam = CUI.GetFontFamily(filePath, size, outlineFlags, shadow)
    if not fam then
        CUI.PrimeFontShadow(fontStr, shadow)
        fontStr:SetFont(filePath, size, outlineFlags)
        return
    end
    local current = fontStr:GetFontObject()
    if current == fam then return end
    if current and CUI._fontFamilySet[current] then
        fontStr:SetFontObject(fam)
        return
    end
    -- The getters may hand back secret values (a text colour set from secret
    -- data), so they are tested with type() only and passed straight back.
    local justifyH, justifyV = fontStr:GetJustifyH(), fontStr:GetJustifyV()
    local red, green, blue, a = fontStr:GetTextColor()
    fontStr:SetFontObject(fam)
    if type(justifyH) == "string" then fontStr:SetJustifyH(justifyH) end
    if type(justifyV) == "string" then fontStr:SetJustifyV(justifyV) end
    if type(red) == "number" then fontStr:SetTextColor(red, green, blue, a) end
end

-- True when a font object is a family: its roman and russian alphabets have
-- members of their own. Read once per object.
function CUI._FontObjectIsFamily(object)
    local c = CUI._fontObjIsFamily
    local matched = c[object]
    if matched ~= nil then return matched end
    local accepted = false
    if object.GetFontObjectForAlphabet then
        local okR, roman = pcall(object.GetFontObjectForAlphabet, object, "roman")
        local okC, russian = pcall(object.GetFontObjectForAlphabet, object, "russian")
        accepted = (okR and okC and roman ~= nil and russian ~= nil and roman ~= russian) and true or false
    end
    c[object] = accepted
    return accepted
end

-- One member (or plain object): the face `path` when given, else its own; `size`
-- when given, else its own size times `scale`; `flags` when given, else its own.
-- A member already in `done` is skipped, so a member several alphabets or objects
-- share changes once (a scale never compounds).
function CUI._SetFontMemberFace(memberKey, filePath, size, outlineFlags, scale, done)
    if done[memberKey] then return end
    done[memberKey] = true
    local fontFace, msize, mflags = memberKey:GetFont()
    if not msize or msize <= 0 then return end
    fontFace = filePath or fontFace
    if not fontFace then return end
    pcall(memberKey.SetFont, memberKey, fontFace, size or msize * (scale or 1), outlineFlags or mflags or "")
end

-- SetFontObjectFace's body with the caller's `done` set (a game text pass shares one
-- set across every object it changes).
function CUI._FontObjectFaceInto(object, filePath, size, outlineFlags, scale, done)
    if CUI._FontObjectIsFamily(object) then
        local alphabetList = CUI._FONT_ALPHABETS
        for idx = 1, #alphabetList do
            local alphabet = alphabetList[idx]
            local success, memberKey = pcall(object.GetFontObjectForAlphabet, object, alphabet)
            if success and memberKey then
                local fontFace = filePath
                if fontFace and not CUI._FontMemberTakesPath(alphabet, fontFace) then fontFace = nil end
                CUI._SetFontMemberFace(memberKey, fontFace, size, outlineFlags, scale, done)
            end
        end
        -- The family's own font as well (it changes no member): GetFont() reads it and
        -- copies take it (the guild chat copies the main chat window's font). Only
        -- where the client's own alphabet takes the face.
        if not filePath or CUI._FontMemberTakesPath(CUI._FONT_CLIENT_OWN, filePath) then
            CUI._SetFontMemberFace(object, filePath, size, outlineFlags, scale, done)
        end
    else
        CUI._SetFontMemberFace(object, filePath, size, outlineFlags, scale, done)
    end
end

-- Changes a Blizzard font OBJECT, family or plain. A family changes member by member:
-- `path` (nil keeps every face) goes to the members that take it under the family
-- rules (roman; russian when the path draws Russian; the client's own CJK alphabet),
-- the others keep their own faces; `size` (nil: each member's own size times `scale`,
-- default 1) and `flags` (nil: each member's own) go to every member. A plain object
-- takes the same on itself.
function CUI.SetFontObjectFace(object, filePath, size, outlineFlags, scale)
    if not (object and type(object) == "table" and object.GetFont and object.SetFont) then return end
    local done = CUI._fontFaceDone
    wipe(done)
    CUI._FontObjectFaceInto(object, filePath, size, outlineFlags, scale, done)
end

-- Each member's (or a plain object's) face, size and flags, and a family's own
-- font, for RestoreFontObject.
function CUI.SnapshotFontObject(object)
    if not (object and type(object) == "table" and object.GetFont) then return nil end
    local snap = {}
    if CUI._FontObjectIsFamily(object) then
        local ownFace, ownSize, ownFlags = object:GetFont()
        snap.own = { face = ownFace, size = ownSize, flags = ownFlags }
        local alphabetList = CUI._FONT_ALPHABETS
        for idx = 1, #alphabetList do
            local success, memberKey = pcall(object.GetFontObjectForAlphabet, object, alphabetList[idx])
            if success and memberKey then
                local fontFace, size, outlineFlags = memberKey:GetFont()
                snap[alphabetList[idx]] = { face = fontFace, size = size, flags = outlineFlags }
            end
        end
    else
        local fontFace, size, outlineFlags = object:GetFont()
        snap.plain = { face = fontFace, size = size, flags = outlineFlags }
    end
    return snap
end

function CUI._RestoreFontMember(memberKey, cfg)
    if cfg and cfg.face and cfg.size and cfg.size > 0 then
        pcall(memberKey.SetFont, memberKey, cfg.face, cfg.size, cfg.flags or "")
    end
end

-- Puts back what SnapshotFontObject read.
function CUI.RestoreFontObject(object, snap)
    if not (object and type(object) == "table" and object.SetFont and snap) then return end
    if snap.plain then
        CUI._RestoreFontMember(object, snap.plain)
        return
    end
    CUI._RestoreFontMember(object, snap.own)
    local alphabetList = CUI._FONT_ALPHABETS
    for idx = 1, #alphabetList do
        local s = snap[alphabetList[idx]]
        if s then
            local success, memberKey = pcall(object.GetFontObjectForAlphabet, object, alphabetList[idx])
            if success and memberKey then CUI._RestoreFontMember(memberKey, s) end
        end
    end
end

-- "Apply to All Game Text" + "Game Text Scale": swaps Blizzard's default game fonts to
-- the user's global face and/or scales their sizes. Taint-safe: runs once at PLAYER_LOGIN
-- (out of combat), sets STANDARD_TEXT_FONT, and SetFonts Blizzard's named font OBJECTS
-- (not secure frames, no keys written onto Blizzard frame tables). Outline preserved;
-- sizes multiply from each object's NATIVE size (single once-per-session pass, so the
-- scale can never compound); either setting requires a reload (no undo path: off/100% =
-- that half skipped, defaults kept). Scale works without the face swap too -- each
-- object keeps its own face at the scaled size.
-- The font objects the pass leaves alone: the floating combat text's, which the
-- Combat Text Font setting owns.
CUI._GAME_TEXT_KEEP = { "CombatTextFont", "SystemFont_World" }
function CUI.ApplyGlobalFontToGameText()
    local saved = CUI.GetFontsDB()
    -- Zero cost while fully off: both settings absent (scale 100 stores nil)
    -- means two table reads and out -- nothing computed, nothing enumerated.
    if not saved.applyToAllGameText and not saved.gameTextScale then return end
    local scale = tonumber(saved.gameTextScale) or 100
    if scale < 75 then
        scale = 75
    elseif scale > 125 then
        scale = 125
    end
    scale = scale / 100
    local swapFont = saved.applyToAllGameText and true or false
    local filePath
    if swapFont then
        filePath = ResolveFontName(saved.global or CUI.DEFAULT_FONT_NAME)
        if not filePath then swapFont = false end
    end
    if not swapFont and scale == 1 then return end

    if swapFont then
        -- The client's own font, before the first swap replaces it (Blizzard Default).
        CUI._clientFontPath = CUI._clientFontPath or _G.STANDARD_TEXT_FONT
        -- Universal fallback consumed by newly-created Blizzard/addon text.
        _G.STANDARD_TEXT_FONT = filePath
    end

    -- Enumerate every registered font object via the game's own font list (no
    -- hardcoded list to go stale); covers Blizzard + other addons in one pass.
    -- A family changes member by member (SetFontObjectFace): a member whose script
    -- the chosen face lacks keeps its own face, so Russian, Korean and Chinese text
    -- keeps drawing. One `done` set for the whole pass, so a member several objects
    -- share scales once. Our own families are skipped.
    local fonts = (GetFonts and GetFonts()) or {}
    local ours = CUI._fontFamilySet
    local done = {}
    -- The floating combat text over the player draws with CombatTextFont (on the
    -- SystemFont_World family), the numbers over enemies with DAMAGE_TEXT_FONT. Both
    -- follow the Combat Text Font setting alone, so the pass marks those two objects,
    -- their own fonts and every member as done and leaves them as they are.
    local keep = CUI._GAME_TEXT_KEEP
    local alphabetList = CUI._FONT_ALPHABETS
    for k = 1, #keep do
        local object = _G[keep[k]]
        if object and type(object) == "table" then
            done[object] = true
            if object.GetFontObjectForAlphabet then
                for a = 1, #alphabetList do
                    local success, memberKey = pcall(object.GetFontObjectForAlphabet, object, alphabetList[a])
                    if success and memberKey then done[memberKey] = true end
                end
            end
        end
    end
    for idx = 1, #fonts do
        local object = _G[fonts[idx]]
        -- Guard each: GetFonts may list entries that are not usable font objects.
        if object and type(object) == "table" and not ours[object] and object.GetFont and object.SetFont then
            CUI._FontObjectFaceInto(object, swapFont and filePath or nil, nil, nil, scale, done)
        end
    end
    -- Premade Groups' category labels are copies of GameFontNormal taken as each button
    -- is built, with no font object to follow, so one built before this pass (the first:
    -- Blizzard's XML declares it) keeps the client's face. A label still on that face
    -- takes the global one at its own size. Nothing to do under Blizzard Default (the
    -- same face) or on WoW Forever (no such window, so the wait would never end).
    local old = CUI._clientFontPath
    if
        swapFont
        and filePath ~= old
        and not CUI.IS_FOREVER
        and EventUtil
        and EventUtil.ContinueOnAddOnLoaded
    then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_GroupFinder", function()
            if not LFGListCategorySelection_AddButton then return end
            hooksecurefunc("LFGListCategorySelection_AddButton", function(cs, idx)
                local b = cs and type(cs.CategoryButtons) == "table" and cs.CategoryButtons[idx]
                local labelText = b and b.Label
                if not (labelText and labelText.GetFont) then return end
                local fontFace, size, outlineFlags = labelText:GetFont() -- not in an and-chain, that keeps only face
                if fontFace == old and size then labelText:SetFont(filePath, size, outlineFlags or "") end
            end)
        end)
    end
end

-- Module-scoped font failsafe (always on, independent of "Apply to All Game Text"). Chat,
-- Quest Tracker and the Blizz-UI-Enhanced tooltips style text per-frame, but some sub-elements
-- draw from Blizzard's SHARED font OBJECTS, leaving stragglers on the default face; swapping
-- those objects at login catches them. Each area is gated on its module being loaded/enabled
-- and uses that module's font key (per-module override, else global). Typeface + outline only,
-- native size preserved (tooltips keep their font-scale). Taint-safe like ApplyGlobalFontToGameText: SetFont on font objects only, never a write onto a Blizzard frame table; runs after the global pass so module wins.
function CUI.ApplyModuleFontFailsafe()
    local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    local GetPath = CUI.GetFontPath
    local GetOutline = CUI.GetFontOutlineFlag
    if not IsLoaded or not GetPath then return end

    -- Face + outline swap preserving each object's native SIZE (per-frame styling owns size).
    -- The outline matches what each area's per-frame styling applies (chat, questTracker,
    -- blizzardSkin) so stragglers stop looking un-styled. Safe for the chat input box:
    -- SkinEditBox sets its own font, so it never inherits ChatFontNormal. `outline` may be ""
    -- (Drop Shadow/None), which correctly CLEARS a native outline; pass nil to keep native flags. Guards nil/non-object, missing size and a rejecting SetFont, so an absent or renamed object is a no-op.
    -- A family changes member by member (SetFontObjectFace): the members whose script the
    -- face lacks keep their own faces. Our own families are skipped.
    local function swapFont(object, filePath, outline)
        if not object or type(object) ~= "table" or CUI._fontFamilySet[object] then return end
        CUI.SetFontObjectFace(object, filePath or _G.STANDARD_TEXT_FONT, nil, outline, nil)
    end

    -- Chat: the module fonts the frames + edit boxes directly; ChatFontNormal backstops the rest (menus, copy/URL windows, channel buttons, etc.).
    if IsLoaded("CludesUIChat") then
        swapFont(_G.ChatFontNormal, GetPath("chat"), GetOutline and GetOutline("chat"))
    end

    -- Quest Tracker: the skin region-walks live blocks; these shared objects catch fontstrings
    -- Blizzard re-templates after the walk. ONLY ObjectiveTracker*-prefixed objects, so the world-map quest log (QuestFont*) stays untouched.
    -- Skipped under the module's stock styles, which keep Blizzard's own tracker text.
    local qtNS = CUI._ModuleNS and CUI._ModuleNS.CludesUIQuestTracker
    local qtStock = qtNS and qtNS.QT_Style and qtNS.QT_Style() ~= "cui"
    if IsLoaded("CludesUIQuestTracker") and not qtStock then
        local p = GetPath("questTracker")
        local po = GetOutline and GetOutline("questTracker")
        swapFont(_G.ObjectiveTrackerHeaderFont, p, po)
        swapFont(_G.ObjectiveTrackerLineFont, p, po)
        for idx = 12, 22 do
            swapFont(_G["ObjectiveTrackerFont" .. idx], p, po)
        end
    end

    -- Tooltips (Blizz UI Enhanced): only when customTooltips is on. _ttFonts styles each visible line (size + outline + scale) on show; these only backstop what it misses.
    if IsLoaded("CludesUIBlizzardSkin") and (not CludesUIDB or CludesUIDB.customTooltips ~= false) then
        local p = GetPath("blizzardSkin")
        local po = GetOutline and GetOutline("blizzardSkin")
        swapFont(_G.GameTooltipText, p, po)
        swapFont(_G.GameTooltipHeaderText, p, po)
        swapFont(_G.GameTooltipTextSmall, p, po)
    end
end

-- Outline flag for icon-overlay text (stack counts, durations, keybinds) on action buttons,
-- unit/raid auras, CDM icons and bags. Checked "Outline Icon Text" (default) forces crisp
-- "OUTLINE, SLUG"; unchecked follows the global/per-module outline choice (each of the five modules has its own font key in _addonKeyToFolder).
function CUI.GetIconTextOutlineFlag(moduleKey)
    local c = CUI._FontCacheReady().icon
    local k = moduleKey or CUI._FONT_KEY_GLOBAL
    local matched = c[k]
    if matched then return matched end

    -- Per-profile (rides profile export); the account-global table is the read-time fallback.
    local fontsDB = CUI.GetFontsDB()
    local tbl = (fontsDB and fontsDB.outlineIconText) or (CludesUIDB and CludesUIDB.outlineIconText)
    local outlineFlag
    if tbl and tbl[moduleKey] == false then
        -- Follows the outline mode, which is already slug-gated at the source.
        outlineFlag = (CUI.GetFontOutlineFlag(moduleKey)) or ""
    else
        -- Forced crisp outline; "Never Show Slug" still drops the slug token.
        outlineFlag = CUI.SlugFlag("OUTLINE, SLUG")
    end
    c[k] = outlineFlag
    return outlineFlag
end

-- Applies the icon-text outline flag AND the matching shadow in one call. Checked -> "OUTLINE,
-- SLUG", no shadow; unchecked -> the user's outline choice, and when that resolves to "" (Drop Shadow/None) a drop shadow is applied for legibility.
function CUI.ApplyIconTextFont(fontStr, fontFile, size, moduleKey)
    if not (fontStr and fontStr.SetFont) then return end
    local outlineFlag = CUI.GetIconTextOutlineFlag(moduleKey)
    -- Prime the shadow FontObject before SetFont (see PrimeFontShadow).
    CUI.PrimeFontShadow(fontStr, outlineFlag == "")
    fontStr:SetFont(fontFile, size, outlineFlag)
end

-- Body text in a module's font: fontPath/flags default to the module's (nil key = global)
-- font and outline; a "" flag (Drop Shadow/None) gets the drop shadow.
function CUI.ApplyModuleFont(fontStr, fontFile, size, moduleKey, outlineFlags)
    if not (fontStr and fontStr.SetFont) then return end
    outlineFlags = outlineFlags or CUI.GetFontOutlineFlag(moduleKey)
    CUI.PrimeFontShadow(fontStr, outlineFlags == "")
    fontStr:SetFont(fontFile or CUI.GetFontPath(moduleKey), size, outlineFlags)
end

-- ApplyModuleFont for a text that can show other players' writing: the same defaults
-- (the module's font and outline; a "" flag gets the drop shadow) as a font family
-- (SetFontFamily). Once a string has a family, no ApplyModuleFont may reach it.
function CUI.ApplyModuleFontFamily(fontStr, fontFile, size, moduleKey, outlineFlags)
    if not (fontStr and fontStr.SetFont) then return end
    outlineFlags = outlineFlags or CUI.GetFontOutlineFlag(moduleKey)
    CUI.SetFontFamily(fontStr, fontFile or CUI.GetFontPath(moduleKey), size, outlineFlags, outlineFlags == "")
end

-- Build font dropdown values/order ("CUI Global Font" first) for W:DualRow configs.
function CUI.BuildFontDropdownData()
    -- Glyph-restricted locales: bundled Latin fonts cannot render the script (and resolve to the
    -- system font anyway), so pickers offer only "CUI Global Font", "System Default" and external SharedMedia, matching the global font picker.
    if CUI.LOCALE_FONT_FALLBACK then
        local values = {
            ["__global"] = { text = "CUI Global Font" },
            [CUI.SYSTEM_FONT_KEY] = { text = "System Default", font = CUI.LOCALE_FONT_FALLBACK },
            [CUI.EXPRESSWAY_FORCED_KEY] = {
                text = "Expressway (Latin only)",
                font = CUI.MEDIA_PATH .. "fonts\\Expressway.TTF",
            },
        }
        local sequence = { "__global", CUI.SYSTEM_FONT_KEY, CUI.EXPRESSWAY_FORCED_KEY }
        if CUI.AppendExternalSharedMediaFonts then CUI.AppendExternalSharedMediaFonts(values, sequence) end
        return values, sequence
    end
    -- "Blizzard Default" sits right under the inherit entry on unrestricted
    -- locales. Glyph-restricted pickers (branch above) skip it: their "System
    -- Default" entry already IS the client's own font.
    local values = {
        ["__global"] = { text = "CUI Global Font" },
        [CUI.BLIZZARD_FONT_KEY] = {
            text = "Blizzard Default",
            font = CUI.GetBlizzardFontPath(),
        },
    }
    local sequence = { "__global", CUI.BLIZZARD_FONT_KEY, "---" }
    local FONT_DIR = CUI.MEDIA_PATH .. "fonts\\"
    for _, label in ipairs(CUI.FONT_ORDER) do
        if label == "---" then
            sequence[#sequence + 1] = "---"
        else
            local filePath = CUI.FONT_BLIZZARD[label]
                or (FONT_DIR .. (CUI.FONT_FILES[label] or "Expressway.TTF"))
            local displayName = (CUI.FONT_DISPLAY_NAMES and CUI.FONT_DISPLAY_NAMES[label]) or label
            values[label] = { text = displayName, font = filePath }
            sequence[#sequence + 1] = label
        end
    end
    if CUI.AppendSharedMediaFonts then CUI.AppendSharedMediaFonts(values, sequence, { keyByName = true }) end
    return values, sequence
end
