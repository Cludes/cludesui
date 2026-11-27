if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CludesUI_GlobalSearch.lua
--  Unified fuzzy search across every registered CludesUI sub-addon's
--  options.
--
--  Optional / modular by design: TagOptionRow and SectionHeader in
--  CludesUI_Widgets.lua call CludesUI._RegisterSearchEntry only if it
--  exists, so this file can be added (or removed) independently of the rest
--  of the addon with no other changes required.
-------------------------------------------------------------------------------

-- The module registry is the core's private one (CludesUI.lua), shared
-- through this addon's namespace. It holds suite modules and plugin modules.
local _, mod = ...
mod = mod.__cuiCoreNS or mod -- standalone builds: the core's own table (CludesUI.lua)

-- Breadcrumb separator: the house right-arrow glyph rendered inline in the
-- sub text (module -> page), sized to sit with the 10pt breadcrumb font.
local BREADCRUMB_ARROW = " |TInterface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-right.png:12:12|t "

-- Display name of a registered module. Plugin modules read as
-- "Section > Module" so results name the plugin they belong to.
local function ModuleLabel(moduleConfig, moduleFolder)
    local title = CUI.L(moduleConfig.title or moduleFolder)
    if moduleConfig._pluginLabel then
        return CUI.L(moduleConfig._pluginLabel) .. BREADCRUMB_ARROW .. title,
            moduleConfig._pluginLabel .. " " .. title
    end
    return title, title
end

-- A page's name as its tab shows it (CUI_NS.GetTabLabel), localized.
local function PageLabel(moduleFolder, pageEntry) return CUI.L(mod.GetTabLabel(moduleFolder, pageEntry)) end

-------------------------------------------------------------------------------
--  Index storage
-------------------------------------------------------------------------------
local _searchIndex = {}
local _seenKeys = {}

-- Registered by TagOptionRow / SectionHeader as each option row / section
-- header is built during normal navigation, and by the one-time pre-build
-- pass below for pages nobody has opened yet this session.
function CUI._RegisterSearchEntry(
    label,
    localLabel,
    tipText,
    moduleFolder,
    pageEntry,
    sectionName,
    selectorSetter,
    selectorKey,
    isSection
)
    -- Opt-out for whole UI regions: a builder sets this around widget
    -- construction it wants excluded from the search entirely (e.g. the QoL
    -- Macro Factory, whose rows must never be indexed or deep-linked).
    if CUI._searchIndexSuppress then return end
    -- Composite labels (DualRow/TripleRow with an empty slot) can come in as whitespace
    -- only (e.g. a single joining space with nothing on either side) -- trim before the
    -- emptiness check so those don't register as inert, unmatchable junk entries.
    if label then label = label:match("^%s*(.-)%s*$") end
    if not label or label == "" or not moduleFolder or not pageEntry then return end
    local key = moduleFolder .. "\1" .. pageEntry .. "\1" .. label
    if _seenKeys[key] then return end
    _seenKeys[key] = true
    if localLabel == "" then localLabel = nil end
    if type(tipText) ~= "string" or tipText == "" then tipText = nil end
    _searchIndex[#_searchIndex + 1] = {
        label = label,
        -- Lowercased once here so a keystroke never re-lowers the whole index.
        lLabel = label:lower(),
        lLoc = localLabel and localLabel:lower(),
        lTip = tipText and tipText:lower(),
        -- Space-free copies: "castbar" finds "Cast Bar", "mouse over" finds "Mouseover".
        nLabel = (label:lower():gsub(" ", "")),
        nLoc = localLabel and (localLabel:lower():gsub(" ", "")),
        nTip = tipText and (tipText:lower():gsub(" ", "")),
        labelLoc = localLabel,
        tooltip = tipText,
        module = moduleFolder,
        section = sectionName,
        page = pageEntry,
        -- Present only for entries built while a page's own internal selector (CDM bar
        -- / action bar / unit dropdown) was set to a specific value -- lets
        -- JumpToResult restore that exact selection before navigating, so a setting
        -- that only exists under one selector value (e.g. HoverCast-only options) is
        -- actually there to find and highlight instead of silently not matching.
        selectorSetter = selectorSetter,
        selectorKey = selectorKey,
        -- True for SectionHeader registrations: results render these as
        -- "Section: Title Case" destinations instead of option rows.
        isSection = isSection,
    }
end

