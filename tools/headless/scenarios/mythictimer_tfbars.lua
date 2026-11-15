-- Mythic+ Tools > Target / Focus cast bars: a target cast (icon, name, the
-- spell's target in class colour, timer, kick tick and mid-cast window), a
-- delay, an interrupt (the flash, then it clears), a focus channel, an
-- uninterruptible flip, target changed, stop, style settings, the unlock
-- preview, the options sample, and off.
local CUI = rawget(_G, "CludesUI")
local ns = CUI._ModuleNS.CludesUIMythicTimer
local function P(...) OUT:write(table.concat({ ... }, " "), "\n") end
if not ns.TFB_OnEnable then P("== no target/focus bars") return end

local tf = {
    target = { enabled = true },
    focus = { enabled = true },
    midCastEnabled = true,
    importantEnabled = true,
}
local db = { profile = { tfb = tf } }

local function Duration(total, elapsed)
    return {
        GetTotalDuration = function() return total end,
        GetElapsedDuration = function() return elapsed end,
        GetRemainingDuration = function() return total - elapsed end,
        IsZero = function() return total - elapsed <= 0 end,
    }
end
local casting = {} -- unit -> { name, texture, protected, spellID, channel, elapsed }
UnitExists = function(u) return u == "target" or u == "focus" end
UnitCastingInfo = function(u)
    local c = casting[u]
    if c and not c.channel then return c[1], nil, c[2], nil, nil, nil, nil, c[3], c[4] end
end
UnitChannelInfo = function(u)
    local c = casting[u]
    if c and c.channel then return c[1], nil, c[2], nil, nil, nil, c[3], c[4] end
end
UnitCastingDuration = function(u) local c = casting[u] if c and not c.channel then return Duration(2.5, c.elapsed or 0.5) end end
UnitChannelDuration = function(u) local c = casting[u] if c and c.channel then return Duration(4, c.elapsed or 1) end end
UnitEmpoweredChannelDuration = function() return nil end
UnitShouldDisplaySpellTargetName = function() return true end
UnitSpellTargetName = function(u) return u == "target" and "Tanky" or nil end
UnitSpellTargetClass = function() return "WARRIOR" end
C_ClassColor.GetClassColor = function() return { GetRGB = function() return 0.78, 0.61, 0.43 end } end
local kickCd = Duration(15, 15)
C_Spell.GetSpellCooldownDuration = function() return kickCd end
C_Spell.IsSpellImportant = function(id) return id == 999 end
C_Spell.GetSpellInfo = function() return { iconID = 4242 } end
-- A known kick, so the kick tick and the mid-cast window draw.
C_SpellBook.IsSpellKnownOrInSpellBook = function(_, bank) return bank == nil end
C_CurveUtil = C_CurveUtil or {}
C_CurveUtil.EvaluateColorValueFromBoolean = function(b, t, f) if b then return t end return f end
CUI.RefreshKickAbility()
P("== kick spell", tostring(CUI.GetActiveKickSpell()))

ns.TFB_OnEnable(db)
-- The bars: UIParent children holding a status bar with the cast spark.
local bars = {}
for _, c in ipairs(UIParent.__children) do
    local found = false
    for _, sb in ipairs(rawget(c, "__children") or {}) do
        for _, r in ipairs(rawget(sb, "__regions") or {}) do
            local tex = r.__v and r.__v.Texture
            if type(tex) == "string" and tex:find("cast_spark", 1, true) then found = true end
        end
    end
    if found then bars[#bars + 1] = c end
end
P("== bars found", #bars)
local function Snap(label)
    for i, f in ipairs(bars) do SNAP(label .. " " .. i, f) end
end

Snap("tf idle")
casting.target = { "Shadow Bolt", 136197, false, 999 }
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_START", "target")
Snap("tf target casting")
HARNESS_ADVANCE(0.35)
Snap("tf target ticked")
casting.target.elapsed = 1
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_DELAYED", "target")
HARNESS_FIRE_EVENT("SPELL_UPDATE_COOLDOWN")
Snap("tf target delayed")
casting.target = nil
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_INTERRUPTED", "target", "cast-guid", 999, "Player-1-00000001")
Snap("tf target interrupted")
HARNESS_ADVANCE(1.2)
Snap("tf flash over")
casting.focus = { "Mind Flay", nil, false, 15407, channel = true }
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_CHANNEL_START", "focus")
Snap("tf focus channel")
casting.focus[3] = true
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "focus")
Snap("tf focus protected")
casting.focus = nil
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_CHANNEL_STOP", "focus", "guid", 15407, nil)
Snap("tf focus stopped")
casting.target = { "Frostbolt", 135846, false, 116 }
HARNESS_FIRE_EVENT("PLAYER_TARGET_CHANGED")
Snap("tf target changed")
casting.target = nil
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_STOP", "target")
Snap("tf stopped")

-- Style settings on a fresh cast.
casting.target = { "Shadow Bolt", 136197, false, 1 }
local function Set(label, apply)
    apply()
    ns.TFB_Refresh()
    HARNESS_FIRE_EVENT("UNIT_SPELLCAST_START", "target")
    Snap("tf " .. label)
end
Set("no icon", function() tf.target.showIcon = false end)
Set("no timer", function() tf.target.showIcon = nil tf.target.showTimer = false end)
Set("size", function() tf.target.showTimer = nil tf.target.width, tf.target.height = 300, 26 end)
Set("no target text", function() tf.target.showTarget = false end)
Set("colours", function()
    tf.target.showTarget = nil
    tf.castColor = { r = 0.1, g = 0.5, b = 0.9 }
    tf.targetClassColor = false
    tf.targetColor = { r = 1, g = 1, b = 0 }
    tf.showSpark = false
end)
casting.target = nil
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_STOP", "target")

ns.TFB_SetPreview("target", true)
Snap("tf preview")
P("== preview", tostring(ns.TFB_IsPreview("target")))
ns.TFB_SetPreview("target", false)
Snap("tf preview off")

local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(320, 40)
P("== sample", tostring(ns.TFB_PaintSample(host, "focus")))
SNAP("tf sample", host)

tf.target.enabled, tf.focus.enabled = false, false
ns.TFB_Refresh()
Snap("tf off")
