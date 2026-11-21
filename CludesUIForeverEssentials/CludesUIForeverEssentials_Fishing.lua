if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_Fishing.lua  (WoW Forever only)
--  Fishing helpers, each its own setting (all off by default):
--  Fishing Key      one key casts; it first equips a pole when none is in
--                   hand and applies a lure (cog). With Reel In (cog), once
--                   soft interact targets the bobber the key reels in; the
--                   Bobber Indicator (cog) shows whether it does.
--  Double-Click     a pole in hand: a quick second right-click on the world
--                   casts (its own Apply Lure in its cog).
--  Fishing Sounds   music and ambience down, effects up, for the session.
--
--  Every action is a real key press or click on a secure button, bound out
--  of combat only. A session starts with a cast and ends on moving, combat
--  or a load; the CVars it changes go through CludesUI.HoldCVar, their
--  values from before saved and put back at the next login after a reload.
-------------------------------------------------------------------------------
local _, module = ...
local BUTTON_NAME = "CludesUIFishingCastButton"

-- Settings live in CludesUIDB.fishing; unset keys read these. key: the
-- Fishing Key (nil: none); held: [set] = { [cvar] = the value before };
-- pos: where Unlock Mode put the Bobber Indicator.
local F = module.Feature("fishing", {
    reel = true,
    indicator = true,
    lure = true,
    doubleClick = false,
    clickLure = false,
    sound = false,
}, { point = "CENTER", relPoint = "CENTER", x = 0, y = -180 })

-- The Fishing ranks, highest first.
local FISHING_SPELLS = { 18248, 7732, 7731, 7620 }

-- Lures, best first (item ID): Aquadynamic Fish Attractor, Bright Baubles,
-- Flesh Eating Worm, Nightcrawlers, Aquadynamic Fish Lens, Shiny Bauble.
local LURES = { 6533, 6532, 7307, 6530, 6811, 6529 }

-- The bobber (game object ID).
local BOBBER = 35591

local DOUBLE_CLICK_DELAY = 0.4 -- seconds at most between the two right-clicks
local DISARM_DELAY = 1 -- no release by then: the right-click goes back to the game

-- CVars held for the session: name = its value then, from the value before.
-- Soft interact on, wide and far enough to target the bobber by itself.
local REEL_CVARS = {
    SoftTargetInteract = function() return 3 end,
    SoftTargetInteractRange = function() return 30 end,
    SoftTargetInteractArc = function() return 2 end,
    SoftTargetInteractRangeIsHard = function() return 0 end,
}
-- The splash of the bobber over the music.
local SOUND_CVARS = {
    Sound_MusicVolume = function(before) return before * 0.3 end,
    Sound_AmbienceVolume = function(before) return before * 0.3 end,
    Sound_SFXVolume = function(before) return math.max(before, 0.8) end,
    Sound_EnableSoundWhenGameIsInBG = function() return 1 end,
}

local function KeyOn() return F.Get("key") ~= nil end
local function ReelOn() return KeyOn() and F.Get("reel") end
local function IndicatorOn() return ReelOn() and F.Get("indicator") end
local function AnyOn() return KeyOn() or F.Get("doubleClick") or F.Get("sound") end

local eventFrame = CreateFrame("Frame")
local clickOwner = CreateFrame("Frame") -- holds the double-click's binding
local castButton, indicator
local fishingID, fishingName -- the Fishing rank known (nil: none)
local inSession = false
local lineOut = false -- the Fishing channel runs
local reeling = false -- the key is bound to Interact With Target
local clickArmed = false -- the right-click is bound to the button
local lastRightClick = 0
local armedAt = 0 -- when the right-click was bound to the button
local worldHooked = false

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function ResolveFishing()
    fishingID, fishingName = nil, nil
    for index = 1, #FISHING_SPELLS do
        local ident = FISHING_SPELLS[index]
        if IsPlayerSpell(ident) then
            fishingID, fishingName = ident, C_Spell.GetSpellName(ident)
            return
        end
    end
end

local function IsPole(ident)
    local _, _, _, _, _, classID, subClassID = C_Item.GetItemInfoInstant(ident)
    return classID == Enum.ItemClass.Weapon and subClassID == Enum.ItemWeaponSubclass.Fishingpole