-------------------------------------------------------------------------------
--  Fuzzy scoring: subsequence match, ranked below any exact substring by
--  ScoreEntry's tiers. Cheap enough to run per keystroke over the whole
--  index -- no Levenshtein needed.
-------------------------------------------------------------------------------
local function FuzzyScore(haystack, needle)
    local hLen, nLen = #haystack, #needle
    -- Forward pass only finds where the earliest full match ends.
    local hitIndex, nameIndex = 1, 1
    while hitIndex <= hLen and nameIndex <= nLen do
        if haystack:byte(hitIndex) == needle:byte(nameIndex) then nameIndex = nameIndex + 1 end
        hitIndex = hitIndex + 1
    end
    if nameIndex <= nLen then return nil end -- not every needle char found in order
    local lastMatch = hitIndex - 1
    -- Backward pass from there finds the latest start, so the match is not
    -- anchored on a stray early letter ("stats" on "secondary stat display"
    -- must start at "stat", not at the "s" of "secondary").
    local consecutiveRun, score = 0, 0
    hitIndex, nameIndex = lastMatch, nLen
    while nameIndex >= 1 do
        if haystack:byte(hitIndex) == needle:byte(nameIndex) then
            consecutiveRun = consecutiveRun + 1
            score = score + consecutiveRun -- reward tight clustering (a run of k scores 1+2+...+k)
            nameIndex = nameIndex - 1
        else
            consecutiveRun = 0
        end
        hitIndex = hitIndex - 1
    end
    local firstMatch = hitIndex + 1

    -- Reject overly sparse matches. Without this, a long enough haystack makes almost
    -- any needle findable as SOME subsequence somewhere in it (e.g. "combat" scattering
    -- across "Consumables Talent" in a coarse module+page label) -- that's noise, not a
    -- real fuzzy match. Flat +8 slack keeps short abbreviations ("aoc" over "Auto Open
    -- Containers") alive while capping how far a longer word may scatter.
    local span = lastMatch - firstMatch + 1
    if span > nLen + 8 then return nil end

    return (score * 100) / span -- density: tighter matches for the same needle score higher
end

-- Tiers, best first: label exact, label plural-stem exact, tooltip exact,
-- tooltip stem, label fuzzy, tooltip fuzzy. A tier always outranks the one
-- below it; within a tier, earlier position / denser match wins.
local TIER = 10000
local function FieldScore(hgt, nh, needle, stem, mod, exactTier, fuzzyTier)
    if not hgt then return nil end
    local idx = hgt:find(needle, 1, true)
    if idx then return exactTier * TIER + math.max(0, TIER - 1 - idx) end
    if stem then
        -- Singular form must end its word: "stat" in "stat display", not "status".
        idx = hgt:find(stem, 1, true)
        while idx do
            local c = hgt:byte(idx + #stem)
            if not c or c < 97 or (c > 122 and c < 128) then
                return (exactTier - 1) * TIER + math.max(0, TIER - 1 - idx)
            end
            idx = hgt:find(stem, idx + 1, true)
        end
    end
    idx = nh:find(mod, 1, true)
    if idx then return (exactTier - 1) * TIER + math.max(0, TIER - 1 - idx) end
    local s = FuzzyScore(hgt, needle)
    if s then return fuzzyTier * TIER + math.min(s, TIER - 1) end
end

local function ScoreEntry(record, needle, stem, mod)
    local a = FieldScore(record.lLabel, record.nLabel, needle, stem, mod, 5, 1)
    local b = FieldScore(record.lLoc, record.nLoc, needle, stem, mod, 5, 1)
    local c = FieldScore(record.lTip, record.nTip, needle, stem, mod, 3, 0)
    -- Page results also score on the tab name alone: "fonts" hits "Fonts" at
    -- position 1 instead of late in "Global Settings Fonts".
    local d = FieldScore(record.lPage, record.nPage, needle, stem, mod, 5, 1)
    if b and (not a or b > a) then a = b end
    if c and (not a or c > a) then a = c end
    if d and (not a or d > a) then a = d end
    return a
end

-- Tie-break for equal scores: whole text equals the query, then shorter
-- text, then a fixed order (page, section, option; module in sidebar order,
-- Global Settings first, plugins last; page; label), since table.sort is not
-- stable and the candidates come from pairs().
local KIND_RANK = { page = 1 }
-- The sidebar's order is its groups' (read at load, before any other addon runs);
-- every key outside them (plugins, other addons' pages) takes 1000.
local _moduleRank = { [CUI.GLOBAL_KEY] = 0 }
do
    local num = 0
    for _, group in ipairs(CUI.ADDON_GROUPS) do
        for _, moduleFolder in ipairs(group.members) do
            num = num + 1
            _moduleRank[moduleFolder] = num
        end
    end
end
local function SortResults(a, b)
    if a.score ~= b.score then return a.score > b.score end
    local xa, xb = a.exact == true, b.exact == true
    if xa ~= xb then return xa end
    local entryA, entryB = a.entry, b.entry
    local ta = entryA.displayLabel or entryA.label
    local tb = entryB.displayLabel or entryB.label
    if #ta ~= #tb then return #ta < #tb end
    local ka = KIND_RANK[entryA.kind] or (entryA.isSection and 2 or 3)
    local kb = KIND_RANK[entryB.kind] or (entryB.isSection and 2 or 3)
    if ka ~= kb then return ka < kb end
    if entryA.module ~= entryB.module then
        local ra, rb = _moduleRank[entryA.module] or 1000, _moduleRank[entryB.module] or 1000
        if ra ~= rb then return ra < rb end
        return entryA.module < entryB.module
    end
    if entryA.order and entryB.order and entryA.order ~= entryB.order then
        return entryA.order < entryB.order
    end
    if entryA.page ~= entryB.page then return entryA.page < entryB.page end
    return entryA.label < entryB.label
end

-------------------------------------------------------------------------------
--  Coarse (whole-page) candidates: "Damage Meters -> Spell History" as a
--  single jump target, not just its individual options. Built directly from
--  the module registry's static config (title/pages), so unlike the
--  fine-grained index above it needs no build pass or navigation to exist --
--  page/module identity is known the moment a sub-addon registers, before
--  any of its widgets are ever constructed.
-------------------------------------------------------------------------------
local _coarseCandidates

local function BuildCoarseCandidates()
    _coarseCandidates = {}
    for moduleFolder, moduleConfig in pairs(mod.modules or {}) do
        if moduleConfig.pages then
            -- moduleText is the plain-text form used in the haystack.
            local moduleLabel, moduleText = ModuleLabel(moduleConfig, moduleFolder)
            for sequence, pageEntry in ipairs(moduleConfig.pages) do
                local pageCaption = PageLabel(moduleFolder, pageEntry)
                -- A relabeled tab stays findable by its page identity too.
                local pageText = pageCaption
                if mod.GetTabLabel(moduleFolder, pageEntry) ~= pageEntry then
                    pageText = pageCaption .. " " .. CUI.L(pageEntry)
                end
                _coarseCandidates[#_coarseCandidates + 1] = {
                    kind = "page",
                    -- Combined haystack so a query spanning both module and page words
                    -- (e.g. "damage spell") still matches, not just one half of it.
                    label = moduleText .. " " .. pageText,
                    lLabel = (moduleText .. " " .. pageText):lower(),
                    nLabel = ((moduleText .. pageText):lower():gsub(" ", "")),
                    lPage = pageCaption:lower(),
                    nPage = (pageCaption:lower():gsub(" ", "")),
                    order = sequence,
                    displayLabel = pageCaption,
                    moduleLabel = moduleLabel,
                    module = moduleFolder,
                    page = pageEntry,
                }
            end
        end
    end
end

-- Module-name filter: "raid frames border style" should search "border style" WITHIN
-- Raid Frames, not fuzzy-match the whole phrase everywhere. Lazily built alias list
-- (module titles + sidebar display names, both localized), longest alias first so "raid
-- frames" can never lose to a shorter overlapping alias. Only a FULL alias at the START
-- of the query (followed by more words) activates the filter -- single overlapping
-- words ("raid" also appears in other modules' option labels) never do.
local _moduleAliases

local function BuildModuleAliases()
    _moduleAliases = {}
    local seen = {}
    local function Add(aliasName, moduleFolder)
        if not aliasName then return end
        aliasName = aliasName:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if aliasName == "" then return end
        local key = aliasName .. "\1" .. moduleFolder
        if seen[key] then return end
        seen[key] = true
        _moduleAliases[#_moduleAliases + 1] = { alias = aliasName, folder = moduleFolder }
    end
    for moduleFolder, moduleConfig in pairs(mod.modules or {}) do
        Add(moduleConfig.title and CUI.L(moduleConfig.title), moduleFolder)
        -- A plugin's section label filters to all of that plugin's modules.
        if moduleConfig._pluginLabel then Add(CUI.L(moduleConfig._pluginLabel), moduleFolder) end
    end
    if CUI.ADDON_ROSTER then
        for _, record in ipairs(CUI.ADDON_ROSTER) do
            if mod.modules and mod.modules[record.folder] then
                Add(record.display and CUI.L(record.display), record.folder)
            end
        end
    end
    -- Hand-curated shorthands on top of the titles/display names, matching
    -- how players actually abbreviate the modules. Folders that never
    -- registered a module simply don't get their shorthands.
    local EXTRA_ALIASES = {
        CludesUIMythicTimer = { "m+ timer", "m+", "m+ tools", "mythic+ timer" },
        CludesUICooldownManager = { "cdm" },
        -- Without the "+", and the module's former name.
        CludesUIBlizzardSkin = { "blizzard skins", "blizz ui enhanced" },
        CludesUIQuickdraw = {
            "radial",
            "wheel",
            "ring menu",
            "palette",
            "grid",
            "arc",
            "fan",
            "action wheel",
            "action palette",
            "action menu",
        },
        CludesUILoadoutManager = { "gear swap", "talent swap", "equipment manager", "loadouts" },
        -- The module's former name.
        CludesUIRaidFrames = { "raid frames" },
    }
    for moduleFolder, entries in pairs(EXTRA_ALIASES) do
        if mod.modules and mod.modules[moduleFolder] then
            for _, a in ipairs(entries) do
                Add(a, moduleFolder)
            end
        end
    end
    table.sort(_moduleAliases, function(lhs, rhs) return #lhs.alias > #rhs.alias end)
end

-- Alternate spellings a query may use for a feature whose option labels
-- name it differently; see the synonym pass in SearchIndex. Terms are
-- plain lowercase words (no pattern characters) and engage from their
-- first SYNONYM_MIN_PREFIX letters (shorter terms need all of theirs).
-- Only add pairs whose alternate really appears in option labels.
local QUERY_SYNONYMS = {
    { "skyriding", { "dragon riding", "dragonriding" } },
    { "sky riding", { "dragon riding", "dragonriding" } },
    -- Abbreviations
    { "cd", { "cooldown" } },
    { "cds", { "cooldown" } },
    { "global cooldown", { "gcd" } },
    { "hp", { "health" } },
    { "ab", { "action bar" } },
    { "uf", { "unit frame" } },
    { "rf", { "raid frame" } },
    { "experience", { "xp" } },
    { "lfg", { "group finder", "queue" } },
    { "m+", { "mythic", "keystone" } },
    { "mplus", { "mythic", "keystone" } },
    -- Other words for the same thing
    { "transparency", { "opacity" } },
    { "alpha", { "opacity" } },
    { "kick", { "interrupt" } },
    { "interrupt", { "kick" } },
    { "cleanse", { "dispel" } },
    { "purge", { "dispel" } },
    { "decurse", { "dispel" } },
    { "aggro", { "threat" } },
    { "hotkey", { "keybind" } },
    { "keybind", { "hotkey" } },
    { "binding", { "hotkey" } },
    { "inventory", { "bag" } },
    { "bags", { "bag" } },
    { "colour", { "color" } },
    { "shield", { "absorb" } },
    { "absorb", { "shield" } },
    { "stacks", { "charges" } },
    { "charges", { "stacks" } },
    { "plates", { "nameplate" } },
    { "hotbar", { "action bar" } },
    { "buffs", { "aura" } },
    { "debuffs", { "aura" } },
    { "aura", { "buff", "debuff" } },
    { "move", { "position", "unlock" } },
    { "drag", { "position", "unlock" } },
    { "layer", { "strata" } },
    { "level", { "strata" } },
    { "combo points", { "resource" } },
    { "holy power", { "resource" } },
    { "chi", { "resource" } },
    { "soul shards", { "resource" } },
    { "runes", { "resource" } },
    { "mouse", { "mouseover" } },
    { "hover", { "mouseover" } },
    { "transparent", { "fade" } },
    { "hide when", { "fade" } },
    { "quest", { "objective", "tracker" } },
    -- A choice inside a dropdown (dropdown values are not indexed): its row
    { "compact", { "bag display", "bank display" } },
}
-- WoW Forever's Name Format (first or last names; Forever Essentials > General).
if CUI.IS_FOREVER then QUERY_SYNONYMS[#QUERY_SYNONYMS + 1] = { "surname", { "name format" } } end
local SYNONYM_MIN_PREFIX = 3

local function SearchIndex(searchText, maxResults)
    maxResults = maxResults or 30
    local needle = (searchText or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if needle == "" then return {} end
    if not _coarseCandidates then BuildCoarseCandidates() end
    if not _moduleAliases then BuildModuleAliases() end

    -- Detect a module name ANYWHERE in the query (whole words only, longest alias
    -- first) and split it off as an ADDITIVE boost: "raid frames border style" and
    -- "border style raid frames" both surface "border style" within Raid Frames on top
    -- of the plain full-query results (merged below -- never replacing them).
    local filterKeys, subNeedle
    for _, m in ipairs(_moduleAliases) do
        local a = m.alias
        local s, e = needle:find(a, 1, true)
        while s do
            local beforeOk = s == 1 or needle:sub(s - 1, s - 1) == " "
            local afterOk = e == #needle or needle:sub(e + 1, e + 1) == " "
            if beforeOk and afterOk then
                -- Several modules can share one alias (a plugin section label).
                filterKeys = {}
                for _, other in ipairs(_moduleAliases) do
                    if other.alias == a then filterKeys[other.folder] = true end
                end
                subNeedle = (needle:sub(1, s - 1) .. " " .. needle:sub(e + 1))
                    :gsub("%s+", " ")
                    :gsub("^%s+", "")
                    :gsub("%s+$", "")
                break
            end
            s, e = needle:find(a, s + 1, true)
        end
        if filterKeys then break end
    end

    -- Progressive variant: while a module name is still being TYPED, the
    -- trailing word(s) act as a module-name PREFIX -- "border style r"
    -- (then "ra", "raid f", ...) already narrows to every module whose name
    -- starts that way, engaging the filter long before the full name is
    -- typed. Longest trailing chunk wins; all prefix-matching modules are
    -- searched as a union, so ambiguity ("r") just means a wider net.
    if not filterKeys then
        local words = {}
        for wid in needle:gmatch("%S+") do
            words[#words + 1] = wid
        end
        for idx = 1, #words do
            local chunk = table.concat(words, " ", idx, #words)
            local keySet
            for _, m in ipairs(_moduleAliases) do
                if m.alias:sub(1, #chunk) == chunk then
                    keySet = keySet or {}
                    keySet[m.folder] = true
                end
            end
            if keySet then
                filterKeys = keySet
                subNeedle = idx > 1 and table.concat(words, " ", 1, idx - 1) or ""
                break
            end
        end
    end

    -- One scoring pass over both indexes. With a module filter active, only
    -- those modules' entries are considered, matched against the remainder
    -- of the query; a BARE module name (or name prefix) lists pages.
    local function ScorePass(folderSet, num)
        local ranked = {}
        -- "stats" also finds "stat" as a near-exact hit, one tier down.
        local stem = #num >= 4 and num:sub(-1) == "s" and num:sub(1, -2) or nil
        local mod = num:gsub(" ", "")
        local function Consider(entries)
            for _, record in ipairs(entries) do
                if not folderSet or folderSet[record.module] then
                    if num == "" then
                        if record.kind == "page" then
                            -- Bare module name: pages in tab order.
                            ranked[#ranked + 1] = { entry = record, score = TIER - record.order }
                        end
                    else
                        local s = ScoreEntry(record, num, stem, mod)
                        if s then
                            local exact = record.lLabel == num or record.lLoc == num or record.lPage == num
                            ranked[#ranked + 1] = { entry = record, score = s, exact = exact }
                        end
                    end
                end
            end
        end
        Consider(_searchIndex)
        Consider(_coarseCandidates)
        return ranked
    end

    -- ADDITIVE module filter: the plain full-query pass ALWAYS runs, and a
    -- detected module name layers its remainder-scoped hits ON TOP (boosted
    -- above plain hits so the targeted interpretation ranks first). The
    -- filter must never REMOVE cross-module matches: typing "hide b"
    -- (trailing "b" = a Bags/Blizz UI prefix) must not drop QoL's "Hide
    -- Blizzard Party Panel", which still matches the plain query.
    local ranked = ScorePass(nil, needle)
    local seenEntries = {}
    for _, score in ipairs(ranked) do
        seenEntries[score.entry] = score
    end
    -- Merge a further pass by entry: an entry already present keeps its
    -- best score, a new one joins the list.
    local function Merge(entries, boost)
        for _, score in ipairs(entries) do
            local s = score.score + boost
            local existing = seenEntries[score.entry]
            if existing then
                if s > existing.score then
                    existing.score = s
                    existing.exact = score.exact
                end
            else
                score.score = s
                seenEntries[score.entry] = score
                ranked[#ranked + 1] = score
            end
        end
    end
    -- Query synonyms: a term players type for a feature whose labels still
    -- carry another name. The term engages while it is still being TYPED:
    -- the longest prefix of it (at least SYNONYM_MIN_PREFIX letters) that
    -- sits in the query on word boundaries, or runs to the end of the
    -- query, is swapped for each alternate spelling and that variant runs
    -- as one more plain pass at the same score -- "sky", "skyr" and
    -- "skyriding" all surface every "Dragon Riding" control. Variants are
    -- deduped so two terms sharing a prefix do not score twice.
    local altNeedles
    for _, syn in ipairs(QUERY_SYNONYMS) do
        local term = syn[1]
        local matched = false
        for len = #term, math.min(SYNONYM_MIN_PREFIX, #term), -1 do
            local pre = term:sub(1, len)
            local s, e = needle:find(pre, 1, true)
            while s do
                local beforeOk = s == 1 or needle:sub(s - 1, s - 1) == " "
                local afterOk = e == #needle or needle:sub(e + 1, e + 1) == " "
                if beforeOk and afterOk then
                    altNeedles = altNeedles or {}
                    for _, alt in ipairs(syn[2]) do
                        altNeedles[needle:sub(1, s - 1) .. alt .. needle:sub(e + 1)] = true
                    end
                    matched = true
                    break
                end
                s, e = needle:find(pre, s + 1, true)
            end
            if matched then break end
        end
    end
    if altNeedles then
        for altNeedle in pairs(altNeedles) do
            Merge(ScorePass(nil, altNeedle), 0)
        end
    end
    if filterKeys then
        Merge(ScorePass(filterKeys, subNeedle), 6 * TIER) -- above every tier
    end

    table.sort(ranked, SortResults)
    local result = {}
    for idx = 1, math.min(maxResults, #ranked) do
        result[idx] = ranked[idx].entry
    end
    return result
end

-------------------------------------------------------------------------------
--  One-time, staggered, off-screen pre-build pass.
--  Populates the index for pages the user hasn't opened yet this session,
--  without ever showing that UI. The hidden root frame is never shown, so
--  nothing built under it ever renders or runs OnUpdate scripts -- WoW gates
--  both on the frame's (and its ancestors') shown state. Rebuilt fresh every
--  login (no SavedVariables caching), so the index can never go stale
--  relative to the actual option code.
-------------------------------------------------------------------------------
local _prebuildDone = false
local _hiddenParent

-- The main panel's content-header chrome is ONE real, shared frame -- not scoped to
-- whatever parent/wrapper a buildPage happens to be given -- and several sub-addons
-- call these directly from buildPage. For real navigation that's fine (there's only
-- ever one visible page), but during a hidden pre-build it would overwrite whatever
-- header the user is actually looking at. These methods are also nil outright until
-- the panel's first Show() (they're defined inside CreateMainFrame), which a plain
-- guard clause inside them can't help with -- so stub them out here for the
-- duration of each pre-build call instead, then restore whatever was there before
-- (nil or the real function).
local _CONTENT_HEADER_METHODS = {
    "SetContentHeader",
    "UpdateContentHeaderHeight",
    "SetContentHeaderHeightSilent",
    "ClearContentHeader",
    "HideContentHeader",
}

-- A single hidden build of one (folder, page). Optionally switches the
-- page's own internal selector (CDM bar / action bar key / unit) to
-- selectorKey first via selectorSetter, so options gated behind a
-- non-default selector value get indexed too -- otherwise they'd only ever
-- be searchable after the player manually visits that selector value once.
-------------------------------------------------------------------------------
--  FRAMELESS INDEX PASS (2026-08-03, user directive: the index pass must
--  never build frames -- the old hidden prebuild created ~48 real pages =
--  10-25MB of permanent frames, and WoW frames are never freed).
--
--  The pass still RUNS every page builder (attribution, data-driven rows,
--  selector variants and localization all keep working), but the builders
--  run against a stub widget factory: CludesUI.Widgets is swapped to
--  AbsorberW for exactly the synchronous buildPage call. Every stub reads
--  the SAME declarative fields the real factory's TagOptionRow /
--  IndexSlotForSearch lines read (verified 1:1 against CludesUI_Widgets
--  2026-08-03) and registers the same index entries -- then returns an
--  "absorber" instead of a frame.
--
--  The absorber survives anything a builder does to a widget: any string
--  key yields another absorber, any call no-ops, arithmetic on it yields
--  plain numbers (y-offset math), NUMERIC keys yield nil so ipairs/# see an
--  empty array (an auto-vivifying [1] would never terminate). Builders'
--  own direct CreateFrame chrome still lands on the real (reused, hidden)
--  wrapper -- a handful of small frames on the few custom-chrome pages,
--  not the widget mass. A builder the absorber cannot survive is caught by
--  the existing pcall and that page falls back to live-navigation indexing,
--  loudly in dev mode.
--
--  MAINTENANCE CONTRACT: a NEW WidgetFactory method that registers search
--  entries needs a matching stub here, or its rows are invisible to search
--  until the page is built live. Mirror the real factory's registration
--  lines exactly (which args/fields, which slots).
-------------------------------------------------------------------------------
local _absSection = nil
local _absWrapper = nil
local _absorberMeta
_absorberMeta = {
    __index = function(_, key)
        -- Numeric keys read as ABSENT so ipairs()/#/array probes terminate.
        if type(key) == "number" then return nil end
        return setmetatable({}, _absorberMeta)
    end,
    __call = function() return setmetatable({}, _absorberMeta) end,
    __add = function() return 100 end,
    __sub = function() return 100 end,
    __mul = function() return 100 end,
    __div = function() return 1 end,
    __mod = function() return 0 end,
    __pow = function() return 1 end,
    __unm = function() return -100 end,
    __concat = function() return "" end,
    __len = function() return 0 end,
    __lt = function() return false end,
    __le = function() return false end,
    __tostring = function() return "CUIAbsorber" end,
}
local function MakeAbsorber() return setmetatable({}, _absorberMeta) end

-- Mirrors IndexSlotForSearch in CludesUI_Widgets.lua exactly: empty
-- labels skip, localized form rides along only when it differs, section is
-- the absorber pass's own tracker (the real path reads it off the parent
-- frame; the absorber parent is shared, so the pass tracks it here), and
-- the selector context comes from the same global the live path uses.
local function RegisterAbsorbed(labelText, tooltipText, isSection)
    if not CUI._RegisterSearchEntry then return end
    if type(labelText) ~= "string" or labelText == "" then return end
    local loc = CUI.L(labelText)
    local sel = CUI._buildingSelector
    CUI._RegisterSearchEntry(
        labelText,
        loc ~= labelText and loc or nil,
        type(tooltipText) == "string" and tooltipText or nil,
        CUI._buildingModule,
        CUI._buildingPage,
        isSection and labelText or _absSection,
        sel and sel.setter,
        sel and sel.key,
        isSection or nil
    )
end

local AbsorberW = {}
function AbsorberW:SectionHeader(hostFrame, textValue, yOffset)
    _absSection = textValue
    RegisterAbsorbed(textValue, nil, true)
    return MakeAbsorber(), 40
end
function AbsorberW:Toggle(hostFrame, textValue, yOffset, getValue, setValue, tipText)
    RegisterAbsorbed(textValue, tipText)
    return MakeAbsorber(), 40
end
function AbsorberW:Slider(
    hostFrame,
    textValue,
    yOffset,
    minVal,
    maxVal,
    step,
    getValue,
    setValue,
    tipText,
    pixel
)
    RegisterAbsorbed(textValue, tipText)
    return MakeAbsorber(), 40
end
function AbsorberW:Dropdown(hostFrame, textValue, yOffset, values, getValue, setValue, sequence, tipText)
    RegisterAbsorbed(textValue, tipText)
    return MakeAbsorber(), 40
end
function AbsorberW:Checkbox(hostFrame, textValue, yOffset, getValue, setValue, tipText)
    RegisterAbsorbed(textValue, tipText)
    return MakeAbsorber(), 40
end
function AbsorberW:ColorPicker(hostFrame, textValue, yOffset, getValue, setValue, hasAlpha)
    RegisterAbsorbed(textValue, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:Button(hostFrame, textValue, yOffset, onClick)
    RegisterAbsorbed(textValue, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:WideButton(hostFrame, textValue, yOffset, onClick, btnWidth)
    RegisterAbsorbed(textValue, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:DualRow(hostFrame, yOffset, leftConfig, rightConfig)
    -- A row the live factory hides for Blizzard Style has nothing to find.
    local BS = CUI.BlizzStyle
    if BS and BS.RowHidden and BS.RowHidden(leftConfig, rightConfig) then return MakeAbsorber(), 0 end
    RegisterAbsorbed(leftConfig and leftConfig.text, leftConfig and leftConfig.tooltip)
    RegisterAbsorbed(rightConfig and rightConfig.text, rightConfig and rightConfig.tooltip)
    return MakeAbsorber(), 40
end
function AbsorberW:TripleRow(hostFrame, yOffset, leftConfig, midCfg, rightConfig, splits)
    RegisterAbsorbed(leftConfig and leftConfig.text, leftConfig and leftConfig.tooltip)
    RegisterAbsorbed(midCfg and midCfg.text, midCfg and midCfg.tooltip)
    RegisterAbsorbed(rightConfig and rightConfig.text, rightConfig and rightConfig.tooltip)
    return MakeAbsorber(), 40
end
function AbsorberW:MultiSwatchRow(hostFrame, yOffset, conf)
    RegisterAbsorbed(conf and conf.text, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:DropdownWithOffsets(hostFrame, yOffset, dropdownCfg, xSliderCfg, ySliderCfg)
    RegisterAbsorbed(dropdownCfg and dropdownCfg.text, dropdownCfg and dropdownCfg.tooltip)
    RegisterAbsorbed(xSliderCfg and xSliderCfg.text, xSliderCfg and xSliderCfg.tooltip)
    RegisterAbsorbed(ySliderCfg and ySliderCfg.text, ySliderCfg and ySliderCfg.tooltip)
    return MakeAbsorber(), 40
end
function AbsorberW:WideDualButton(hostFrame, text1, text2, yOffset, onClick1, onClick2, btnWidth)
    RegisterAbsorbed(text1, nil)
    RegisterAbsorbed(text2, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:WideTripleButton(
    hostFrame,
    text1,
    text2,
    text3,
    yOffset,
    onClick1,
    onClick2,
    onClick3,
    btnWidth,
    disabledOpts
)
    RegisterAbsorbed(text1, nil)
    RegisterAbsorbed(text2, nil)
    RegisterAbsorbed(text3, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:WideDropdown(
    hostFrame,
    title,
    yOffset,
    values,
    getValue,
    setValue,
    sequence,
    btnWidth,
    disabledValuesFn
)
    RegisterAbsorbed(title, nil)
    return MakeAbsorber(), 40
end
function AbsorberW:TripleDropdown(hostFrame, configList, yOffset)
    RegisterAbsorbed(configList and configList[1] and configList[1][1], nil)
    RegisterAbsorbed(configList and configList[2] and configList[2][1], nil)
    RegisterAbsorbed(configList and configList[3] and configList[3][1], nil)
    return MakeAbsorber(), 40
end
function AbsorberW:TripleSlider(hostFrame, configList, yOffset)
    -- Parity with the real factory: it tags an EMPTY row label and indexes
    -- no slots, so the absorber registers nothing either.
    return MakeAbsorber(), 40
end
function AbsorberW:Spacer(hostFrame, yOffset, height) return MakeAbsorber(), height or 20 end
-- Any factory method NOT stubbed above (added later, or missed): absorb it
-- rather than erroring the whole page -- the page still indexes everything
-- its known widgets register; dev mode announces the gap so the stub gets
-- added per the maintenance contract.
setmetatable(AbsorberW, {
    __index = function(_, key)
        if CUI.IsDevModeActive() then
            print(
                "|cffff6060CUI GlobalSearch:|r no absorber stub for W:"
                    .. tostring(key)
                    .. " -- its rows are invisible to search until built live. Add a stub."
            )
        end
        return function() return MakeAbsorber(), 40 end
    end,
})

local function PrebuildOnce(moduleConfig, moduleFolder, pageEntry, selectorSetter, selectorKey)
    if not _hiddenParent then
        _hiddenParent = CreateFrame("Frame", nil, UIParent)
        _hiddenParent:Hide()
    end
    if selectorSetter and selectorKey then selectorSetter(selectorKey) end

    -- ONE reused wrapper for every job: with the widget factory absorbed,
    -- the only things ever created on it are the rare custom-chrome frames
    -- a few builders make directly -- not the per-page widget mass.
    local wrapper = _absWrapper
    if not wrapper then
        wrapper = CreateFrame("Frame", nil, _hiddenParent)
        wrapper:SetSize(1030, 4000)
        _absWrapper = wrapper
    end
    CUI._buildingModule = moduleFolder
    CUI._buildingPage = pageEntry
    CUI._prebuilding = true

    -- Isolate the shared widget-refresh registry so this off-screen build's
    -- widgets can never leak their refresh closures into whatever page the
    -- user is actually looking at (or into that page's cache snapshot).
    local refreshSnap = CUI._SnapshotAndClearWidgetRefreshList()
    -- buildPage functions call some live game APIs (currency lists, class info)
    -- directly during construction, not only inside getValue closures. pcall so one
    -- module's edge case can never block indexing the rest; any such page simply falls
    -- back to being indexed by live navigation instead. Surfaced in dev mode so a
    -- genuinely broken builder is not silently swallowed forever by the indexing pass.
    -- FRAMELESS: the widget factory is swapped to the absorber for exactly
    -- this synchronous call (builders fetch `local W = CludesUI.Widgets`
    -- inside their bodies -- verified no file-scope captures 2026-08-03),
    -- and restored on EVERY exit before anything else can read it.
    _absSection = nil
    local realWidgets = CUI.Widgets
    CUI.Widgets = AbsorberW
    local success, err = pcall(moduleConfig.buildPage, pageEntry, wrapper, -6)
    CUI.Widgets = realWidgets
    if not success and CUI.IsDevModeActive() then
        print(
            "|cffff6060CUI GlobalSearch:|r prebuild failed for "
                .. tostring(moduleFolder)
                .. "::"
                .. tostring(pageEntry)
                .. ": "
                .. tostring(err)
        )
    end
    if refreshSnap then CUI._RestoreWidgetRefreshList(refreshSnap) end

    -- Some buildPage implementations register cleanup (event listeners, etc.) via
    -- parent:HookScript("OnHide", ...), expecting it to fire once the user navigates
    -- away. Hide the wrapper on the chance that helps -- but don't rely on it: a frame
    -- that's never been effectively visible (its ancestor, _hiddenParent, was hidden
    -- before wrapper was ever shown) may not fire OnHide just because wrapper:Hide() is
    -- called on it. Any buildPage that registers session-long listeners (event frames,
    -- etc.) must guard their creation with CludesUI._prebuilding itself rather than
    -- depend on this to clean them up.
    wrapper:Hide()

    CUI._buildingModule = nil
    CUI._buildingPage = nil
    CUI._buildingSelector = nil
    CUI._prebuilding = nil
end

-- One job = ONE hidden page build. Selector variants are expanded into
-- separate jobs at list-build time (not looped synchronously inside a single
-- job) because the variant pages are the suite's heaviest; the per-frame
-- budget in RunPrebuildPass then spreads them across frames.
local function PrebuildJob(task)
    local moduleConfig = task.config
    if not moduleConfig.buildPage then return end
    -- Re-check (not just at job-list-build time): the staggered pass spans many
    -- frames, so the player may have visited and cached this exact page live in the
    -- meantime -- rebuilding it hidden would be a redundant, wasted build. The selector
    -- restore still runs: the live visit happened at whatever selection the player made
    -- themselves, but an EARLIER variant job may have left the module's selector moved.
    local cacheKey = task.folder .. "::" .. task.page
    if not (mod.pageCache and mod.pageCache[cacheKey] and not mod.pageCache[cacheKey].stale) then
        local savedMethods = {}
        for _, name in ipairs(_CONTENT_HEADER_METHODS) do
            savedMethods[name] = CUI[name]
            CUI[name] = function() end
        end
        PrebuildOnce(moduleConfig, task.folder, task.page, task.selectorSetter, task.selectorKey)
        for _, name in ipairs(_CONTENT_HEADER_METHODS) do
            CUI[name] = savedMethods[name]
        end
    end
    -- Set on the LAST variant job of a page: restore whatever the player actually had
    -- selected so a later live visit isn't left showing the last-built variant.
    if task.restoreSetter and task.restoreKey then task.restoreSetter(task.restoreKey) end
end

-- Deliberately NOT run at login: even frameless, running every page builder costs real
-- CPU, so only users who actually use the search ever pay it. Since 2026-08-03 the pass
-- builds NO frames (absorber layer above): its entire footprint is the index strings
-- plus transient garbage, versus the old hidden-build's 10-25MB of permanent page
-- frames. Focusing the search box (or its first query) triggers this pass (see
-- EnsureSearchUI); coarse module/page results need no build and show immediately,
-- and onComplete re-runs the query so late-indexed rows appear without retyping.
local PREBUILD_BUDGET_MS = 4

local function RunPrebuildPass(onComplete)
    if _prebuildDone then return end
    _prebuildDone = true

    local jobs = {}
    for moduleFolder, moduleConfig in pairs(mod.modules or {}) do
        -- Plugins can opt a module out of the hidden pass (searchPrebuild =
        -- false); its pages are then indexed by live navigation only.
        if moduleConfig.pages and moduleConfig._searchPrebuild ~= false then
            for _, pageEntry in ipairs(moduleConfig.pages) do
                -- Already indexed by live navigation -- skip it. Rebuilding it
                -- hidden would be redundant, and would also reassign whatever
                -- module-global closures (header builders, etc.) that page's
                -- buildPage captures to hidden-build versions that a later
                -- cache-restore could pick up instead of the live ones.
                local cacheKey = moduleFolder .. "::" .. pageEntry
                -- A link tab (config.pageLinks) has no page of its own to build.
                if
                    not (mod.pageCache and mod.pageCache[cacheKey] and not mod.pageCache[cacheKey].stale)
                    and not (moduleConfig.pageLinks and moduleConfig.pageLinks[pageEntry])
                then
                    -- Selector-driven pages (CDM bar / unit dropdowns) expand to one
                    -- job PER variant so each tick stays one build; the last variant
                    -- job carries the restore of the player's own selection.
                    local spellings = moduleConfig.getPrebuildVariants
                        and moduleConfig.getPrebuildVariants(pageEntry)
                    if spellings and spellings.keys and #spellings.keys > 0 then
                        for k, key in ipairs(spellings.keys) do
                            local task = {
                                folder = moduleFolder,
                                page = pageEntry,
                                config = moduleConfig,
                                selectorSetter = spellings.setter,
                                selectorKey = key,
                            }
                            if k == #spellings.keys and spellings.setter and spellings.currentKey then
                                task.restoreSetter = spellings.setter
                                task.restoreKey = spellings.currentKey
                            end
                            jobs[#jobs + 1] = task
                        end
                    else
                        jobs[#jobs + 1] = { folder = moduleFolder, page = pageEntry, config = moduleConfig }
                    end
                end
            end
        end
    end

    local idx = 0
    local function StepJob()
        -- A full page build is a multi-millisecond main-thread hit; never do
        -- that during combat. Pause the pass and resume once combat ends.
        if InCombatLockdown() then
            CUI.CombatQueue.Defer(StepJob, function() C_Timer.After(0.05, StepJob) end)
            return
        end
        -- As many builds as fit in a small per-frame budget (at least one),
        -- then yield a frame: fast to finish without a visible hitch.
        local t0 = debugprofilestop()
        repeat
            idx = idx + 1
            local task = jobs[idx]
            if not task then
                if onComplete then onComplete() end
                return
            end
            PrebuildJob(task)
        until debugprofilestop() - t0 > PREBUILD_BUDGET_MS
        C_Timer.After(0, StepJob)
    end
    if jobs[1] then
        -- Next frame, not synchronously: the trigger is a keystroke handler
        -- and the first page build should not lag the typing.
        C_Timer.After(0, StepJob)
    elseif onComplete then
        onComplete()
    end
end

-------------------------------------------------------------------------------
--  Persistent search entry point + results popup.
--
--  Reuses the existing always-visible sidebar search box (placeholder
--  "Search Features...", CludesUI._sidebarSearchBox) as the entry point
--  rather than adding a new button/box of our own -- it's already the
--  natural, always-visible "search" affordance in the panel. We only add a
--  results popup beneath it via HookScript, so the box's existing behavior
--  (filtering the sidebar addon/page list) is untouched.
-------------------------------------------------------------------------------
local _searchUIBuilt = false
local dialog, resultRows
local results, selIdx = {}, 1 -- last shown results; Tab/arrows move selIdx, Enter opens it

local RESULT_ROW_H = 34
local RESULT_ROW_GAP = 4 -- breathing room between result rows
local MAX_VISIBLE_RESULTS = 12

local function GetModuleDisplayName(moduleFolder)
    local moduleConfig = mod.modules and mod.modules[moduleFolder]
    if moduleConfig and moduleConfig.title then return (ModuleLabel(moduleConfig, moduleFolder)) end
    if CUI.ADDON_ROSTER then
        for _, record in ipairs(CUI.ADDON_ROSTER) do
            if record.folder == moduleFolder then return CUI.L(record.display) end
        end
    end
    return moduleFolder
end

local function JoinBreadcrumb(...)
    local parts = {}
    for idx = 1, select("#", ...) do
        local val = select(idx, ...)
        -- A page named like its module (Objective Tracker > Objective Tracker) once.
        if val and val ~= "" and val ~= parts[#parts] then parts[#parts + 1] = val end
    end
    return table.concat(parts, BREADCRUMB_ARROW)
end

-- Section headers are ALL CAPS in the option pages ("GLOBAL OPTIONS");
-- results display them as Title Case ("Global Options"). ASCII-only word
-- matching: non-Latin localized names pass through unchanged, which is the
-- safe outcome. Display-only -- the index keeps the raw name for matching.
local function TitleCaseSection(text)
    -- Only ALL-CAPS names need the conversion. Already mixed-case section
    -- labels (window-skin card titles like "LFG Menu") pass through
    -- untouched -- lowering them first would mangle acronyms ("Lfg Menu").
    if text ~= text:upper() then return text end
    return (text:lower():gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest end))
end

local function JumpToResult(record, sidebarSearchBox)
    -- Coarse (whole-page) results have no single option to highlight -- just land on
    -- the page. Fine-grained option/section results scroll to and glow the specific
    -- matching row via CludesUI:NavigateToElementSettings (the same deep-link
    -- machinery the What's New page uses) instead of ApplyInlineSearch: that function
    -- is a *filter* -- it hides every section that doesn't match -- so reusing it
    -- here to "highlight" a single row could collapse the whole page down to just
    -- that one row's section, or even to nothing at all if the matched row isn't part
    -- of the page's current state (e.g. a CDM bar-type-specific option while a
    -- different bar is selected). NavigateToElementSettings only scrolls + glows; it
    -- never hides anything, so a row it can't currently find (same bar-type case)
    -- just means no scroll/glow happens -- the page is left exactly as the player
    -- already had it, not blanked out.
    if record.kind == "page" or not record.section then
        CUI:SelectModule(record.module)
        CUI:SelectPage(record.page)
    else
        -- Some pages (CDM Bars, Action Bars Display, Unit Frames) show
        -- entirely different content depending on an internal selector --
        -- which bar/unit is picked via that page's own dropdown -- so the
        -- matched row may not exist under whatever selection happens to be
        -- active right now. If this entry was registered under a specific
        -- selection, restore that exact selection first (NavigateToElement-
        -- Settings' preSelectFn) so the row is actually there to find.
        local preSelectFn
        if record.selectorSetter and record.selectorKey then
            preSelectFn = function() record.selectorSetter(record.selectorKey) end
        end
        CUI:NavigateToElementSettings(
            record.module,
            record.page,
            record.section,
            preSelectFn,
            record.label
        )
    end
    if dialog then dialog:Hide() end
    if sidebarSearchBox then sidebarSearchBox:SetText("") end
end

local function EnsureSearchUI()
    if _searchUIBuilt then return end
    local clickArea = CUI._clickArea
    local sidebarSearchBox = CUI._sidebarSearchBox
    if not clickArea or not sidebarSearchBox then return end
    _searchUIBuilt = true

    local Pix = CUI.PanelPP or CUI.PP
    local fontFile = (CUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"

    -- Results popup, anchored below the existing sidebar search box.
    dialog = CreateFrame("Frame", nil, clickArea)
    dialog:SetSize(380, MAX_VISIBLE_RESULTS * (RESULT_ROW_H + RESULT_ROW_GAP) - RESULT_ROW_GAP + 8)
    dialog:SetPoint("TOPLEFT", sidebarSearchBox, "BOTTOMLEFT", 0, -4)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(220)
    dialog:SetClampedToScreen(true)
    dialog:Hide()
    local popupBg = dialog:CreateTexture(nil, "BACKGROUND")
    popupBg:SetAllPoints()
    popupBg:SetColorTexture(0.062, 0.070, 0.082, 0.97)
    dialog._brd = CUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.12, popupBg)
    -- House look: an accent cap; hovered and selected results take an accent wash.
    local cap = dialog:CreateTexture(nil, "ARTWORK", nil, 3)
    cap:SetPoint("TOPLEFT")
    cap:SetPoint("TOPRIGHT")
    cap:SetHeight(2)
    dialog:HookScript("OnShow", function()
        local color = CUI.CLUDES_GREEN
        cap:SetColorTexture(color.r, color.g, color.b, 0.9)
    end)
    local function Wash(texture, enabled)
        local color = CUI.CLUDES_GREEN
        texture:SetColorTexture(color.r, color.g, color.b, enabled and 0.16 or 0)
    end

    local resultsFrame = CreateFrame("Frame", nil, dialog)
    resultsFrame:SetPoint("TOPLEFT", dialog, "TOPLEFT", 4, -4)
    resultsFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -4, 4)

    resultRows = {}
    for idx = 1, MAX_VISIBLE_RESULTS do
        local line = CreateFrame("Button", nil, resultsFrame)
        line:SetHeight(RESULT_ROW_H)
        line:SetPoint("TOPLEFT", resultsFrame, "TOPLEFT", 1, -(idx - 1) * (RESULT_ROW_H + RESULT_ROW_GAP))
        line:SetPoint("TOPRIGHT", resultsFrame, "TOPRIGHT", -1, -(idx - 1) * (RESULT_ROW_H + RESULT_ROW_GAP))

        local highlight = line:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0)

        local labelFS = line:CreateFontString(nil, "OVERLAY")
        CUI.PrimeFontShadow(labelFS, true)
        labelFS:SetFont(fontFile, 14, "")
        labelFS:SetTextColor(0.85, 0.85, 0.88, 1)
        labelFS:SetPoint("LEFT", line, "LEFT", 8, 8)
        labelFS:SetPoint("RIGHT", line, "RIGHT", -8, 8)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)

        local sub = line:CreateFontString(nil, "OVERLAY")
        CUI.PrimeFontShadow(sub, true)
        sub:SetFont(fontFile, 12, "")
        sub:SetTextColor(1, 1, 1, 0.45)
        sub:SetPoint("LEFT", line, "LEFT", 8, -9)
        sub:SetJustifyH("LEFT")

        line:SetScript("OnEnter", function() Wash(highlight, true) end)
        line:SetScript(
            "OnLeave",
            function() Wash(highlight, (idx == selIdx and results[idx]) and true or false) end
        )

        line._hl = highlight
        line._label = labelFS
        line._sub = sub
        line:Hide()
        resultRows[idx] = line
    end

    local function SetSelected(idx)
        Wash(resultRows[selIdx]._hl, false)
        selIdx = idx
        Wash(resultRows[selIdx]._hl, true)
    end

    local RunSearch
    -- Set once the index pass has finished: before that, 0 results may only
    -- mean "not indexed yet", so the "No results" row waits for it.
    local indexReady = false
    -- Started on focus, before the first letter, so the index is usually
    -- complete by the time a query is typed.
    local function StartPrebuild()
        if _prebuildDone then return end
        RunPrebuildPass(function()
            indexReady = true
            if sidebarSearchBox:GetText() ~= "" then RunSearch() end
        end)
    end
    sidebarSearchBox:HookScript("OnEditFocusGained", StartPrebuild)

    RunSearch = function()
        local searchText = sidebarSearchBox:GetText()
        -- The index pass normally started on focus; a query typed without focus
        -- (e.g. pasted) starts it here. Coarse module/page results show immediately;
        -- the pass re-runs the query when it finishes. While a search is active, every "Show
        -- Less Common" section renders force-expanded with no link line; clearing the
        -- box collapses them back to their session state (transitions rebuild -- see
        -- SetLessCommonSearchActive in CludesUI_Widgets.lua).
        if CUI.SetLessCommonSearchActive then CUI.SetLessCommonSearchActive(searchText ~= "") end
        if searchText ~= "" then StartPrebuild() end
        -- Old names still find what was renamed (Layout Mode is Edit Layout now).
        local typed = searchText:lower():match("^%s*(.-)%s*$")
        local QUERY_ALIASES = {
            ["layout mode"] = "edit layout",
            ["unlock mode"] = "edit layout",
            ["move frames"] = "edit layout",
            ["unlock frames"] = "edit layout",
        }
        results = SearchIndex(QUERY_ALIASES[typed] or searchText, MAX_VISIBLE_RESULTS)
        -- Accent-colored "Page:"/"Section:" prefixes. Hex is computed per
        -- search, so a live accent change is picked up on the next keystroke.
        local ACC = CUI.CLUDES_GREEN
        local accentHex = ACC and CUI.HexColor(ACC.r, ACC.g, ACC.b) or CUI.COLOR_CODES.WHITE
        for idx, line in ipairs(resultRows) do
            local record = results[idx]
            if record then
                if record.kind == "page" then
                    -- Coarse whole-page result: prefixed like sections so it
                    -- reads as "go to this page", not a specific option on it.
                    line._label:SetText(accentHex .. CUI.L("Page") .. ":|r " .. record.displayLabel)
                    line._sub:SetText(record.moduleLabel)
                elseif record.isSection then
                    local name = TitleCaseSection(record.label)
                    if record.labelLoc then
                        name = name .. "  (" .. TitleCaseSection(record.labelLoc) .. ")"
                    end
                    line._label:SetText(accentHex .. CUI.L("Section") .. ":|r " .. name)
                    line._sub:SetText(
                        JoinBreadcrumb(
                            GetModuleDisplayName(record.module),
                            PageLabel(record.module, record.page)
                        )
                    )
                else
                    line._label:SetText(
                        record.labelLoc and (record.label .. "  (" .. record.labelLoc .. ")") or record.label
                    )
                    line._sub:SetText(
                        JoinBreadcrumb(
                            GetModuleDisplayName(record.module),
                            PageLabel(record.module, record.page)
                        )
                    )
                end
                line:SetScript("OnClick", function() JumpToResult(record, sidebarSearchBox) end)
                line:EnableMouse(true)
                line:Show()
            else
                line:Hide()
            end
        end
        SetSelected(1)
        local isShown = #results
        if isShown == 0 and indexReady and searchText:match("%S") then
            -- Inert "No results" row instead of an empty popup. Pipes are
            -- shown literally so the query cannot inject escape codes.
            local line = resultRows[1]
            local q = searchText:gsub("||", "|"):gsub("|", "||")
            line._label:SetText(CUI.Lf("No results for %s", '"' .. q .. '"'))
            line._sub:SetText(CUI.L("Check the spelling or try a different word"))
            line._hl:SetColorTexture(1, 1, 1, 0)
            line:SetScript("OnClick", nil)
            line:EnableMouse(false)
            line:Show()
            isShown = 1
        end
        if isShown > 0 then
            local num = math.min(isShown, MAX_VISIBLE_RESULTS)
            dialog:SetHeight(num * (RESULT_ROW_H + RESULT_ROW_GAP) - RESULT_ROW_GAP + 8)
            -- Retyped while shown: refit the outline's bottom edge.
            dialog._brd:Fit()
            dialog:Show()
        else
            dialog:Hide()
        end
    end

    -- HookScript adds to the box's existing handlers rather than replacing
    -- them, so the sidebar addon/page filtering it already does keeps working.
    sidebarSearchBox:HookScript("OnTextChanged", RunSearch)
    sidebarSearchBox:HookScript("OnEnterPressed", function(self)
        if results[selIdx] then JumpToResult(results[selIdx], self) end
    end)
    local function Step(d)
        local num = #results
        if num > 0 and dialog:IsShown() then SetSelected((selIdx - 1 + d) % num + 1) end
    end
    sidebarSearchBox:HookScript("OnTabPressed", function() Step(IsShiftKeyDown() and -1 or 1) end)
    sidebarSearchBox:HookScript("OnArrowPressed", function(_, key)
        if key == "UP" then
            Step(-1)
        elseif key == "DOWN" then
            Step(1)
        end
    end)

    -- Click-anywhere-else closes the results: a global mouse-down listener
    -- registered only while the popup is shown (the same pattern as the
    -- dropdown widgets) -- non-blocking, world clicks pass through, and no
    -- per-frame OnUpdate work. Row clicks fire on mouse UP, and the DOWN
    -- lands while the cursor is over the popup, so results stay clickable.
    local clickOff = CreateFrame("Frame")
    clickOff:SetScript("OnEvent", function()
        if not dialog:IsMouseOver() and not sidebarSearchBox:IsMouseOver() then dialog:Hide() end
    end)
    dialog:SetScript("OnShow", function() clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    dialog:SetScript("OnHide", function() clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
end

-------------------------------------------------------------------------------
--  Wire the search hooks into the panel the first time it's opened, via any
--  entry point (Show / Toggle / ShowModule all funnel through the panel's
--  internal CreateMainFrame, which is what creates the sidebar search box
--  this file hooks into). No edits to CludesUI.lua needed for this --
--  standard same-addon method wrapping from a later-loaded file.
-------------------------------------------------------------------------------
for _, methodName in ipairs({ "Show", "Toggle", "ShowModule" }) do
    local original = CUI[methodName]
    if original then
        CUI[methodName] = function(self, ...)
            original(self, ...)
            EnsureSearchUI()
        end
    end
end
