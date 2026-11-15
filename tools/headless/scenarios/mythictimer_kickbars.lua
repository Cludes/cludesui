-- Mythic+ Tools > Kick Tracker bars: live rows from a stubbed kick engine
-- (members, a cooldown, a placed kick with its marker, an unnamed kick's
-- gate layers, the ticker running down and stopping, a roster change), each
-- style setting, the unlock preview, the options sample, and off.
local CUI = rawget(_G, "CludesUI")
local ns = CUI._ModuleNS.CludesUIMythicTimer
local KE = ns.KickEngine
local function P(...) OUT:write(table.concat({ ... }, " "), "\n") end
if not (KE and ns.KTB_OnEnable) then P("== no kick bars") return end

local cfg = { enabled = true, barWidth = 200, barHeight = 22, barSpacing = 2 }
local db = { profile = { kickTracker = cfg } }

-- The engine, stubbed: three members, cooldowns by unit.
local handlers
local members = {
    player = { guid = "G-player", class = "WARRIOR", kick = 6552 },
    party1 = { guid = "G-p1", class = "MAGE", kick = 2139 },
    party2 = { guid = "G-p2", class = "SHAMAN", kick = 57994 },
}
local cds = {}
KE.GROUP_UNITS = { "player", "party1", "party2", "party3", "party4" }
KE.Subscribe = function(_, h) handlers = h end
KE.Unsubscribe = function() handlers = nil end
KE.Allowed = function() return true end
KE.Member = function(u) return members[u] end
KE.Cooldown = function(u) local c = cds[u] if c then return c[1], c[2] end end
KE.KickDuration = function(u) return members[u] and 15 or nil end
UnitName = function(u) local m = members[u] return m and (m.class:sub(1, 1) .. m.class:sub(2):lower() .. "-" .. u) or u end
GetRaidTargetIndex = function(u) return u == "nameplate3" and 8 or nil end
C_Spell.GetSpellTexture = function(id) return 1000 + id end
C_ClassColor.GetClassColor = function(cls)
    local c = { WARRIOR = { 0.78, 0.61, 0.43 }, MAGE = { 0.25, 0.78, 0.92 }, SHAMAN = { 0, 0.44, 0.87 } }
    local t = c[cls]
    return t and { GetRGB = function() return t[1], t[2], t[3] end }
end

ns.KTB_OnEnable(db)
-- The bars' container: the UIParent child whose children are rows (sb + dur).
local container
for _, c in ipairs(UIParent.__children) do
    for _, r in ipairs(rawget(c, "__children") or {}) do
        if rawget(r, "sb") and rawget(r, "dur") then container = c end
    end
end
if not container then P("== no container") return end
local function Snap(label) SNAP(label, container) end

Snap("kick live")
P("== subscribed", tostring(handlers ~= nil))
local now = GetTime()
cds.party1 = { now, 24 }
handlers.cooldown("party1", now, 24)
handlers.kick("nameplate3", "party1")
Snap("kick party1 on cooldown")
HARNESS_ADVANCE(0.35)
Snap("kick ticked")
-- An unnamed kick: a gate packet for two members.
handlers.gate(GetTime(), { "player", "party2" }, { player = 1, party2 = 2 }, { player = 1, party2 = 3 }, { "nameplate3" })
Snap("kick gate layers")
handlers.gate(GetTime(), {}, {}, {}, { "nameplate3" }, true)
-- A sure kick of party2 supersedes its layer.
cds.party2 = { GetTime(), 12 }
handlers.cooldown("party2", GetTime(), 12)
Snap("kick party2 sure kick")
-- A roster change: party1 leaves, party2 becomes party1.
members.party1, members.party2 = members.party2, nil
cds.party1, cds.party2 = cds.party2, nil
handlers.roster()
Snap("kick roster closed up")
HARNESS_ADVANCE(30)
Snap("kick all ready")

-- Style settings.
local function Set(label, k, v)
    cfg[k] = v
    ns.KTB_Refresh()
    Snap("kick " .. label)
end
Set("icon right", "barIconOnRight", true)
Set("no icon", "barShowIcon", false)
cfg.barShowIcon, cfg.barIconOnRight = nil, nil
Set("border", "barBorderSize", 2)
Set("grow up", "barGrowUp", true)
cfg.barBgMode, cfg.barBgColor = "custom", { r = 0.1, g = 0.2, b = 0.3, a = 0.6 }
Set("custom bg", "barShowTimer", false)
Set("no marker", "barShowMarker", false)
Set("no self", "barIncludeSelf", false)
Set("size", "barWidth", 260)

ns.KTB_SetPreview(true)
Snap("kick preview")
P("== preview", tostring(ns.KTB_IsPreview()))
ns.KTB_SetPreview(false)
Snap("kick preview off")

local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(300, 100)
local w, h = ns.KTB_PaintSample(host)
P("== sample size", tostring(w), tostring(h))
SNAP("kick sample", host)
ns.KTB_PaintSample(host, 4)
SNAP("kick sample 4", host)

cfg.enabled = false
ns.KTB_Refresh()
Snap("kick off")
P("== subscribed after off", tostring(handlers ~= nil))
