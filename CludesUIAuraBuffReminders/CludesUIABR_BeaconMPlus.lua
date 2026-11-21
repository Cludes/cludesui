if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not CUI or CUI.IS_FOREVER then return end
-------------------------------------------------------------------------------
--  CludesUIABR_BeaconMPlus.lua
--  Beacon M+ Reminders (retail, Holy Paladin; CORE > Beacon M+ Reminders, off
--  by default): during a Mythic+ boss encounter, a glowing red Beacon icon on
--  the tank's Raid Frames frame while the tank carries the player's Beacon of
--  Light or Beacon of Faith.
--
--  Auras are secret in M+, so Lua never reads them: one engine aura container
--  on the tank's unit draws the icon only while that aura is up (HELPFUL|PLAYER
--  plus the two spell IDs), and its button carries the glow. The container is
--  shown only between ENCOUNTER_START and ENCOUNTER_END inside a key, so it
--  listens to nothing outside boss fights. Raid frames do not move once a key
--  has started, so the host is placed once per encounter and never follows.
--  Other classes stop here at load; a paladin with the option off, or on
--  another spec, registers no gameplay events, and an armed one follows the
--  roster only while a key runs.
-------------------------------------------------------------------------------
if select(2, UnitClass("player")) ~= "PALADIN" then return end

local BEACON_IDS = { [53563] = true, [156910] = true } -- Beacon of Light, Beacon of Faith
local PARTY = { "party1", "party2", "party3", "party4" }
local HOLY_SPEC = 65
local ICON_SIZE = 30
local STYLE_KEY = "abrBeaconMPlus"
local GLOW_SPEC = { style = 2, r = 1, g = 0.15, b = 0.15 } -- Action Button Glow, red
local GLOW_NEED = { flip = true } -- the family Action Button Glow draws on an engine host

local eventFrame = CreateFrame("Frame")
local started = false -- the first PLAYER_ENTERING_WORLD ran the initial sync
local level = -1 -- 0 off, 1 option on but not Holy, 2 armed (Holy)
local tankUnit -- cached out of the encounter; roles can read secret in M+
local owner, boxHolder, containerUnit

local function Enabled()
    local saved = _G._CUABR_AceDB
    local skinData = saved and saved.profile and saved.profile.display
    return skinData and skinData.beaconMPlus == true
end

local function IsHoly()
    local specInfo = C_SpecializationInfo.GetSpecialization()
    return specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo) == HOLY_SPEC
end

local function FindTank()
    for index = 1, 4 do
        local u = PARTY[index]
        if UnitExists(u) then
            local role = UnitGroupRolesAssigned(u)
            if issecretvalue and issecretvalue(role) then return end -- keep the cached tank
            if role == "TANK" then
                tankUnit = u
                return
            end
        end
    end
    tankUnit = nil
end

local function FindIn(entries, unitToken)
    if not entries then return end
    for index = 1, #entries do
        local widget = entries[index]
        if widget and widget:IsVisible() and widget:GetAttribute("unit") == unitToken then return widget end
    end
end

-- The tank's Raid Frames button: the party frames, or the raid frames when the
-- party is shown on them.
local function TankButton(unitToken)
    local rf = CUI._ModuleNS["CludesUIRaidFrames"]
    if not rf then return end
    return FindIn(rf._partyAllButtons, unitToken) or FindIn(rf._allButtons, unitToken)
end

-- Built once per engine button, the only window where the button may be
-- decorated: the aura icon, no mouse (the tank's frame keeps its clicks and
-- mouseover casts), and the red glow on a child host, whose C-side animation
-- runs the same in and out of restricted content.
local function InitButton(btnFrame, skinData)
    local iconTex = btnFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(btnFrame)
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btnFrame:SetIcon(iconTex)
    pcall(btnFrame.EnableMouse, btnFrame, false)
    local glow = CreateFrame("Frame", nil, btnFrame)
    glow:SetAllPoints(btnFrame)
    glow:SetFrameLevel(btnFrame:GetFrameLevel() + 2)
    glow:EnableMouse(false)
    local Glows = CUI.Glows
    -- The button runs the animation itself (12.1.5): Blizzard plays it while
    -- the button shows the Beacon and stops it otherwise, so every button
    -- carries the glow; the icon above is its own (the button re-registers it
    -- to re-run its visibility). Without that API the animation plays while
    -- hidden too, and the group's cap is a fixed 1: only the one button it
    -- can ever show carries the glow.
    if
        not Glows.BindEngineHost(glow, btnFrame, skinData, iconTex)
        and not CUI.AuraKit.ButtonCanShow(btnFrame)
    then
        return
    end
    Glows.PrewarmEngineHost(glow, ICON_SIZE, ICON_SIZE, GLOW_NEED)
    skinData.abrBeaconGlow = glow
    Glows.StartSpecGlow(glow, GLOW_SPEC, ICON_SIZE, ICON_SIZE, "engine")
end