end

-- WoW Forever fishes with the pole in the main hand.
local function PoleInHand()
    local ident = GetInventoryItemID("player", INVSLOT_MAINHAND)
    return ident ~= nil and IsPole(ident)
end

-- The best fishing pole in the bags (highest item level), or nil.
local function PoleInBags()
    local best, bestLevel
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local ident = C_Container.GetContainerItemID(bag, slot)
            if ident and IsPole(ident) then
                local level = select(4, C_Item.GetItemInfo(ident)) or 0
                if not best or level > bestLevel then
                    best, bestLevel = ident, level
                end
            end
        end
    end
    return best
end

local function BestLure()
    for index = 1, #LURES do
        if C_Item.GetItemCount(LURES[index]) > 0 then return LURES[index] end
    end
end

-- The game object ID in a "GameObject-0-...-35591-..." GUID, or nil.
local function ObjectID(unitGuid)
    if not unitGuid or issecretvalue(unitGuid) then return nil end
    -- Only the object's ID field is read: the server and spawn fields before
    -- and after it may be obfuscated.
    return tonumber(unitGuid:match("^GameObject%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)%-"))
end

-------------------------------------------------------------------------------
--  Held CVars
-------------------------------------------------------------------------------
local function CVarText(val) return val % 1 == 0 and tostring(val) or ("%.2f"):format(val) end

local function Hold(set, cvars)
    local conf = F.Cfg()
    conf.held = conf.held or {}
    if conf.held[set] then return end
    local was = {}
    for name, value in pairs(cvars) do
        local current = C_CVar.GetCVar(name)
        local wanted = current and CVarText(value(tonumber(current) or 0))
        if
            current ~= nil
            and current ~= wanted
            and CUI.HoldCVar(name, wanted, "CludesUIForeverEssentials")
        then
            was[name] = current
        end
    end
    conf.held[set] = was
end

local function Release(set)
    local held = F.Read().held
    local was = held and held[set]
    if not was then return end
    for name, value in pairs(was) do
        CUI.ReleaseCVar(name, value, "CludesUIForeverEssentials")
    end
    held[set] = nil
end

-------------------------------------------------------------------------------
--  Bobber Indicator: while the line is in the water, an icon with a green
--  border when the key reels in, red when the bobber is not targeted; the key
--  sits on it and the full sentence is its tooltip. Placed in Unlock Mode.
-------------------------------------------------------------------------------
local INDICATOR_SIZE = 40
local ICON = "Interface\\Icons\\Trade_Fishing" -- the Fishing profession

local function IndicatorTip()
    if reeling then return CUI.Lf("Bobber found: %s reels in", GetBindingText(F.Get("key"))) end
    return CUI.L("Bobber not found: keep it on screen, cast again, or right-click it to reel in.")
end

local function BuildIndicator()
    if indicator then return end
    local Pix = CUI.PP
    indicator = CreateFrame("Frame", nil, UIParent)
    indicator:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    indicator:SetFrameStrata("HIGH")
    -- Hover for the sentence; clicks go through to the world.
    indicator:SetMouseMotionEnabled(true)
    indicator:SetMouseClickEnabled(false)
    indicator:Hide()
    local iconTex = indicator:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexture(ICON)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    indicator.icon = iconTex
    Pix.CreateBorder(indicator, 1, 0.2, 0.2, 1, 2, "OVERLAY", 2)
    -- The key, clipped to the icon's width.
    local key = indicator:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    key:SetPoint("BOTTOM", 0, 3)
    key:SetWidth(INDICATOR_SIZE - 4)
    key:SetWordWrap(false)
    indicator.key = key
    indicator:SetScript("OnEnter", function(self) CUI.ShowWidgetTooltip(self, IndicatorTip()) end)
    indicator:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
    F.Place(indicator)
end

local function UpdateIndicator()
    if not (lineOut and IndicatorOn()) then
        if indicator then indicator:Hide() end
        return
    end
    BuildIndicator()
    local red, green, blue = 1, 0.2, 0.2
    if reeling then
        red, green, blue = 0.2, 1, 0.3
    end
    CUI.PP.SetBorderColor(indicator, red, green, blue, 1)
    indicator.icon:SetDesaturated(not reeling)
    indicator.key:SetText(GetBindingText(F.Get("key"), true))
    indicator:Show()
    if indicator:IsMouseOver() then CUI.ShowWidgetTooltip(indicator, IndicatorTip()) end
