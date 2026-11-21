if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  AuraSounds.lua -- Raid Lead: Aura Sounds.
--
--  Plays a sound when an aura you choose is applied to you, gains a stack,
--  or falls off. The game plays the sound itself (C_UnitAuras.AddAuraSound),
--  so it works in boss fights and keys, where addons cannot read auras.
--
--  The game refuses new registrations while auras are secret, so a change
--  made in combat is applied as soon as combat ends.
--
--  Settings live in the active CludesUI profile:
--    sounds = { { id = spellID, when = "added"|"stacks"|"removed",
--                 sound = file name in CludesUI/media/sounds, on = true }, ... }
-------------------------------------------------------------------------------
local _, mod = ...

local SOUND_DIR = "Interface\\AddOns\\CludesUI\\media\\sounds\\"
mod.SOUND_FILES = {
    "AirHorn.ogg",
    "BikeHorn.ogg",
    "Bite.ogg",
    "Glass.mp3",
    "Kaching.ogg",
    "Phone.ogg",
    "RobotBlip.ogg",
    "Sonar.ogg",
    "WarningSiren.ogg",
    "WaterDrop.ogg",
    "Wilhelm.ogg",
}
mod.SOUND_WHEN = {
    { id = "added", label = "Applied" },
    { id = "stacks", label = "Gains a Stack" },
    { id = "removed", label = "Removed" },
}

local saved
function mod.RaidLeadDB()
    if not saved then saved = CUI.Lite.NewDB("CludesUIRaidLeadDB", { profile = { sounds = {} } }) end
    saved.profile.sounds = saved.profile.sounds or {}
    return saved.profile
end

local handles = {} -- ids the game gave back, to remove them again
local pending = false -- a rebuild is owed for after combat

local function Secret() return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() end

local function Trigger(when)
    local T = Enum and Enum.UnitAuraSoundTrigger
    if not T then return nil end
    if when == "stacks" then return T.ApplicationsIncreased end
    if when == "removed" then return T.Removed end
    return T.Added
end

local function Clear()
    for idx = #handles, 1, -1 do
        pcall(C_UnitAuras.RemoveAuraSound, handles[idx])
        handles[idx] = nil
    end
end

--- Registers every enabled aura sound with the game. Returns how many took.
function mod.RebuildAuraSounds()
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound) then return 0 end
    if Secret() or InCombatLockdown() then
        pending = true
        return 0
    end
    pending = false
    Clear()
    local num = 0
    for _, entry in ipairs(mod.RaidLeadDB().sounds) do
        local trigger = Trigger(entry.when)
        if entry.on ~= false and tonumber(entry.id) and trigger then
            local success, hgt = pcall(C_UnitAuras.AddAuraSound, trigger, {
                unitToken = "player",
                spellID = tonumber(entry.id),
                soundFileName = SOUND_DIR .. (entry.sound or "WarningSiren.ogg"),
                outputChannel = "Master",
                throttleSeconds = 1,
            })
            if success and hgt then
                handles[#handles + 1] = hgt
                num = num + 1
            end
        end
    end
    return num
end

--- Plays one sound file, for the settings page's preview.
function mod.PreviewSound(file) PlaySoundFile(SOUND_DIR .. (file or "WarningSiren.ogg"), "Master") end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" or pending then C_Timer.After(1, mod.RebuildAuraSounds) end
end)