-- The style's restyle runs only when AuraKit deferred it to the restriction
-- lift, after the button refused the glow's registration: it starts the glow
-- again (an unchanged one returns at once).
local function RetryGlow(btnFrame, skinData)
    local glow = skinData.abrBeaconGlow
    if glow then CUI.Glows.StartSpecGlow(glow, GLOW_SPEC, ICON_SIZE, ICON_SIZE, "engine") end
end

local function EnsureContainer(unitToken)
    if boxHolder then
        if containerUnit ~= unitToken then
            boxHolder:SetUnit(unitToken)
            containerUnit = unitToken
        end
        return
    end
    local AK = CUI.AuraKit
    AK.styles[STYLE_KEY] = AK.styles[STYLE_KEY]
        or { noRegions = true, width = ICON_SIZE, height = ICON_SIZE, applyExtra = RetryGlow }
    owner = CreateFrame("Frame", nil, UIParent)
    owner:SetSize(ICON_SIZE, ICON_SIZE)
    owner:SetFrameStrata("HIGH")
    owner:Hide()
    boxHolder = AK.CreateContainer(owner, unitToken, {
        point = { "CENTER", owner, "CENTER" },
        layout = { anchorPoint = "CENTER" },
        groups = {
            {
                key = "beacon",
                filter = { "HELPFUL", "PLAYER" },
                maxFrameCount = 1,
                candidateFilters = { includeSpellIDs = BEACON_IDS },
                style = STYLE_KEY,
                extraInit = InitButton,
            },
        },
    })
    containerUnit = unitToken
end

-- Engine aura hosts stay UIParent-anchored (an engine subtree must never join
-- another frame's anchor family), so the host takes the button's centre as a
-- number.
local function PlaceOver(btnFrame)
    local posX, posY = btnFrame:GetCenter()
    if not posX or (issecretvalue and (issecretvalue(posX) or issecretvalue(posY))) then return false end
    local s = btnFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    owner:ClearAllPoints()
    owner:SetPoint("CENTER", UIParent, "BOTTOMLEFT", posX * s, posY * s)
    return true
end

local function StandDown()
    if owner then owner:Hide() end
end

-- The tank is read only inside a key, so the roster events are registered from
-- CHALLENGE_MODE_START (or arming, or a PLAYER_ENTERING_WORLD, inside a key) to
-- the key's end; each of those starts looks the tank up again.
local function WatchRoster(enabled)
    if enabled then
        eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    else
        eventFrame:UnregisterEvent("GROUP_ROSTER_UPDATE")
        eventFrame:UnregisterEvent("PLAYER_ROLES_ASSIGNED")
    end
end

-- Built while the key's countdown runs (out of combat), so the first pull does
-- no engine construction; Arm still builds it if a key began before the option.
local function Prebuild()
    if level == 2 and tankUnit and C_ChallengeMode.IsChallengeModeActive() then EnsureContainer(tankUnit) end
end

local function Arm()
    if level ~= 2 or not C_ChallengeMode.IsChallengeModeActive() then return end
    local unitToken = tankUnit
    local btnFrame = unitToken and TankButton(unitToken)
    if not btnFrame then return end
    EnsureContainer(unitToken)
    if PlaceOver(btnFrame) then owner:Show() end
end

local function Sync()
    local wanted = 0
    if Enabled() then wanted = IsHoly() and 2 or 1 end
    if wanted == level then return end
    level = wanted
    eventFrame:UnregisterAllEvents()
    StandDown()
    if wanted == 0 then return end
    eventFrame:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
    if wanted == 2 then
        eventFrame:RegisterEvent("ENCOUNTER_START")
        eventFrame:RegisterEvent("ENCOUNTER_END")
        eventFrame:RegisterEvent("CHALLENGE_MODE_START")
        eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        eventFrame:RegisterEvent("CHALLENGE_MODE_RESET")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        WatchRoster(C_ChallengeMode.IsChallengeModeActive())
        FindTank()
        if IsEncounterInProgress() then
            Arm()
        else
            Prebuild()
        end
    end
end

eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "ENCOUNTER_START" then
        Arm()
    elseif evt == "CHALLENGE_MODE_START" then
        WatchRoster(true)
        FindTank()
        Prebuild()
    elseif evt == "ENCOUNTER_END" then
        StandDown()
    elseif evt == "CHALLENGE_MODE_COMPLETED" or evt == "CHALLENGE_MODE_RESET" then
        WatchRoster(false)
        StandDown()
    elseif evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_ROLES_ASSIGNED" then
        FindTank()
    elseif evt == "PLAYER_ENTERING_WORLD" then
        if not started then
            -- After every module's OnEnable, so ABR's DB and refresh exist. The
            -- options page and profile switches both go through that refresh.
            started = true
            if _G._CUABR_RequestRefresh then hooksecurefunc("_CUABR_RequestRefresh", Sync) end
            Sync()
            return
        end
        StandDown()
        WatchRoster(C_ChallengeMode.IsChallengeModeActive())
        FindTank()
        if IsEncounterInProgress() then
            Arm()
        else
            Prebuild()
        end
    else -- PLAYER_SPECIALIZATION_CHANGED
        Sync()
    end
end)
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
