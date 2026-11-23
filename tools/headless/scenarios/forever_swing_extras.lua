-- Swing timer extras (CUI_ResourceBars_SwingTimer.lua, WoW Forever): paladin
-- Seal Colors (aura added / removed, a cast while auras are secret, the run-out
-- timer, the toggle), the Swing Window zone (length, latency, melee rows only)
-- and the Cast Clip tick (in time, delaying the swing, cleared on stop).
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIResourceBars
OUT:write("== st " .. tostring(mod and mod.ST_Apply ~= nil) .. "\n")
if not (mod and mod.ST_Apply) then return end

local NAMES = {
    [20154] = "Seal of Righteousness",
    [20375] = "Seal of Command",
    [78] = "Heroic Strike",
}
C_Spell.GetSpellName = function(id) return NAMES[id] end
C_Spell.IsCurrentSpell = function() return false end
UnitAttackSpeed = function() return 2.0, nil, nil end
local secret = false
C_Secrets = { ShouldAurasBeSecret = function() return secret end }
local buffs = {}
C_UnitAuras.GetAuraDataByIndex = function(_, i) return buffs[i] end
C_UnitAuras.GetAuraDataByAuraInstanceID = function(_, inst)
    for _, a in ipairs(buffs) do if a.auraInstanceID == inst then return a end end
end
local cast = nil
UnitCastingInfo = function()
    if not cast then return nil end
    return "Holy Light", "Holy Light", 0, cast[1] * 1000, cast[2] * 1000
end
UnitChannelInfo = function() return nil end
GetNetStats = function() return 0, 0, 100, 100 end
-- The fake client's text binding has no UpdateFontString: a no-op stand-in.
C_DurationUtil.CreateDurationTextBinding = function()
    return setmetatable({}, { __index = function() return function() end end })
end
local function Wait(secs) for _ = 1, secs do HARNESS_ADVANCE(1) end end

local conf = mod.ERB.db.profile.swingTimer
conf.enabled = true
conf.visibility = "always"
mod.ST_Apply()

local shell = _G.ERB_SwingTimerFrame
local mh, oh
for _, c in ipairs({ shell:GetChildren() }) do
    if c._def and c._def.tag == "MH" then mh = c end
    if c._def and c._def.tag == "OH" then oh = c end
end
OUT:write("== rows mh " .. tostring(mh ~= nil) .. " oh " .. tostring(oh ~= nil) .. "\n")

local function F(n) return n and ("%.2f"):format(n) or "nil" end
local function Fill(tag)
    local r, g, b = mh._bar:GetStatusBarTexture():GetVertexColor()
    OUT:write(("== %s: fill %s %s %s\n"):format(tag, F(r), F(g), F(b)))
end
local function Win(tag)
    local z = mh._zones and mh._zones.win
    local t = z and (z.front:IsShown() and z.front or z.back:IsShown() and z.back)
    OUT:write(("== %s: window %s w=%s\n"):format(tag, t and "on" or "off", t and F(t:GetWidth()) or "-"))
end
local function Tick(tag)
    local t = mh._tick
    local shown = t and t:IsShown()
    local x = shown and select(4, t:GetPoint(1))
    local c = shown and t["\0v"].ColorTexture
    OUT:write(("== %s: tick %s x=%s color=%s\n"):format(tag, shown and "on" or "off", F(x),
        c and (F(c[1]) .. " " .. F(c[2]) .. " " .. F(c[3])) or "-"))
end
local function Swing() HARNESS_FIRE_EVENT("PLAYER_SWING", 2.0, Enum.PlayerSwingType.MainHand) end

Swing()
Fill("swing, no seal")
Win("window off by default")
Tick("cast clip off by default")

-- Seal of Command added, then removed.
buffs[1] = { name = "Seal of Command", auraInstanceID = 7, duration = 30, expirationTime = GetTime() + 30 }
HARNESS_FIRE_EVENT("UNIT_AURA", "player", { addedAuras = { buffs[1] } })
Fill("Seal of Command up")
buffs[1] = nil
HARNESS_FIRE_EVENT("UNIT_AURA", "player", { removedAuraInstanceIDs = { 7 } })
Fill("Seal of Command removed")

-- A cast while auras are secret: shown from the cast, gone after its length.
secret = true
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_SUCCEEDED", "player", "guid", 20154)
Fill("Righteousness cast (auras secret)")
HARNESS_FIRE_EVENT("UNIT_AURA", "player", { removedAuraInstanceIDs = { 99 } })
Fill("secret aura update ignored")
Wait(29)
Fill("29s later")
Wait(2)
Fill("31s later: ran out")
secret = false