end

-------------------------------------------------------------------------------
--  The key and the double-click
-------------------------------------------------------------------------------
-- What the next press does (viaClick: the double-click's, which has its own
-- Apply Lure). Out of combat only.
local function UpdateCastButton(viaClick)
    if not castButton then return end
    if InCombatLockdown() then
        CUI.CombatQueue.Defer("FishingButton", UpdateCastButton)
        return
    end
    if not PoleInHand() then
        local pole = PoleInBags()
        if pole then
            castButton:SetAttribute("type", "item")
            castButton:SetAttribute("item", "item:" .. pole)
            return
        end
    elseif F.Get(viaClick and "clickLure" or "lure") and not GetWeaponEnchantInfo() then
        local lure = BestLure()
        if lure then
            castButton:SetAttribute("type", "macro")
            castButton:SetAttribute("macrotext", "/use item:" .. lure .. "\n/use " .. INVSLOT_MAINHAND)
            return
        end
    end
    castButton:SetAttribute("type", "spell")
    castButton:SetAttribute("spell", fishingID)
end

-- The key on the button (casts). Out of combat only.
local function BindCast()
    if not castButton then return end
    if InCombatLockdown() then
        CUI.CombatQueue.Defer("FishingBind", BindCast)
        return
    end
    ClearOverrideBindings(castButton)
    local key = F.Get("key")
    if key then SetOverrideBindingClick(castButton, true, key, BUTTON_NAME) end
end

local function StopReel()
    if not reeling then return end
    reeling = false
    BindCast()
    UpdateIndicator()
end

-- The right-click back to the game. Out of combat only.
local function Disarm()
    if clickArmed and not InCombatLockdown() then
        ClearOverrideBindings(clickOwner)
        clickArmed = false
        UpdateCastButton() -- back to what the key does
    end
end

-------------------------------------------------------------------------------
--  Session
-------------------------------------------------------------------------------
local function StartSession()
    if ReelOn() then Hold("reel", REEL_CVARS) end
    if F.Get("sound") then Hold("sound", SOUND_CVARS) end
    if inSession then return end
    inSession = true
    eventFrame:RegisterEvent("PLAYER_STARTED_MOVING")
    if ReelOn() then eventFrame:RegisterEvent("PLAYER_SOFT_INTERACT_CHANGED") end
end

local function EndSession()
    StopReel()
    Release("reel")
    Release("sound")
    if not inSession then return end
    inSession = false
    eventFrame:UnregisterEvent("PLAYER_STARTED_MOVING")
    eventFrame:UnregisterEvent("PLAYER_SOFT_INTERACT_CHANGED")
end

-- Built out of combat (the caller checks).
local function BuildButton()
    if castButton then return end
    castButton = CreateFrame("Button", BUTTON_NAME, UIParent, "SecureActionButtonTemplate")
    -- Acts on the release: the session starts just before a cast, and the
    -- double-click's second right-click casts as it comes up.
    castButton:RegisterForClicks("AnyUp", "AnyDown")
    castButton:SetAttribute("useOnKeyDown", false)
    castButton:Hide()
    -- The key's press sets what its release does (pole, lure or cast), out of
    -- combat; in combat the release does what was set last.
    castButton:SetScript("PreClick", function(self, _, down)
        if InCombatLockdown() then return end
        if down then
            -- An armed double-click keeps reading its own Apply Lure, not the key's.
            UpdateCastButton(clickArmed)
        elseif self:GetAttribute("type") == "spell" then
            StartSession()
        end
    end)
    castButton:SetScript("PostClick", function(_, _, down)
        if not down then Disarm() end
    end)
end

-- The safety net: no release reached the button within DISARM_DELAY of the
-- arming (an older timer finds a newer arming and leaves it).
local function DisarmLate()
    if clickArmed and GetTime() - armedAt >= DISARM_DELAY - 0.05 then Disarm() end
end

