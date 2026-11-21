if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
local _, mod = ...
if not mod.ECME then return end

-- A display-only consumer of Blizzard's recommendation changes. No secure
-- action button, Blizzard-frame writes, hooks, timers or polling.
--
-- Cost by state: off = nothing registered; on while Blizzard's Assisted
-- Highlight is off = the highlight-state callback alone; live = the combat
-- edges, plus, while the icon may show (Only in Combat allows it, or Unlock
-- Mode), the recommendation callbacks and the form, vehicle and pet battle
-- events. Each of them only shows the hidden driver, whose one-shot OnUpdate
-- runs a single Update per frame. SPELL_UPDATE_COOLDOWN is armed only while
-- Show GCD has a recommendation on screen. Target and spec changes need no
-- events: Blizzard's manager polls the recommendation and re-fires the
-- spell-change callback whenever it changes (a spec swap also fires
-- RotationSpellsUpdated). A form change resets the manager's last value
-- before its next read, so a change to no recommendation fires nothing
-- there: UPDATE_SHAPESHIFT_FORM stays.
local widget, iconTex, textOverlay, keybind, gcd, driver
local isActive, live, watching, preview, inCombat = false, false, false, false, false
local gcdArmed, gcdStamp = false, nil
-- Paint stamps: the texture and label on screen (nil / false = repaint).
local paintedTexture, paintedKey = nil, false
local moverKey = "ECME_RotationAssistIcon"
local CB_SPELL = "AssistedCombatManager.OnAssistedHighlightSpellChange"
local CB_ROTATION = "AssistedCombatManager.RotationSpellsUpdated"
local CB_STATE = "AssistedCombatManager.OnSetUseAssistedHighlight"
local edgeEvents = { "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local watchEvents = {
    "UPDATE_SHAPESHIFT_FORM",
    "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_VEHICLE_ACTIONBAR",
    "PET_BATTLE_OPENING_START",
    "PET_BATTLE_CLOSE",
}

-- Where the icon sits until it is dragged or offset. The options page reads
-- it too; it is shared, so copy it before writing to it.
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = -140 }
mod.CDM_ROTATION_ICON_DEFAULT_POS = DEFAULT_POS

-- Every recommendation comes from Blizzard's Assisted Highlight; WoW Forever
-- has no assisted combat at all.
function mod.RotationAssistAvailable()
    if CUI.IS_FOREVER then return false end
    return GetCVarBool("assistedCombatHighlight") == true
end

local function Settings()
    local p = mod.ECME.db and mod.ECME.db.profile
    return p and p.rotationAssistIcon
end

local function SpellID(value)
    if issecretvalue(value) or type(value) ~= "number" or value <= 0 then return nil end
    return value
end

-- The global cooldown is independent of the recommended spell's cooldown.
-- Its duration object goes straight to the native widget (no timing reads),
-- pushed through on every pass with no value comparison.
local function PaintGCD()
    local duration = C_Spell.GetSpellCooldownDuration(CUI.GCD_SPELL)
    if duration then
        gcd:Show()
        gcd:SetCooldownFromDurationObject(duration)
    else
        gcd:Clear()
        gcd:Hide()
    end
end

-- SPELL_UPDATE_COOLDOWN storms within a frame: the first event paints at once,
-- and a same-frame repeat queues one trailing pass (Update repaints the swipe
-- after the frame's events), so a later state in that frame is never dropped.
local function UpdateGCD()
    local nowTime = GetTime()
    if gcdStamp == nowTime then
        driver:Show()
        return
    end
    gcdStamp = nowTime
    PaintGCD()
end

-- SPELL_UPDATE_COOLDOWN rides the icon's show edge (Show GCD with a
-- recommendation on screen) and is dropped again on its hide edge.
local function ArmGCD(on)
    if on == gcdArmed then return end
    gcdArmed = on
    if not on then
        driver:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
        if gcd then
            gcd:Clear()
            gcd:Hide()
        end
        return
    end
    if not gcd then
        gcd = CreateFrame("Cooldown", nil, widget, "CooldownFrameTemplate")
        gcd:SetAllPoints(iconTex)
        gcd:SetFrameLevel(widget:GetFrameLevel() + 1)
        gcd:EnableMouse(false)
        gcd:SetDrawSwipe(true)
        gcd:SetSwipeColor(0, 0, 0, 0.65)
        gcd:SetDrawEdge(true)
        gcd:SetDrawBling(false)
        gcd:SetHideCountdownNumbers(true)
    end
    driver:RegisterEvent("SPELL_UPDATE_COOLDOWN")