-- A seal already up when the timer turns on (full scan); then the toggle off.
buffs[1] = { name = "Seal of Righteousness", auraInstanceID = 8, duration = 30, expirationTime = GetTime() + 30 }
mod.ST_Apply()
Swing()
Fill("seal up at apply")
conf.sealColors = false
mod.ST_Apply()
Fill("Seal Colors off")
conf.sealColors = nil
buffs[1] = nil
mod.ST_Apply()

-- Swing Window: default 0.4s of a 2s swing; plus latency.
local wid = mh._clip:GetWidth()
OUT:write("== clip width " .. F(wid) .. "\n")
conf.swingWindow = true
mod.ST_Apply()
Swing()
Win("window 0.4s")
conf.windowLatency = true
mod.ST_Apply()
Swing()
Win("window 0.4s + 0.1s latency")
conf.swingWindowTime, conf.windowLatency = 1.0, nil
mod.ST_Apply()
Swing()
Win("window 1.0s")
conf.swingWindow, conf.swingWindowTime = nil, nil
mod.ST_Apply()
Swing()
Win("window off")

-- Cast Clip: a cast ending halfway through the swing, then past its end.
conf.castClip = true
mod.ST_Apply()
Swing()
Tick("on, no cast")
cast = { GetTime(), GetTime() + 1.0 }
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_START", "player")
Tick("cast ends at 1.0s of 2.0s")
cast = { GetTime(), GetTime() + 3.0 }
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_DELAYED", "player")
Tick("cast ends past the swing")
cast = nil
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_STOP", "player")
Tick("cast stopped")
conf.depleteFill = false
mod.ST_Apply()
Swing()
cast = { GetTime(), GetTime() + 0.5 }
HARNESS_FIRE_EVENT("UNIT_SPELLCAST_START", "player")
Tick("filling bar, cast ends at 0.5s")
Wait(3)
Tick("swing over")
conf.castClip, conf.depleteFill = nil, nil
cast = nil
mod.ST_Apply()

-- Target Swing: off by default; ticked, it shows for a hostile living target,
-- starts on the target's physical hit on the player, parries haste it, a
-- spell or another unit's target does nothing, a new target resets it.
local tgt
for _, c in ipairs({ shell:GetChildren() }) do
    if c._def and c._def.tag == "TGT" then tgt = c end
end
local hostile, dead, onMe = true, false, true
UnitCanAttack = function() return hostile end
UnitIsDead = function() return dead end
UnitIsUnit = function() return onMe end
UnitAttackSpeed = function(unit) if unit == "target" then return 2.5 end return 2.0, nil, nil end
local function Tgt(tag)
    OUT:write(("== %s: tgt shown=%s live=%s end=%s height=%s\n"):format(tag, tostring(tgt:IsShown()),
        tostring(tgt._live or false), tgt._end and F(tgt._end - GetTime()) or "-", F(shell:GetHeight())))
end
Tgt("off by default")
conf.showTGT = true
mod.ST_Apply()
Tgt("ticked, hostile target")
HARNESS_FIRE_EVENT("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
Tgt("target hits me")
HARNESS_FIRE_EVENT("UNIT_COMBAT", "player", "WOUND", "", 120, 4)
Tgt("a fire spell (no restart)")
HARNESS_ADVANCE(0.5)
HARNESS_FIRE_EVENT("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
Tgt("0.5s later the target parries (2.0 left -> 1.0)")
HARNESS_FIRE_EVENT("UNIT_COMBAT", "target", "PARRY", "", 0, 1)
Tgt("parries again (1.0 left -> 0.5)")
onMe = false
HARNESS_FIRE_EVENT("UNIT_COMBAT", "player", "WOUND", "", 120, 1)
Tgt("hit while it targets someone else (no restart)")
onMe = true
HARNESS_FIRE_EVENT("PLAYER_TARGET_CHANGED")
Tgt("new target")
hostile = false
HARNESS_FIRE_EVENT("UNIT_FLAGS", "target")
Tgt("target turns friendly")
hostile = true
HARNESS_FIRE_EVENT("UNIT_FACTION", "target")
Tgt("hostile again")
dead = true
HARNESS_FIRE_EVENT("PLAYER_TARGET_CHANGED")
Tgt("dead target")
dead = false
conf.showTGT = false
mod.ST_Apply()
Tgt("unticked")

SNAP("swing timer", shell)
