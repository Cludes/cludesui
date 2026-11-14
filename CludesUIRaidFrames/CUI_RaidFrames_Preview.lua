if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Preview.lua
--
--  The options preview's shared data: the sample rosters and icon tables,
--  and ns._previewInternals for the CUI_RaidFrames_Preview*.lua files behind
--  it, which hold the preview itself (fake members, the tickers, the
--  real-frame overlay, the size preview). Loads behind the CUI_RaidFrames_*.lua
--  chain and reads it through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...

local Inner = mod._internals
-- CludesUIRaidFrames.lua or one of the CUI_RaidFrames_*.lua files failed to load.
if not Inner or Inner.broken then
    return
end

-------------------------------------------------------------------------------
--  Options preview (fake raid members when options panel is open)
--  Shows 20 buttons with randomized class colors and names so the user
--  can see their settings applied without needing a real group.
-------------------------------------------------------------------------------
mod._PV_CLASS_TOKENS = CludesUI.CLASS_TOKEN_ORDER
mod._PV_TANK_CLASSES = { "WARRIOR", "PALADIN", "DEATHKNIGHT", "MONK", "DRUID", "DEMONHUNTER" }
mod._PV_HEALER_CLASSES = { "PRIEST", "PALADIN", "SHAMAN", "MONK", "DRUID", "EVOKER" }
mod._PV_DPS_CLASSES = mod._PV_CLASS_TOKENS
mod._PV_EXT_ICONS = {
    572025,
    135936,
    237542,
    627485,
    135964,
    135966,
    4622478,
}
mod._PV_DEF_ICONS = {
    DEATHKNIGHT = { 237525, 136120 },
    DEMONHUNTER = { 1305150, 463284 },
    DRUID = { 136097, 236169 },
    EVOKER = { 1394891 },
    HUNTER = { 132199, 136094 },
    MAGE = { 135841, 609811 },
    MONK = { 615341, 620827 },
    PALADIN = { 524353, 524354 },
    PRIEST = { 237550, 237563 },
    ROGUE = { 136177, 132294 },
    SHAMAN = { 538565 },
    WARLOCK = { 136146, 136150 },
    WARRIOR = { 132336, 132361 },
}
mod._PV_NAMES = {
    "Thaldrin",
    "Kaelara",
    "Morgath",
    "Sylvaris",
    "Drakmoor",
    "Elyndra",
    "Bronthar",
    "Velisara",
    "Grimjaw",
    "Luneth",
    "Ashvane",
    "Tormund",
    "Ravynne",
    "Zulkhar",
    "Brightwing",
    "Fenwick",
    "Dawnforge",
    "Nighthollow",
    "Stormhelm",
    "Embertide",
}
-- CUI LEGENDS event roster (the parent's CludesUI.PREVIEW_ROSTER, shared with
-- Group Finder's settings preview). Preview slot 1 is always the player; entries
-- 1-19 fill slots 2-20. Name, class and role travel together through the role
-- sort (ns._pvNames).
mod._PV_ROSTER = CludesUI.PREVIEW_ROSTER
mod._PV_DISPEL_DB_ICONS = {
    Magic = 135735,
    Curse = 132291,
    Disease = 237535,
    Poison = 132106,
    [""] = 4547635,
}
mod._PV_DEBUFF_ICONS = { 135813, 136139, 132090, 136197, 135849, 136188 }
mod._pvActiveAuras = {}

-- What the CUI_RaidFrames_Preview*.lua files share: each file adds the names
-- later files re-import. previewActiveSetters and the list beside it: every file
-- that reads one of these keeps its own copy and adds a setter here; each
-- place that assigns it writes through the Set<Name> function built below,
-- which runs them all.
-- broken: true while an CUI_RaidFrames_Preview*.lua file loads; a file that
-- fails leaves it set, and the files behind it return at their first lines.
CludesUI.NewInternals(mod, "_previewInternals", {
    -- Created here: files that load ahead of CreatePreviewFrame and
    -- BuildPreviewRoles read them too.
    previewFrames = {},
    previewClassTokens = {}, -- [1..20] class token per slot
    previewActiveSetters = {},
    previewContainerSetters = {},
}, {
    SetPreviewActive = "previewActiveSetters",
    SetPreviewContainer = "previewContainerSetters",
})
-- The main chain's visibility passes read the raid preview's state as this plain
-- field (as the party preview's ns._partyPvActive), never a preview function: a
-- preview file that fails to load must not leave them a nil call.
do
    local entries = mod._previewInternals.previewActiveSetters
    entries[#entries + 1] = function(val)
        mod._raidPvActive = val
    end
end