end

local function HideIcon()
    ArmGCD(false)
    widget:Hide()
end

local function Queue() driver:Show() end

-- The show-edge sources: armed while the icon may show, dropped while Only
-- in Combat hides it out of combat (the combat edges re-arm them).
local function SetWatch(on)
    if on == watching then return end
    watching = on
    if on then
        for index = 1, #watchEvents do
            driver:RegisterEvent(watchEvents[index])
        end
        EventRegistry:RegisterCallback(CB_SPELL, Queue, driver)
        EventRegistry:RegisterCallback(CB_ROTATION, Queue, driver)
        mod.UpdateRotationAssistIconKeybind = Queue
        return
    end
    for index = 1, #watchEvents do
        driver:UnregisterEvent(watchEvents[index])
    end
    EventRegistry:UnregisterCallback(CB_SPELL, driver)
    EventRegistry:UnregisterCallback(CB_ROTATION, driver)
    mod.UpdateRotationAssistIconKeybind = nil
end

local function RunPass()
    -- A direct pass also consumes a queued one.
    driver:Hide()
    if not live then return end
    local conf = Settings()
    if not conf or not conf.enabled then
        HideIcon()
        return
    end
    local editing = preview and not inCombat
    local mayShow = editing or inCombat or not conf.onlyInCombat
    SetWatch(mayShow)
    local spellId
    if
        mayShow
        and not C_ActionBar.HasVehicleActionBar()
        and not C_ActionBar.HasOverrideActionBar()
        and not C_PetBattles.IsInBattle()
        and C_AssistedCombat.IsAvailable()
    then
        spellId = SpellID(C_AssistedCombat.GetNextCastSpell(true))
    end
    if not spellId and not editing then
        HideIcon()
        return
    end
    local texture = spellId and C_Spell.GetSpellTexture(spellId) or 134400
    if issecretvalue(texture) then
        HideIcon()
        return
    end
    if texture ~= paintedTexture then
        paintedTexture = texture
        iconTex:SetTexture(texture)
    end
    local key = conf.showKeybind and spellId and mod.ResolveCDMKeybind(spellId) or nil
    if key ~= paintedKey then
        paintedKey = key
        keybind:SetText(key or "")
        keybind:SetShown(key ~= nil)
        mod.ShowCDMKeybindBadge(keybind, conf)
    end
    widget:Show()
    ArmGCD(conf.showGCD == true and spellId ~= nil)
    if gcdArmed then PaintGCD() end
end