-- A second right-click on the world soon after the first: bound to the
-- button just for this click.
local function OnWorldMouseDown(_, btnFrame)
    if btnFrame ~= "RightButton" or not F.Get("doubleClick") or CUI.PadGamepadUI() then return end
    local nowTime = GetTime()
    local double = nowTime - lastRightClick < DOUBLE_CLICK_DELAY
    lastRightClick = double and 0 or nowTime
    if
        not double
        or not castButton
        or InCombatLockdown()
        or UnitChannelInfo("player")
        or UnitExists("mouseover")
        or not PoleInHand()
    then
        return
    end
    UpdateCastButton(true)
    SetOverrideBindingClick(clickOwner, true, "BUTTON2", BUTTON_NAME)
    clickArmed = true
    armedAt = GetTime()
    C_Timer.After(DISARM_DELAY, DisarmLate)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
eventFrame:SetScript("OnEvent", function(_, evt, _, arg2, arg3)
    if evt == "PLAYER_SOFT_INTERACT_CHANGED" then
        -- arg2: the new soft interact target. The bobber with the line in the
        -- water: the key reels in. Anything else: it casts again.
        if InCombatLockdown() then return end
        if ReelOn() and lineOut and ObjectID(arg2) == BOBBER then
            if not reeling then
                reeling = true
                ClearOverrideBindings(castButton)
                SetOverrideBinding(castButton, true, F.Get("key"), "INTERACTTARGET")
                UpdateIndicator()
            end
        else
            StopReel()
        end
    elseif evt == "UNIT_SPELLCAST_CHANNEL_START" then
        -- arg3: the spell ID
        if not (fishingName and arg3) or issecretvalue(arg3) then return end
        if C_Spell.GetSpellName(arg3) == fishingName then
            lineOut = true
            StartSession()
            UpdateIndicator()
        end
    elseif evt == "UNIT_SPELLCAST_CHANNEL_STOP" then
        lineOut = false
        StopReel()
        UpdateIndicator()
    elseif evt == "SPELLS_CHANGED" then
        ResolveFishing()
    else
        -- PLAYER_STARTED_MOVING, PLAYER_REGEN_DISABLED (bindings can still
        -- change), PLAYER_LEAVING_WORLD
        if evt == "PLAYER_REGEN_DISABLED" then
            ClearOverrideBindings(clickOwner)
            clickArmed = false
        end
        lineOut = false
        EndSession()
        UpdateIndicator()
    end
end)

local FEATURE_EVENTS = { "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_LEAVING_WORLD" }

-- Login and the options; takes effect immediately in both directions. The
-- button and the bindings only change out of combat: in combat the apply
-- waits for its end.
local booted = false
local function Apply()
    if InCombatLockdown() then
        CUI.CombatQueue.Defer("Fishing", Apply)
        return
    end
    if not booted then
        -- What a reload or a disconnect mid-session left held goes back.
        booted = true
        local held = F.Read().held
        if held then
            for set in pairs(held) do
                Release(set)
            end
        end
    end
    EndSession()
    Disarm()
    if castButton then ClearOverrideBindings(castButton) end
    UpdateIndicator()
    if not AnyOn() then
        eventFrame:UnregisterAllEvents()
        return
    end
    BuildButton()
    ResolveFishing()
    if IndicatorOn() then BuildIndicator() end -- placed in Unlock Mode before the first cast
    for index = 1, #FEATURE_EVENTS do
        eventFrame:RegisterEvent(FEATURE_EVENTS[index])
    end
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
    -- Never under the Gamepad interface style: a hook on a Blizzard frame
    -- there can run inside its secure navigation.
    if F.Get("doubleClick") and not worldHooked and not CUI.PadGamepadUI() then
        worldHooked = true
        WorldFrame:HookScript("OnMouseDown", OnWorldMouseDown)
    end
    UpdateCastButton()
    BindCast()
end

-- Options-page entry points.
CUI._Fishing = {
    Get = F.Get,
    Cfg = F.Cfg,
    Apply = Apply,
}

F.Start(Apply, {
    key = "CUI_FishingBobber",
    label = "Bobber Indicator",
    order = 60,
    shown = IndicatorOn,
    frame = function(build)
        if build then BuildIndicator() end
        return indicator
    end,
    size = function() return INDICATOR_SIZE, INDICATOR_SIZE end,
})
