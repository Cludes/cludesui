if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CludesUIGroupFinder.lua: premade group filters, list tweaks and the M+
-- applications bar. Nothing hooks in until it's enabled.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.Lite
        and CludesUI.HELD_BACK_ADDONS
        and CludesUI.SetFontFamily
        and CludesUI.PREVIEW_ROSTER
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (group titles, applicant names and notes take font families through SetFontFamily, and the settings preview names its samples from PREVIEW_ROSTER)
-- Held back from this release (CludesUI.HELD_BACK_ADDONS): nothing runs,
-- and with no namespace published the options page never registers.
if CludesUI.HELD_BACK_ADDONS[ADDON_NAME] then return end
CludesUI._ModuleNS[ADDON_NAME] = mod -- options file grabs the ns from here

local GF = CludesUI.Lite.NewAddon(ADDON_NAME)
-- Work on Blizzard frames that waits for combat to end; inert until a Defer.
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

local DEFAULTS = {
    padding = 12,
    nameColors = false,
    classTooltip = true,
    leaderRating = true,
    leaderCrown = true,
    missingRoles = true,
    specIcons = true,
    iconSize = 125,
    cancelOldest = false,
    dungeonAbbr = false,
    dungeonScore = false,
}
mod.DEFAULTS = DEFAULTS

local APPS_DEFAULTS = {
    enabled = false,
    scope = "character",
    texture = "none",
    showAccepted = true,
    showDeclined = true,
    showDelisted = true,
    showCancelled = true,
}
mod.APPS_DEFAULTS = APPS_DEFAULTS

local saved

local function Profile() return saved and saved.profile end

-- Account-wide bits live in CludesUIDB.<key>, outside profiles.
local function Account(key)
    if not CludesUIDB then CludesUIDB = {} end
    local t = CludesUIDB[key]
    if type(t) ~= "table" then
        t = {}
        CludesUIDB[key] = t
    end
    return t
end

-- Account-wide so profile swaps and imports never flip it.
function mod.Enabled()
    local tbl = CludesUIDB and CludesUIDB.groupFinder
    return type(tbl) == "table" and tbl.enabled == true or false
end

function mod.SetEnabled(val) Account("groupFinder").enabled = val and true or false end

-- True while another premade groups filter that hooks the same panel is loaded:
-- Group Finder can't be turned on then (its page and the login announcement ask).
function mod.Blocked() return C_AddOns.IsAddOnLoaded("PremadeGroupsFilter") and true or false end

-- Read-only defaults until the profile's ready.
local readOnly = {
    search = setmetatable({}, { __index = DEFAULTS, __newindex = function() end }),
    apps = setmetatable({}, { __index = APPS_DEFAULTS, __newindex = function() end }),
}

local function Search()
    local profile = Profile()
    return profile and profile.search or readOnly.search
end

-- filters belong to the character, everything else to the profile
local FILTER_KEYS = {}
for _, k in ipairs({
    "ratingOn",
    "ratingValue",
    "regions",
    "delves",
    "delveTiers",
    "bosses",
    "raidDiffs",
    "raidPlaystyles",
    "raidRoles",
    "partyFit",
    "notDeclined",
    "hasLust",
    "hasBrez",
    "extraMyClass",
    "raidMyClass",
    "extraExpr",
    "extraRolesAny",
    "roleCounts",
    "dimPicks",
}) do
    FILTER_KEYS[k] = true
end

local charDB
local function CharFilters() return charDB and charDB.filters end

local conf = setmetatable({}, {
    __index = function(_, key)
        if FILTER_KEYS[key] then
            local frame = CharFilters()
            return frame and frame[key]
        end
        return Search()[key]
    end,
    __newindex = function(_, key, val)
        if FILTER_KEYS[key] then
            local frame = CharFilters()
            if frame then frame[key] = val end
            return
        end
        Search()[key] = val
    end,
})

function mod.Cfg() return conf end

-- blizzard's dungeon picks for this character, nil until saved once
function mod.CharBlizzFilter() return charDB and charDB.blizz end
function mod.SetCharBlizzFilter(t)
    if charDB then charDB.blizz = t end
end

-- the results and applicant lists' display settings, in the profile (read-only
-- until the profile's ready)
local ownListRO = setmetatable({}, { __newindex = function() end })
function mod.OwnListDB()
    local profile = Profile()
    if not profile then return ownListRO end
    local t = profile.ownList
    if type(t) ~= "table" then
        t = {}
        profile.ownList = t
    end
    return t
end

function mod.AppsCfg()
    local profile = Profile()
    return profile and profile.apps or readOnly.apps
end

function mod.AppCountsStore()
    local tbl = Account("groupFinderApps")
    if type(tbl.dungeon) ~= "table" then tbl.dungeon = {} end
    return tbl.dungeon
end

function mod.ResetSettings()
    if saved then saved:ResetProfile() end
    if charDB then wipe(charDB.filters) end
end

function GF:OnInitialize()
    saved = CludesUI.Lite.NewDB(
        "CludesUIGroupFinderDB",
        { profile = { search = DEFAULTS, apps = APPS_DEFAULTS } }
    )
    if type(CludesUIGroupFinderCharDB) ~= "table" then CludesUIGroupFinderCharDB = {} end
    charDB = CludesUIGroupFinderCharDB
    if type(charDB.filters) ~= "table" then
        -- a character's first login with filters of its own: it starts from a
        -- copy of the profile's, which stay for the characters that log in later
        local filters = {}
        local cfg = Profile() and Profile().search
        if cfg then
            for key in pairs(FILTER_KEYS) do
                local val = cfg[key]
                if type(val) == "table" then val = CopyTable(val) end
                filters[key] = val
            end
        end
        charDB.filters = filters
    end
end

function GF:OnEnable()
    if not mod.Enabled() then return end
    -- PGF hooks the same panel, so we turn ourselves off while it's loaded.
    if mod.Blocked() then
        mod.SetEnabled(false)
        CludesUI.Print(
            CludesUI.COLOR_CODES.BRAND
                .. "CludesUI|r "
                .. CludesUI.L("Group Finder has been turned off because Premade Groups Filter is loaded.")
        )
        return
    end

    if mod.Apps_Enable then mod.Apps_Enable() end
    local function Start()
        if mod.Search_OnEnable then mod.Search_OnEnable() end
    end
    if C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder") and PVEFrame then
        Start()
        return
    end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, _, name)
        if name == "Blizzard_GroupFinder" then
            self:UnregisterEvent("ADDON_LOADED")
            Start()
        end
    end)
end
