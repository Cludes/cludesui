if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_ReadyCheck.lua
--
--  The Ready Check mana warning.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local REMIND, ResolveFontPath = Inner.EABR, Inner.ResolveFontPath

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end

-------------------------------------------------------------------------------
--  Ready Check Mana Warning: centered text warning for ~10s when a ready check fires in a raid and the player is a healer under 80% mana. Out-of-combat only.
-------------------------------------------------------------------------------
local SetupReadyCheckManaWarning = function()
    local warnFrame, warnFS, warnTimer, warnCurve

    -- Helpers hang on EABR, not block locals; settings slice (db.profile.consumables, options "Ready Check Mana Warning" row) is fetched inline per helper.

    -- Default ON: the warning predates its toggle, so a missing key = enabled.
    function REMIND.RCWEnabled()
        local profile = saved and saved.profile
        local c = profile and profile.consumables
        return not c or c.rcManaWarn ~= false
    end

    -- Custom swatch color, or the brightened mana color (the original look).
    function REMIND.RCWColor()
        local profile = saved and saved.profile
        local c = profile and profile.consumables
        local colour = c and c.rcManaWarnColor
        if colour and colour.r then return colour.r, colour.g, colour.b end
        local mc = CUI.GetPowerColor("MANA")
        if mc then return math.min(mc.r * 1.5, 1), math.min(mc.g * 1.5, 1), math.min(mc.b * 1.5, 1) end
        return 0, 0.825, 1
    end

    local function HideWarning()
        if warnFrame then
            if warnFrame._breathe then warnFrame._breathe:Stop() end
            warnFrame:Hide()
        end
        if warnTimer then
            warnTimer:Cancel()
            warnTimer = nil
        end
    end

    -- Pushes position/size/color settings onto the built frame; the color curve is rebuilt here since colors bake in at AddPoint time, and an already-visible warning/preview is re-tinted so edits show live.
    function REMIND.RCWApplySettings()
        if not warnFrame then return end
        local profile = saved and saved.profile
        local c = profile and profile.consumables
        warnFrame:ClearAllPoints()
        warnFrame:SetPoint(
            "CENTER",
            UIParent,
            "CENTER",
            (c and c.rcManaWarnX) or 0,
            75 + ((c and c.rcManaWarnY) or 0)
        )
        local font = ResolveFontPath(c and c.rcManaWarnFont)
        local outline = CUI.GetFontOutlineFlag("auraBuff")
        CUI.PrimeFontShadow(warnFS, outline == "" and CUI.GetFontUseShadow("auraBuff"))
        warnFS:SetFont(font, (c and c.rcManaWarnSize) or 48, outline)
        -- Explicit white instance color: tinted purely via SetVertexColor (curve result); with no instance color it would inherit the primed shadow FontObject's color, which resolves BLACK.
        warnFS:SetTextColor(1, 1, 1, 1)
        local red, green, blue = REMIND.RCWColor()
        -- Curve: alpha 1 at/below 80%, alpha 0 above; colors the FontString directly via SetVertexColor, using alpha for visibility -- no secret value reads.
        if C_CurveUtil and C_CurveUtil.CreateColorCurve then
            warnCurve = C_CurveUtil.CreateColorCurve()
            warnCurve:AddPoint(0.0, CreateColor(red, green, blue, 1))
            warnCurve:AddPoint(0.80, CreateColor(red, green, blue, 1))
            warnCurve:AddPoint(0.8001, CreateColor(red, green, blue, 0))
            warnCurve:AddPoint(1.0, CreateColor(red, green, blue, 0))
        end
        if warnFrame:IsShown() then warnFS:SetVertexColor(red, green, blue, 1) end
    end

    local function MakeWarnFrame()
        if warnFrame then return end
        warnFrame = CreateFrame("Frame", nil, UIParent)
        warnFrame:SetSize(600, 60)
        warnFrame:SetFrameStrata("FULLSCREEN")
        warnFrame:SetFrameLevel(100)
        warnFrame:Hide()
        warnFS = warnFrame:CreateFontString(nil, "OVERLAY")
        warnFS:SetPoint("CENTER")
        -- Breathe animation: fade between 60% and 100% alpha
        local anim = warnFrame:CreateAnimationGroup()
        local fadeOut = anim:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0.6)
        fadeOut:SetDuration(0.4)
        fadeOut:SetOrder(1)
        fadeOut:SetSmoothing("IN_OUT")
        local fadeIn = anim:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0.6)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.4)
        fadeIn:SetOrder(2)
        fadeIn:SetSmoothing("IN_OUT")
        anim:SetLooping("REPEAT")
        warnFrame._breathe = anim
        REMIND.RCWApplySettings()
        warnFS:SetText(CUI.L("LOW MANA"))
    end

    -- Only listens for READY_CHECK OOC AND in a raid; GROUP_ROSTER_UPDATE/zone change track raid membership, PLAYER_REGEN toggles combat state.
    local rcFrame = CreateFrame("Frame")
    local _inRaid = false

    local function UpdateReadyCheckRegistration()
        local shouldListen = _inRaid and not InCombatLockdown() and REMIND.RCWEnabled()
        if shouldListen then
            rcFrame:RegisterEvent("READY_CHECK")
        else
            rcFrame:UnregisterEvent("READY_CHECK")
            HideWarning()
        end
    end

    rcFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    rcFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    rcFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rcFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    rcFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcFrame:SetScript("OnEvent", function(_, evt)
        if
            evt == "GROUP_ROSTER_UPDATE"
            or evt == "ZONE_CHANGED_NEW_AREA"
            or evt == "PLAYER_ENTERING_WORLD"
        then
            _inRaid = IsInRaid()
            UpdateReadyCheckRegistration()
            return
        end
        if evt == "PLAYER_REGEN_DISABLED" or evt == "PLAYER_REGEN_ENABLED" then
            UpdateReadyCheckRegistration()
            return
        end
        -- READY_CHECK (only fires when out of combat AND in raid)
        if not REMIND.RCWEnabled() then return end
        local specInfo = GetSpecialization and GetSpecialization()
        if not specInfo then return end
        local role = GetSpecializationRole(specInfo)
        if role ~= "HEALER" then return end
        if not UnitPowerPercent then return end
        MakeWarnFrame()
        REMIND.RCWApplySettings()
        if not warnCurve then return end
        -- Lets WoW's C side evaluate mana% against the curve: full alpha below 80%, zero above. SetVertexColor applies the secret RGBA directly -- no reads needed.
        local color = UnitPowerPercent("player", Enum.PowerType.Mana, false, warnCurve)
        if not color or not color.GetRGBA then return end
        warnFS:SetVertexColor(color:GetRGBA())
        warnFrame:Show()
        if warnFrame._breathe and not warnFrame._breathe:IsPlaying() then warnFrame._breathe:Play() end
        if warnTimer then warnTimer:Cancel() end
        warnTimer = C_Timer.NewTimer(10, HideWarning)
    end)

    -- Options hooks (Consumables -> Ready Check Mana Warning row).
    _G._CUABR_RCWarnApply = function()
        MakeWarnFrame()
        REMIND.RCWApplySettings()
    end
    -- Preview bypasses the curve (must be visible at any mana level), tinting with the plain configured color (readable constants, no secrets).
    _G._CUABR_RCWarnPreview = function()
        MakeWarnFrame()
        REMIND.RCWApplySettings()
        if warnTimer then
            warnTimer:Cancel()
            warnTimer = nil
        end
        local red, green, blue = REMIND.RCWColor()
        warnFS:SetVertexColor(red, green, blue, 1)
        warnFrame:Show()
        if warnFrame._breathe and not warnFrame._breathe:IsPlaying() then warnFrame._breathe:Play() end
    end
    _G._CUABR_RCWarnHidePreview = HideWarning
    _G._CUABR_RCWarnUpdateReg = UpdateReadyCheckRegistration
end
-- The warning reads retail spec roles and lives in the consumables options; WoW Forever skips it.
if not REMIND.FOREVER then SetupReadyCheckManaWarning() end

Inner.broken = false
