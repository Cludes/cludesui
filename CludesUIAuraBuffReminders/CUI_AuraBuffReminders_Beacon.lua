if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Beacon.lua
--
--  Last-used item tracking and the standalone Beacon reminders.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local floor = math.floor

local _B, DEFAULT_TEXT_COLOR, REMIND = Inner._B, Inner.DEFAULT_TEXT_COLOR, Inner.EABR
local GetTextAnchorPoints, Known = Inner.GetTextAnchorPoints, Inner.Known
local ResolveFontPath, SetABRFont, ShortLabel = Inner.ResolveFontPath, Inner.SetABRFont, Inner.ShortLabel
local Tex, texCache, FLASK_ITEMS, FOOD_ITEMS = Inner.Tex, Inner.texCache, Inner.FLASK_ITEMS, Inner.FOOD_ITEMS
local WEAPON_ENCHANT_ITEMS, ApplyGlow = Inner.WEAPON_ENCHANT_ITEMS, Inner.ApplyGlow
local ICON_SIZE, RemoveGlow, LayoutIcons = Inner.ICON_SIZE, Inner.RemoveGlow, Inner.LayoutIcons
local CursorAttachActive, ReleaseCursorAnchor = Inner.CursorAttachActive, Inner.ReleaseCursorAnchor

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
local cuiPanelOpen = false
Inner.panelOpenSetters[#Inner.panelOpenSetters + 1] = function(val) cuiPanelOpen = val end
local combatAnchor
Inner.combatAnchorSetters[#Inner.combatAnchorSetters + 1] = function(val) combatAnchor = val end
local cursorAnchor
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val) cursorAnchor = val end

-------------------------------------------------------------------------------
--  Last-Used Item Tracking (per-character)
-------------------------------------------------------------------------------
local TrackItemUse
do
    local flaskSet, foodSet, weSet = {}, {}, {}
    for _, frame in ipairs(FLASK_ITEMS) do
        for _, ident in ipairs(frame.items) do
            flaskSet[ident] = true
        end
    end
    for _, frame in ipairs(FOOD_ITEMS) do
        foodSet[frame.itemID] = true
    end
    for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
        weSet[we.itemID] = true
    end
    TrackItemUse = function(itemId)
        if not saved or not saved.profile then return end
        -- All persistent use-tracking lives in db.profile (this DB layer has no `char` namespace).
        if flaskSet[itemId] then
            saved.profile.lastUsedFlask = itemId
        elseif foodSet[itemId] then
            saved.profile.lastUsedFood = itemId
        elseif weSet[itemId] then
            saved.profile.lastUsedWeaponEnchant = itemId
        end
    end
end

-------------------------------------------------------------------------------
--  Standalone Beacon Reminders -- IsSpellOverlayed-based, combat-safe, independent from the main aura/buff system.
-------------------------------------------------------------------------------
_B.frame = CreateFrame("Frame")
_B.isPaladin = false
_B.overlayRegistered = false
_B.anchor = nil
_B.icons = {}
_B.iconState = {}
_B.glowState = {}
_B.cachedInInstance = false
_B.refreshPending = false
_B.onCursor = false -- shown beacons are placed on the cursor anchor
local _cursorBeacons = {} -- BeaconLayoutIcons' scratch list, reused
_B.BOL = 53563
_B.BOF = 156910
_B.VIRTUE = 200025
_B.ALL = { _B.BOL, _B.BOF }
local IsSpellOverlayed = (C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed)
    or IsSpellOverlayed

local function BeaconUpdateInstanceCache()
    local _, instanceType, difficultyID = GetInstanceInfo()
    difficultyID = tonumber(difficultyID) or 0
    -- PvP instances (arenas/BGs) have difficultyID 0 but are still valid
    if instanceType == "pvp" or instanceType == "arena" then
        _B.cachedInInstance = true
        return
    end
    if difficultyID == 0 then
        _B.cachedInInstance = false
        return
    end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        _B.cachedInInstance = false
        return
    end
    _B.cachedInInstance = (
        instanceType == "party"
        or instanceType == "raid"
        or (instanceType == "scenario" and difficultyID == 208)
    )
end

local function BeaconUpdateOverlayEvents()
    if _B.cachedInInstance and _B.isPaladin then
        if not _B.overlayRegistered then
            _B.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _B.frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _B.overlayRegistered = true
        end
    else
        if _B.overlayRegistered then
            _B.frame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
            _B.frame:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
            _B.overlayRegistered = false
        end
    end
end

local function BeaconMakeIcon(spellId)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(ICON_SIZE, ICON_SIZE)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(120)
    frame:Hide()
    local iconTex = frame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    iconTex:SetTexture(Tex(spellId))
    iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame._icon = iconTex
    frame._spellID = spellId
    REMIND.ApplyIconBorder(frame, false)
    local textValue = REMIND.GetIconTextOverlay(frame):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", frame, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    frame._text = textValue
    return frame
end

local function BeaconLayoutIcons()
    -- Beacon icons are merged into the main LayoutIcons row; the separate beacon anchor is hidden (unused).
    if _B.anchor then CludesUI.SetElementVisibility(_B.anchor, false) end

    -- When cursor-attached, position beacon icons at the cursor anchor
    local useCursor = saved and CursorAttachActive(saved.profile.display) and cursorAnchor
    if useCursor then
        local visIcons = _cursorBeacons
        wipe(visIcons)
        for _, ident in ipairs(_B.ALL or {}) do
            if _B.iconState and _B.iconState[ident] and _B.icons[ident] then
                visIcons[#visIcons + 1] = _B.icons[ident]
            end
        end
        _B.onCursor = #visIcons > 0
        if _B.onCursor then
            local display = saved.profile.display
            local spacing = display.iconSpacing or 8
            local baseScale = display.scale or 1.0
            local iconSz = floor(ICON_SIZE * baseScale + 0.5)
            local iconH = iconSz
            if display.iconShape and display.iconShape ~= "none" then
                iconSz, iconH = mod.IconDimensions(iconSz, display)
            end
            local totalW = (#visIcons * iconSz) + ((#visIcons - 1) * spacing)
            local startX = -(totalW / 2) + (iconSz / 2)
            for index, frame in ipairs(visIcons) do
                frame:SetSize(iconSz, iconH)
                frame:SetAlpha(display.opacity or 1.0)
                frame:SetFrameStrata("TOOLTIP")
                frame:SetFrameLevel(9980)
                REMIND.ApplyIconBorder(frame, false)
                frame:ClearAllPoints()
                frame:SetPoint(
                    "CENTER",
                    cursorAnchor,
                    "CENTER",
                    startX + (index - 1) * (iconSz + spacing),
                    -(iconH + 8)
                )
            end
            cursorAnchor:Show()
            CludesUI.SetElementVisibility(cursorAnchor, true)
        else
            ReleaseCursorAnchor()
        end
        return
    end

    -- Restore beacon icons to normal strata after leaving cursor mode
    _B.onCursor = false
    for _, ident in ipairs(_B.ALL or {}) do
        if _B.icons and _B.icons[ident] then
            _B.icons[ident]:SetFrameStrata("HIGH")
            _B.icons[ident]:SetFrameLevel(120)
        end
    end
    -- Re-layout main icons to include/exclude beacon icons
    LayoutIcons()
    ReleaseCursorAnchor()
end

local function BeaconApplyGlow(frame, show)
    if show then
        local p = saved and saved.profile.display
        local glowType = p and p.glowType or 0
        if glowType > 0 then
            local baseScale = p and p.scale or 1.0
            local iconSz = floor(ICON_SIZE * baseScale + 0.5)
            ApplyGlow(frame, p, iconSz)
        end
        _B.glowState[frame._spellID] = true
    else
        if _B.glowState[frame._spellID] then
            RemoveGlow(frame)
            _B.glowState[frame._spellID] = false
        end
    end
end

local function BeaconApplyText(frame)
    local p = saved and saved.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(frame._text, fontFile, textSize)
        frame._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        frame._text:SetPoint(tp, frame, ip, xOff, yOff)
        frame._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        frame._text:SetText(ShortLabel(frame._spellID == _B.BOL and "Beacon of Light" or "Beacon of Faith"))
        frame._text:Show()
    else
        frame._text:SetText("")
        frame._text:Hide()
    end
end

local function ShowBeaconIcon(spellId, show)
    local frame = _B.icons[spellId]
    if not frame then return end
    local changed = false
    if show then
        if not _B.iconState[spellId] then
            BeaconApplyText(frame)
            frame:Show()
            _B.iconState[spellId] = true
            BeaconApplyGlow(frame, true)
            changed = true
        end
    else
        if _B.iconState[spellId] then
            BeaconApplyGlow(frame, false)
            frame._text:SetText("")
            frame:Hide()
            _B.iconState[spellId] = false
            changed = true
        end
    end
    if changed then BeaconLayoutIcons() end
end

local function SyncBeacons()
    if not _B.isPaladin then return end
    if cuiPanelOpen or not IsSpellOverlayed then
        ShowBeaconIcon(_B.BOL, false)
        ShowBeaconIcon(_B.BOF, false)
        return
    end
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        ShowBeaconIcon(_B.BOL, false)
        ShowBeaconIcon(_B.BOF, false)
        return
    end
    if not _B.cachedInInstance or not (IsInGroup() or IsInRaid()) then
        ShowBeaconIcon(_B.BOL, false)
        ShowBeaconIcon(_B.BOF, false)
        return
    end

    local au = saved and saved.profile.auras
    local enabled = au and au.enabled

    local trackBOL = enabled and enabled.bol ~= false and Known(_B.BOL) and not Known(_B.VIRTUE)
    local trackBOF = enabled and enabled.bof ~= false and Known(_B.BOF)

    ShowBeaconIcon(_B.BOL, trackBOL and IsSpellOverlayed(_B.BOL))
    ShowBeaconIcon(_B.BOF, trackBOF and IsSpellOverlayed(_B.BOF))
end

-- Combat edges (the main event handler, right after the combat flag moves):
-- with Only on Cursor in Combat on, shown beacons move between the reminder
-- row and the cursor. Their layout otherwise runs only when one shows or
-- hides. Nothing to do for a non-Paladin or with the option off.
local function BeaconCombatEdge()
    if not _B.isPaladin then return end
    local p = saved and saved.profile.display
    if p and p.cursorAttach and p.cursorAttachCombatOnly then BeaconLayoutIcons() end
end

local function BeaconRefreshSoon()
    if _B.refreshPending then return end
    _B.refreshPending = true
    C_Timer.After(0, function()
        _B.refreshPending = false
        SyncBeacons()
    end)
end

local function BeaconInit()
    local _, class = UnitClass("player")
    _B.isPaladin = (class == "PALADIN")
    if not _B.isPaladin then return end

    _B.icons[_B.BOL] = BeaconMakeIcon(_B.BOL)
    _B.icons[_B.BOF] = BeaconMakeIcon(_B.BOF)

    _B.anchor = CreateFrame("Frame", "EABR_BeaconAnchor", UIParent)
    _B.anchor:SetSize(1, 1)
    _B.anchor:SetFrameStrata("HIGH")
    _B.anchor:EnableMouse(false)
    _B.anchor:Show()
    CludesUI.SetElementVisibility(_B.anchor, false)
    -- Anchor to the combat anchor (created by OnEnable before this call)
    if combatAnchor then
        _B.anchor:SetPoint("CENTER", combatAnchor, "CENTER", 0, -60)
    else
        _B.anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end

    BeaconUpdateInstanceCache()
    BeaconUpdateOverlayEvents()
    SyncBeacons()
end

-- Expose for options and anchor positioning
_G._CUABR_BeaconRefresh = SyncBeacons

-- Beacon tracking is retail Holy Paladin; WoW Forever registers nothing here
-- (BeaconInit is skipped there too, so the handler would only ever return).
if not REMIND.FOREVER then
    _B.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    _B.frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    _B.frame:RegisterEvent("SPELLS_CHANGED")
    _B.frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    _B.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _B.frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    _B.frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    _B.frame:RegisterEvent("PLAYER_LEVEL_CHANGED")
end
_B.frame:SetScript("OnEvent", function(_, e, ident)
    if not _B.isPaladin then return end
    if e == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or e == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if ident == _B.BOL or ident == _B.BOF then SyncBeacons() end
        return
    end
    if e == "PLAYER_ENTERING_WORLD" or e == "ZONE_CHANGED_NEW_AREA" or e == "GROUP_ROSTER_UPDATE" then
        BeaconUpdateInstanceCache()
        BeaconUpdateOverlayEvents()
    end
    if
        e == "TRAIT_CONFIG_UPDATED"
        or e == "PLAYER_TALENT_UPDATE"
        or e == "SPELLS_CHANGED"
        or e == "PLAYER_SPECIALIZATION_CHANGED"
        or e == "PLAYER_LEVEL_CHANGED"
    then
        -- Invalidates cached spell textures for beacon spells so dynamic icon changes (e.g. BOL morphing to Virtue) pick up the new icon.
        if texCache then
            texCache[_B.BOL] = nil
            texCache[_B.BOF] = nil
        end
        for _, spellRef in ipairs(_B.ALL) do
            local frame = _B.icons[spellRef]
            if frame and frame._icon then
                local t = Tex(spellRef)
                if t then frame._icon:SetTexture(t) end
            end
        end
        BeaconRefreshSoon()
        return
    end
    SyncBeacons()
end)

Inner.BeaconInit, Inner.BeaconRefresh, Inner.TrackItemUse = BeaconInit, SyncBeacons, TrackItemUse
Inner.BeaconCombatEdge = BeaconCombatEdge
Inner.broken = false
