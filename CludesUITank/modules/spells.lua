local addonName, ns = ...
if ns.standalone then return end

-- All Midnight raid tank spells, grouped by raid > boss, current tier first.
-- threshold: default stack count to trigger a TAUNT alert.
-- Presets default to enabled=false; user opts in via the Alerts tab.
--
-- Spell IDs come from the Adventure Guide entries the Warcraft wiki records for
-- each encounter, taking the abilities it marks as Tank. Only abilities that
-- land ON the tank are listed: a boss self-buff (Entombed Sentinels' Empowering
-- Slam, The Lost Explorers' Steady Strikes and United Defense) can never be
-- found on the co-tank, so alerting on it is impossible.
--
-- Boss order follows the Adventure Guide.

ns.SpellData = {
    raids = {
        -- ──────────────────────────────────────────────────────────────
        --  THE VENOMOUS ABYSS  (Midnight Season 2, Coiled Isle)
        -- ──────────────────────────────────────────────────────────────
        {
            name = "The Venomous Abyss",
            bosses = {
                {
                    name = "Nek'zali the Soulcoiler",
                    spells = {
                        { id = 1284110, name = "Hollowing Strikes",    note = "tank swap",     threshold = 2 },
                        { id = 1284103, name = "Possession Barrage",   note = "tank physical", threshold = 1 },
                    },
                },
                {
                    name = "Entombed Sentinels",
                    spells = {
                        { id = 1284487, name = "Bloodvenom Injection", note = "tank swap",     threshold = 2 },
                    },
                },
                {
                    name = "The Lost Explorers",
                    spells = {
                        { id = 1295854, name = "Shredding Shards",     note = "tank swap",     threshold = 2 },
                    },
                },
                {
                    name = "Vashnik the Malignant",
                    spells = {
                        { id = 1280935, name = "Dripping Fangs",       note = "tank swap",     threshold = 2 },
                    },
                },
                {
                    name = "Sszorak",
                    spells = {
                        { id = 1277002, name = "Ravage",               note = "tank swap",     threshold = 2 },
                        { id = 1282869, name = "Corroding Venom",      note = "tank debuff",   threshold = 2 },
                    },
                },
                {
                    name = "The Twin Fangs",
                    spells = {
                        { id = 1310360, name = "Envenomed",            note = "tank swap",     threshold = 2 },
                        { id = 1289092, name = "Fractured",            note = "tank swap",     threshold = 2 },
                        { id = 1289192, name = "Caustic Deluge",       note = "tank debuff",   threshold = 1 },
                        { id = 1288538, name = "Stone Breaker",        note = "tank physical", threshold = 1 },
                    },
                },
                {
                    name = "The Coiled Altar",
                    spells = {
                        { id = 1298795, name = "Corrupted Toxin",      note = "tank swap",     threshold = 2 },
                        { id = 1300322, name = "Twinfang Toxin",       note = "tank dot",      threshold = 1 },
                        { id = 1299680, name = "Sever",                note = "tank physical", threshold = 1 },
                        { id = 1307279, name = "Blighted Sever",       note = "tank physical", threshold = 1 },
                        { id = 1286620, name = "Soul Sever",           note = "tank physical", threshold = 1 },
                    },
                },
                {
                    name = "Ula'tek",
                    spells = {
                        { id = 1298367, name = "Mother's Wrath",       note = "tank swap",     threshold = 1 },
                        { id = 1299757, name = "Toxic Incubation",     note = "tank debuff",   threshold = 1 },
                        { id = 1305709, name = "Desperate Thrash",     note = "tank attack",   threshold = 1 },
                    },
                },
            },
        },
        -- ──────────────────────────────────────────────────────────────
        --  THE VOIDSPIRE  (Midnight Season 1)
        -- ──────────────────────────────────────────────────────────────
        {
            name = "The Voidspire",
            bosses = {
                {
                    name = "Imperator Averzian",
                    spells = {
                        { id = 1249251, name = "Dark Upheaval",         note = "tank physical", threshold = 1 },
                        { id = 1255680, name = "Gnashing Void",         note = "tank attack",   threshold = 1 },
                        { id = 1255683, name = "Gnashing Void",         note = "tank attack",   threshold = 1 },
                        { id = 1265540, name = "Blackening Wounds",     note = "tank swap",     threshold = 1 },
                        { id = 1280015, name = "Void Marked",           note = "tank marker",   threshold = 1 },
                        { id = 1274846, name = "Dark Barrage",          note = "tank debuff",   threshold = 2 },
                        { id = 1261249, name = "Void Rupture",          note = "tank debuff",   threshold = 2 },
                        { id = 1262036, name = "Void Rupture",          note = "tank debuff",   threshold = 2 },
                        { id = 1275059, name = "Black Miasma",          note = "tank dot",      threshold = 1 },
                    },
                },
                {
                    name = "Vorasius",
                    spells = {
                        { id = 1241844, name = "Smashed",               note = "tank swap",     threshold = 2 },
                    },
                },
                {
                    name = "Fallen-King Salhadaar",
                    spells = {
                        { id = 1245592, name = "Torturous Extract",     note = "tank debuff",   threshold = 2 },
                        { id = 1271577, name = "Destabilizing Strikes", note = "tank swap",     threshold = 1 },
                        { id = 1250828, name = "Void Exposure",         note = "tank debuff",   threshold = 2 },
                        { id = 1250991, name = "Dark Radiation",        note = "tank debuff",   threshold = 2 },
                        { id = 1253032, name = "Shattering Twilight",   note = "tank swap",     threshold = 1 },
                    },
                },
                {
                    name = "Vaelgor & Ezzorak",
                    spells = {
                        { id = 1244221, name = "Dread Breath",          note = "tank swap",     threshold = 1 },
                        { id = 1244413, name = "Nullsnap",              note = "tank debuff",   threshold = 2 },
                        { id = 1245645, name = "Rakfang",               note = "tank debuff",   threshold = 2 },
                        { id = 1265131, name = "Vaelwing",              note = "tank swap",     threshold = 2 },
                        { id = 1264467, name = "Tail Lash",             note = "tank physical", threshold = 1 },
                        { id = 1265152, name = "Impale",                note = "tank swap",     threshold = 1 },
                        { id = 1280458, name = "Grappling Maw",         note = "tank debuff",   threshold = 2 },
                    },
                },
                {
                    name = "Lightblinded Vanguard",
                    spells = {
                        { id = 1246736, name = "Judgment",              note = "tank swap",     threshold = 1 },
                        { id = 1251857, name = "Judgment",              note = "tank swap",     threshold = 1 },
                        { id = 1251812, name = "Final Verdict",         note = "tank physical", threshold = 1 },
                        { id = 1251859, name = "Shield of the Righteous", note = "tank physical", threshold = 1 },
                        { id = 1246745, name = "Exorcism",              note = "tank physical", threshold = 1 },
                    },
                },
                {
                    name = "Crown of the Cosmos",
                    spells = {
                        { id = 1233526, name = "Corrupting Essence",    note = "tank debuff",   threshold = 2 },
                        { id = 1241520, name = "Corrupting Essence",    note = "tank debuff",   threshold = 2 },
                        { id = 1261531, name = "Corrupting Essence",    note = "tank debuff",   threshold = 2 },
                        { id = 1233470, name = "Umbral Tether",         note = "tank tether",   threshold = 1 },
                        { id = 1237844, name = "Umbral Tether",         note = "tank tether",   threshold = 1 },
                        { id = 1233787, name = "Dark Hand",             note = "tank target",   threshold = 1 },
                        { id = 1246461, name = "Rift Slash",            note = "tank swap",     threshold = 2 },
                    },
                },
            },
        },
        -- ──────────────────────────────────────────────────────────────
        --  THE DREAMRIFT  (Midnight Season 1)
        -- ──────────────────────────────────────────────────────────────
        {
            name = "The Dreamrift",
            bosses = {
                {
                    name = "Chimaerus, the Undreamt God",
                    spells = {
                        { id = 1246621, name = "Caustic Phlegm",        note = "tank debuff",   threshold = 2 },
                        { id = 1246653, name = "Caustic Phlegm",        note = "tank debuff",   threshold = 2 },
                        { id = 1262020, name = "Colossal Strikes",      note = "tank swap",     threshold = 1 },
                        { id = 1272726, name = "Rending Tear",          note = "tank physical", threshold = 1 },
                        { id = 1266343, name = "Bleed",                 note = "tank bleed",    threshold = 1 },
                        { id = 1253744, name = "Rift Vulnerability",    note = "tank debuff",   threshold = 2 },
                    },
                },
            },
        },
    },
}

-- True for a spell ID that belongs to the preset list above. Anything else in
-- db.spellAlerts was added by the user.
local presetIds
function ns.SpellData.IsPreset(spellID)
    if not presetIds then
        presetIds = {}
        for _, raid in ipairs(ns.SpellData.raids) do
            for _, boss in ipairs(raid.bosses) do
                for _, spell in ipairs(boss.spells) do presetIds[spell.id] = true end
            end
        end
    end
    return presetIds[tonumber(spellID)] == true
end

-- The user's own alerts as a sorted list of {id, key, alert}. `key` is the
-- table key as stored, which may be a number or a numeric string.
function ns.SpellData.CustomAlerts(db)
    local list = {}
    for key, alert in pairs(db.spellAlerts or {}) do
        local id = tonumber(key)
        if id and type(alert) == "table" and not ns.SpellData.IsPreset(id) then
            list[#list + 1] = {id = id, key = key, alert = alert}
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

-- Seed db.spellAlerts with defaults for any spell not already present.
-- Called each time the options panel is shown (preserves user changes).
function ns.SpellData.SeedDefaults(db)
    db.spellAlerts = db.spellAlerts or {}
    for _, raid in ipairs(ns.SpellData.raids) do
        for _, boss in ipairs(raid.bosses) do
            for _, spell in ipairs(boss.spells) do
                if db.spellAlerts[spell.id] == nil then
                    db.spellAlerts[spell.id] = {
                        enabled   = false,
                        threshold = spell.threshold or 1,
                        preset    = true,
                    }
                end
            end
        end
    end
end