local function OnEvent(self, evt)
    if evt == "SPELL_UPDATE_COOLDOWN" then
        UpdateGCD()
        return
    end
    -- Combat state comes from the edge itself: InCombatLockdown() still
    -- reads false inside the PLAYER_REGEN_DISABLED dispatch.
    if evt == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif evt == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif evt == "PLAYER_ENTERING_WORLD" then
        inCombat = (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
    end
    self:Show()
end

local function PlaceIcon()
    if not widget or CUI._unlockActive then return end
    local conf = Settings()
    local place = conf and conf.position or DEFAULT_POS
    widget:ClearAllPoints()
    widget:SetPoint(place.point or "CENTER", UIParent, place.relPoint or "CENTER", place.x or 0, place.y or 0)
end

local function OnUnlock(activeSession)
    preview = activeSession and true or false
    if not activeSession then PlaceIcon() end
    RunPass()
end

local function RegisterMover()
    -- Element Options opens the icon's own page. The key must not start with
    -- CDM_: Unlock Mode and spec layers read that prefix as a CDM bar.
    local map = CUI._ELEMENT_SETTINGS_MAP or {}
    CUI._ELEMENT_SETTINGS_MAP = map
    if not map[moverKey] then
        map[moverKey] = {
            module = "CludesUICooldownManager",
            page = "Rotation Assist Icon",
            sectionName = "ROTATION ASSIST ICON",
            highlightText = "Show Rotation Assist Icon",
        }
    end
    CUI:RegisterUnlockElements({
        CUI.MakeUnlockElement({
            key = moverKey,
            label = "Rotation Assist Icon",
            group = "Cooldown Manager",
            order = 601,
            getFrame = function() return widget end,
            getSize = function() return widget:GetWidth(), widget:GetHeight() end,
            noResize = true,
            noAnchorTo = true,
            noAnchorTarget = true,
            noSizeMatchTarget = true,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                local conf = Settings()
                if conf then
                    conf.position = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                end
                PlaceIcon()
            end,
            loadPos = function()
                local conf = Settings()
                return conf and conf.position
            end,
            clearPos = function()
                local conf = Settings()
                if conf then conf.position = nil end
            end,
            applyPos = PlaceIcon,
        }),
    }, "CludesUICooldownManager")
    CUI:RegisterUnlockModeListener(widget, OnUnlock)
end

-- Live = enabled with Blizzard's Assisted Highlight on. Off it, nothing but
-- the highlight-state callback stays armed (no events, mover or listener).
-- Going live arms the combat edges; the next Update arms the rest.
local function SetLive(on)
    if on == live then return end
    live = on
    if on then
        inCombat = (InCombatLockdown() or UnitAffectingCombat("player")) and true or false
        for index = 1, #edgeEvents do
            driver:RegisterEvent(edgeEvents[index])
        end
        RegisterMover()
        return
    end
    SetWatch(false)
    ArmGCD(false)
    driver:UnregisterAllEvents()
    driver:Hide()
    CUI:UnregisterUnlockModeListener(widget)
    CUI:UnregisterUnlockElement(moverKey)
    preview = false
    widget:Hide()
end

local function OnHighlightState()
    SetLive(mod.RotationAssistAvailable())
    RunPass()
end

local function CreateIcon()
    widget = CreateFrame("Frame", nil, UIParent)
    widget:SetFrameStrata("MEDIUM")
    widget:Hide()
    local level = widget:GetFrameLevel()
    iconTex = widget:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Levels above the icon: GCD swipe +1, the 1px black rim +2 (its pixel
    -- border +3), the keybind badge +4/+5 (StyleCDMKeybind), the label +6.
    local rim = CreateFrame("Frame", nil, widget)
    rim:SetAllPoints()
    rim:SetFrameLevel(level + 2)
    CUI.PP.CreateBorder(rim, 0, 0, 0, 1, 1)
    textOverlay = CreateFrame("Frame", nil, widget)
    textOverlay:SetAllPoints()
    textOverlay:SetFrameLevel(level + 6)
    keybind = textOverlay:CreateFontString(nil, "OVERLAY")
    -- SetText also requires a font when the opt-in label is still hidden.
    CUI.ApplyIconTextFont(keybind, mod.GetCDMFont(), 14 * CUI.PP.mult, "cdm")
    -- The one event and callback owner: hidden while idle, shown to queue a
    -- pass, and its one-shot OnUpdate (Update hides it first) runs that pass.
    driver = mod.TakeShell()
    driver:Hide()
    driver:SetScript("OnUpdate", RunPass)
    driver:SetScript("OnEvent", OnEvent)
end

function mod.RefreshRotationAssistIcon()
    -- Kept defined on WoW Forever (called unguarded), where it does nothing.
    if CUI.IS_FOREVER then return end
    local conf = Settings()
    if not conf or not conf.enabled then
        if not isActive then return end
        isActive = false
        EventRegistry:UnregisterCallback(CB_STATE, driver)
        SetLive(false)
        return
    end
    if not widget then CreateIcon() end
    local size = conf.iconSize or 48
    CUI.PP.Size(widget, size, size)
    mod.StyleCDMKeybind(keybind, conf, textOverlay, CUI.PP.mult, mod.GetCDMFont())
    -- Settings edge: the next pass repaints the texture and the label.
    paintedTexture, paintedKey = nil, false
    PlaceIcon()
    if not isActive then
        isActive = true
        EventRegistry:RegisterCallback(CB_STATE, OnHighlightState, driver)
    end
    SetLive(mod.RotationAssistAvailable())
    RunPass()
end
