if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
if not Inner or Inner.broken then
    return
end
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
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local cuiPanelOpen = false
Inner.panelOpenSetters[#Inner.panelOpenSetters + 1] = function(val)
    cuiPanelOpen = val
end
local combatAnchor
Inner.combatAnchorSetters[#Inner.combatAnchorSetters + 1] = function(val)
    combatAnchor = val
end
local cursorAnchor
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val)
    cursorAnchor = val
end

-------------------------------------------------------------------------------
--  Last-Used Item Tracking (per-character)
-------------------------------------------------------------------------------
local TrackItemUse
do
    local flaskSet, foodSet, weSet = {}, {}, {}
    for _, f in ipairs(FLASK_ITEMS) do
        for _, ident in ipairs(f.items) do
            flaskSet[ident] = true
        end
    end
    for _, f in ipairs(FOOD_ITEMS) do
        foodSet[f.itemID] = true
    end
    for _, we in ipairs(WEAPON_ENCHANT_ITEMS) do
        weSet[we.itemID] = true
    end
    TrackItemUse = function(itemId)
        if not saved or not saved.profile then
            return
        end
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
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(120)
    f:Hide()
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(Tex(spellId))
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f._icon = icon
    f._spellID = spellId
    REMIND.ApplyIconBorder(f, false)
    local textValue = REMIND.GetIconTextOverlay(f):CreateFontString(nil, "OVERLAY")
    textValue:SetPoint("TOP", f, "BOTTOM", 0, -2)
    SetABRFont(textValue, ResolveFontPath(), 11)
    textValue:SetTextColor(1, 1, 1, 1)
    f._text = textValue
    return f
end

local function BeaconLayoutIcons()
    -- Beacon icons are merged into the main LayoutIcons row; the separate beacon anchor is hidden (unused).
    if _B.anchor then
        CludesUI.SetElementVisibility(_B.anchor, false)
    end

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
            local p = saved.profile.display
            local spacing = p.iconSpacing or 8
            local baseScale = p.scale or 1.0
            local sz = floor(ICON_SIZE * baseScale + 0.5)
            local iconH = sz
            if p.iconShape and p.iconShape ~= "none" then
                sz, iconH = mod.IconDimensions(sz, p)
            end
            local totalW = (#visIcons * sz) + ((#visIcons - 1) * spacing)
            local startX = -(totalW / 2) + (sz / 2)
            for idx, f in ipairs(visIcons) do
                f:SetSize(sz, iconH)
                f:SetAlpha(p.opacity or 1.0)
                f:SetFrameStrata("TOOLTIP")
                f:SetFrameLevel(9980)
                REMIND.ApplyIconBorder(f, false)
                f:ClearAllPoints()
                f:SetPoint(
                    "CENTER",
                    cursorAnchor,
                    "CENTER",
                    startX + (idx - 1) * (sz + spacing),
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

local function BeaconApplyGlow(f, show)
    if show then
        local p = saved and saved.profile.display
        local glowType = p and p.glowType or 0
        if glowType > 0 then
            local baseScale = p and p.scale or 1.0
            local sz = floor(ICON_SIZE * baseScale + 0.5)
            ApplyGlow(f, p, sz)
        end
        _B.glowState[f._spellID] = true
    else
        if _B.glowState[f._spellID] then
            RemoveGlow(f)
            _B.glowState[f._spellID] = false
        end
    end
end

local function BeaconApplyText(f)
    local p = saved and saved.profile.display
    if p and p.showText then
        local tc = p.textColor or DEFAULT_TEXT_COLOR
        local fontFile = ResolveFontPath(p.nameFont)
        local textSize = p.textSize or 11
        local xOff = p.textXOffset or 0
        local yOff = p.textYOffset or -2
        SetABRFont(f._text, fontFile, textSize)
        f._text:ClearAllPoints()
        local tp, ip = GetTextAnchorPoints(p)
        f._text:SetPoint(tp, f, ip, xOff, yOff)
        f._text:SetTextColor(tc.r, tc.g, tc.b, 1)
        f._text:SetText(ShortLabel(f._spellID == _B.BOL and "Beacon of Light" or "Beacon of Faith"))
        f._text:Show()
    else
        f._text:SetText("")
        f._text:Hide()
    end
end

local function BeaconSetVisible(spellId, show)
    local f = _B.icons[spellId]
    if not f then
        return
    end
    local changed = false
    if show then
        if not _B.iconState[spellId] then
            BeaconApplyText(f)
            f:Show()
            _B.iconState[spellId] = true
            BeaconApplyGlow(f, true)
            changed = true
        end
    else
        if _B.iconState[spellId] then
            BeaconApplyGlow(f, false)
            f._text:SetText("")
            f:Hide()
            _B.iconState[spellId] = false
            changed = true
        end
    end
    if changed then
        BeaconLayoutIcons()
    end
end

local function BeaconRefresh()
    if not _B.isPaladin then
        return
    end
    if cuiPanelOpen or not IsSpellOverlayed then
        BeaconSetVisible(_B.BOL, false)
        BeaconSetVisible(_B.BOF, false)
        return
    end
    if UnitInVehicle("player") or (IsMounted() and IsFlying()) then
        BeaconSetVisible(_B.BOL, false)
        BeaconSetVisible(_B.BOF, false)
        return
    end
    if not _B.cachedInInstance or not (IsInGroup() or IsInRaid()) then
        BeaconSetVisible(_B.BOL, false)
        BeaconSetVisible(_B.BOF, false)
        return
    end

    local au = saved and saved.profile.auras
    local enabled = au and au.enabled

    local trackBOL = enabled and enabled.bol ~= false and Known(_B.BOL) and not Known(_B.VIRTUE)
    local trackBOF = enabled and enabled.bof ~= false and Known(_B.BOF)

    BeaconSetVisible(_B.BOL, trackBOL and IsSpellOverlayed(_B.BOL))
    BeaconSetVisible(_B.BOF, trackBOF and IsSpellOverlayed(_B.BOF))
end

-- Combat edges (the main event handler, right after the combat flag moves):
-- with Only on Cursor in Combat on, shown beacons move between the reminder
-- row and the cursor. Their layout otherwise runs only when one shows or
-- hides. Nothing to do for a non-Paladin or with the option off.
local function BeaconCombatEdge()
    if not _B.isPaladin then
        return
    end
    local p = saved and saved.profile.display
    if p and p.cursorAttach and p.cursorAttachCombatOnly then
        BeaconLayoutIcons()
    end
end

local function BeaconRefreshSoon()
    if _B.refreshPending then
        return
    end
    _B.refreshPending = true
    C_Timer.After(0, function()
        _B.refreshPending = false
        BeaconRefresh()
    end)
end

local function BeaconInit()
    local _, class = UnitClass("player")
    _B.isPaladin = (class == "PALADIN")
    if not _B.isPaladin then
        return
    end

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
    BeaconRefresh()
end

-- Expose for options and anchor positioning
_G._CUABR_BeaconRefresh = BeaconRefresh

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
    if not _B.isPaladin then
        return
    end
    if e == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" or e == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        if ident == _B.BOL or ident == _B.BOF then
            BeaconRefresh()
        end
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
            local f = _B.icons[spellRef]
            if f and f._icon then
                local t = Tex(spellRef)
                if t then
                    f._icon:SetTexture(t)
                end
            end
        end
        BeaconRefreshSoon()
        return
    end
    BeaconRefresh()
end)

Inner.BeaconInit, Inner.BeaconRefresh, Inner.TrackItemUse = BeaconInit, BeaconRefresh, TrackItemUse
Inner.BeaconCombatEdge = BeaconCombatEdge
Inner.broken = false
