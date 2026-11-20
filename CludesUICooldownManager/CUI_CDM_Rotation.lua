if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Rotation.lua
--
--  Rotation helper integration (Blizzard C_AssistedCombat).
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ECME, FC, SnapForScale, _ecmeFC = Inner.ECME, Inner.FC, Inner.SnapForScale, Inner._ecmeFC
local _getFD, StartNativeGlow, StopNativeGlow = Inner._getFD, Inner.StartNativeGlow, Inner.StopNativeGlow
local cdmBarIcons = Inner.cdmBarIcons

-- Shown CDM bar icons for spellID, filled into out (wiped first). A CDM icon
-- and a suggested spell can each hold EITHER the base or an override spell id
-- (e.g. Maul <-> Raze), and which side is which varies by spec, so base ids
-- are compared in BOTH directions.
local function CDMIconsForSpell(spellId, result)
    wipe(result)
    local GetBaseSpell = C_Spell and C_Spell.GetBaseSpell
    local spellBase = (GetBaseSpell and GetBaseSpell(spellId)) or spellId
    if type(spellBase) ~= "number" or (issecretvalue and issecretvalue(spellBase)) then
        spellBase = spellId
    end
    for _, icons in pairs(cdmBarIcons) do
        for _, iconTex in ipairs(icons) do
            local ifc = _ecmeFC[iconTex]
            local spellRef = ifc and ifc.spellID
            if type(spellRef) ~= "number" or (issecretvalue and issecretvalue(spellRef)) then
                spellRef = nil
            end
            if spellRef and iconTex:IsShown() then
                -- Direct/base match first (cheap); only resolve the icon's own base if those
                -- miss, to keep the common path light. sid > 0: item/trinket icons store -itemID/-13/-14, which must not be fed to GetBaseSpell.
                local match = (spellRef == spellId) or (spellRef == spellBase)
                if not match and GetBaseSpell and spellRef > 0 then
                    local sidBase = GetBaseSpell(spellRef)
                    if type(sidBase) == "number" and not (issecretvalue and issecretvalue(sidBase)) then
                        match = sidBase == spellBase
                    end
                end
                if match then
                    result[#result + 1] = iconTex
                end
            end
        end
    end
    return result
end

-- Plugin API (PLUGINS_API.md): the CDM icons currently showing spellID.
function CludesUI.GetCDMIconsForSpell(spellId, result)
    result = result or {}
    if type(spellId) ~= "number" or (issecretvalue and issecretvalue(spellId)) or spellId <= 0 then
        wipe(result)
        return result
    end
    return CDMIconsForSpell(spellId, result)
end

-------------------------------------------------------------------------------
--  Rotation Helper Integration (Blizzard C_AssistedCombat)
--  Highlights the currently suggested spell on its CDM icon. The default is
--  Blizzard's ActionBarButtonAssistedCombatHighlightTemplate; profile settings
--  can opt into a custom glow or a static solid border.
-------------------------------------------------------------------------------
do
    mod._rotationGlowedIcons = {}
    local _rotMatched = {} -- scratch for CDMIconsForSpell
    local _rotSpareSet = {} -- each pass fills this and swaps it with ns._rotationGlowedIcons
    mod._rotationHookInstalled = false
    mod._rotationInCombat = false

    local ROT_GLOW_RATIO = 0.33
    local ROT_STYLE_TO_GLOW = {
        pixel = 1,
        shape = 2,
        button = 3,
        autocast = 4,
        gcd = 5,
        modern = 6,
        classic = 7,
    }

    local function _rotConfig()
        local profile = ECME.db and ECME.db.profile
        return profile and profile.cdmBars
    end

    local function _rotCVarOn()
        -- User can force-hide via our own toggle, overriding Blizzard's CVar
        local conf = _rotConfig()
        if conf and conf.hideRotationHelper then
            return false
        end
        return GetCVarBool and GetCVarBool("assistedCombatHighlight")
    end

    local function _rotCreateHighlight(iconTex)
        local success, hf =
            pcall(CreateFrame, "Frame", nil, iconTex, "ActionBarButtonAssistedCombatHighlightTemplate")
        if not success or not hf then
            return nil
        end
        hf:SetAllPoints()
        -- Sit above everything on the icon: Blizzard's cooldown swipe, our border frame, our glowOverlay (+6), and any proc alert frames. +15 clears them all with margin.
        hf:SetFrameLevel(iconTex:GetFrameLevel() + 15)
        hf:Hide()
        if hf.Flipbook and hf.Flipbook.Anim then
            hf.Flipbook.Anim:Play()
            hf.Flipbook.Anim:Stop()
        end
        return hf
    end

    local function _rotCreateCustom(iconTex)
        local overlayFrame = CreateFrame("Frame", nil, iconTex)
        overlayFrame:SetFrameLevel(iconTex:GetFrameLevel() + 15)
        overlayFrame:SetAlpha(0)
        return overlayFrame
    end

    local function _rotSolidBorder(overlayFrame, thickness, red, green, blue)
        local tbl = overlayFrame._rotSolid
        if not tbl then
            tbl = {}
            for index = 1, 4 do
                tbl[index] = overlayFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            end
            tbl[1]:SetPoint("TOPLEFT")
            tbl[1]:SetPoint("TOPRIGHT")
            tbl[2]:SetPoint("BOTTOMLEFT")
            tbl[2]:SetPoint("BOTTOMRIGHT")
            tbl[3]:SetPoint("TOPLEFT")
            tbl[3]:SetPoint("BOTTOMLEFT")
            tbl[4]:SetPoint("TOPRIGHT")
            tbl[4]:SetPoint("BOTTOMRIGHT")
            overlayFrame._rotSolid = tbl
        end
        local px = SnapForScale(thickness)
        tbl[1]:SetHeight(px)
        tbl[2]:SetHeight(px)
        tbl[3]:SetWidth(px)
        tbl[4]:SetWidth(px)
        for index = 1, 4 do
            tbl[index]:SetColorTexture(red, green, blue, 1)
            tbl[index]:Show()
        end
    end

    local function _rotHideSolid(overlayFrame)
        local tbl = overlayFrame and overlayFrame._rotSolid
        if not tbl then
            return
        end
        for index = 1, 4 do
            tbl[index]:Hide()
        end
    end

    local function _rotResolveColor(conf)
        local mode = conf and conf.rotationAssistColorMode or "default"
        if mode == "class" then
            local color = CludesUI.GetClassColor(CludesUI._playerClass)
            if color then
                return color.r, color.g, color.b
            end
        elseif mode == "custom" then
            return conf.rotationAssistColorR or 1,
                conf.rotationAssistColorG or 0,
                conf.rotationAssistColorB or 0
        end
        -- Default: no tint request, like every other glow site (gold for the drawn
        -- styles via StartNativeGlow, the atlas's own look for FlipBooks).
        return nil
    end

    local function _rotHide(iconTex)
        local rfc = iconTex and _ecmeFC[iconTex]
        local hf = rfc and rfc.rotationHighlight
        if hf then
            if hf.Flipbook and hf.Flipbook.Anim then
                hf.Flipbook.Anim:Stop()
            end
            hf:Hide()
        end
        local custom = rfc and rfc.rotationCustomHighlight
        if custom then
            StopNativeGlow(custom)
            _rotHideSolid(custom)
            custom._rotCfgKey = nil
        end
    end

    local function _rotShow(iconTex)
        if not iconTex then
            return
        end
        local rfc = FC(iconTex)
        local conf = _rotConfig()
        local style = conf and conf.rotationAssistStyle or "blizzard"
        if style ~= "solid" and not ROT_STYLE_TO_GLOW[style] then
            style = "blizzard"
        end

        if style ~= "blizzard" then
            local hf0 = rfc.rotationHighlight
            if hf0 then
                if hf0.Flipbook and hf0.Flipbook.Anim then
                    hf0.Flipbook.Anim:Stop()
                end
                hf0:Hide()
            end
            local overlayFrame = rfc.rotationCustomHighlight
            if not overlayFrame then
                overlayFrame = _rotCreateCustom(iconTex)
                rfc.rotationCustomHighlight = overlayFrame
            end
            local outset = conf.rotationAssistOutset or 1
            if outset < 0 then
                outset = 0
            elseif outset > 12 then
                outset = 12
            end
            overlayFrame:ClearAllPoints()
            overlayFrame:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -outset, outset)
            overlayFrame:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", outset, -outset)
            overlayFrame:SetFrameLevel(iconTex:GetFrameLevel() + 15)
            local thickness = conf.rotationAssistThickness or 3
            if thickness < 1 then
                thickness = 1
            elseif thickness > 8 then
                thickness = 8
            end
            local cr, cg, callback = _rotResolveColor(conf)
            local glowStyle = ROT_STYLE_TO_GLOW[style]
            -- Pixel Glow lines/speed/background (unset = the engine defaults).
            local lines, speed = conf.rotationAssistLines or 8, conf.rotationAssistSpeed or 4
            local bgc = conf.rotationAssistBackground and conf.rotationAssistBackgroundColor
            -- One reused key table (this runs on every suggestion update in combat).
            local kt = mod._rotKeyScratch
            if not kt then
                kt = {}
                mod._rotKeyScratch = kt
            end
            kt[1], kt[2], kt[3], kt[4], kt[5], kt[6], kt[7] =
                style, cr or -1, cg or -1, callback or -1, thickness, outset, glowStyle or 0
            kt[8], kt[9], kt[10] = lines, speed, conf.rotationAssistBackground and 1 or 0
            kt[11], kt[12], kt[13] = bgc and bgc.r or 0, bgc and bgc.g or 0, bgc and bgc.b or 0
            local cfgKey = table.concat(kt, ":", 1, 13)
            if overlayFrame._rotCfgKey ~= cfgKey or not overlayFrame._glowActive then
                overlayFrame._rotCfgKey = cfgKey
                if style == "solid" then
                    StopNativeGlow(overlayFrame)
                    _rotSolidBorder(overlayFrame, thickness, cr or 1.0, cg or 0.788, callback or 0.137)
                    overlayFrame._glowActive = true
                    overlayFrame:SetAlpha(1)
                else
                    _rotHideSolid(overlayFrame)
                    local wid = (iconTex:GetWidth() or 36) + outset * 2
                    local hgt = (iconTex:GetHeight() or 36) + outset * 2
                    StartNativeGlow(overlayFrame, glowStyle, cr, cg, callback, {
                        N = lines,
                        th = thickness,
                        period = speed,
                        bg = conf.rotationAssistBackground and {
                            r = (bgc and bgc.r) or 0,
                            g = (bgc and bgc.g) or 0,
                            b = (bgc and bgc.b) or 0,
                        } or nil,
                        width = wid,
                        height = hgt,
                    })
                end
            end
            return
        end

        local custom = rfc.rotationCustomHighlight
        if custom then
            StopNativeGlow(custom)
            _rotHideSolid(custom)
            custom._rotCfgKey = nil
        end
        local hf = rfc.rotationHighlight
        if not hf then
            hf = _rotCreateHighlight(iconTex)
            if not hf then
                return
            end
            rfc.rotationHighlight = hf
        end
        if hf.Flipbook then
            local wid = iconTex:GetWidth() or 36
            local hgt = iconTex:GetHeight() or 36
            local ox = wid * ROT_GLOW_RATIO
            local oy = hgt * ROT_GLOW_RATIO
            hf.Flipbook:ClearAllPoints()
            hf.Flipbook:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -ox, oy)
            hf.Flipbook:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", ox, -oy)
        end
        hf:Show()
        if hf.Flipbook and hf.Flipbook.Anim then
            hf.Flipbook.Anim:Play()
            if not mod._rotationInCombat then
                hf.Flipbook.Anim:Stop()
            end
        end
    end

    local function UpdateRotationHighlightsNow()
        if not _rotCVarOn() then
            for iconTex in pairs(mod._rotationGlowedIcons) do
                _rotHide(iconTex)
                mod._rotationGlowedIcons[iconTex] = nil
            end
            return
        end

        local suggestedSpell = C_AssistedCombat
            and C_AssistedCombat.GetNextCastSpell
            and C_AssistedCombat.GetNextCastSpell()
        if type(suggestedSpell) ~= "number" or (issecretvalue and issecretvalue(suggestedSpell)) then
            suggestedSpell = nil
        end

        local newSet = _rotSpareSet
        wipe(newSet)
        if suggestedSpell then
            for _, iconTex in ipairs(CDMIconsForSpell(suggestedSpell, _rotMatched)) do
                _rotShow(iconTex)
                newSet[iconTex] = true
            end
        end

        local oldSet = mod._rotationGlowedIcons
        for iconTex in pairs(oldSet) do
            if not newSet[iconTex] then
                _rotHide(iconTex)
            end
        end
        _rotSpareSet = oldSet
        mod._rotationGlowedIcons = newSet
    end

    -- Coalesce Blizzard's overlapping assisted-combat callbacks and bar rebuilds
    -- into one pass on the next frame. A suggestion change normally fires both an
    -- EventRegistry callback and UpdateAllAssistedHighlightFramesForSpell; running
    -- the full icon scan for each notification needlessly doubles the hot path.
    local _rotDirty = CreateFrame("Frame")
    _rotDirty:Hide()
    _rotDirty:SetScript("OnUpdate", function(self)
        self:Hide()
        UpdateRotationHighlightsNow()
    end)

    local function QueueRotationHighlightUpdate()
        _rotDirty:Show()
    end
    mod.UpdateRotationHighlights = QueueRotationHighlightUpdate

    local function _rotSyncCombat()
        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
        mod._rotationInCombat = inCombat and true or false
        for iconTex in pairs(mod._rotationGlowedIcons) do
            local rfc2 = iconTex and _ecmeFC[iconTex]
            local hf = rfc2 and rfc2.rotationHighlight
            if hf and hf:IsShown() and hf.Flipbook and hf.Flipbook.Anim then
                if mod._rotationInCombat then
                    if not hf.Flipbook.Anim:IsPlaying() then
                        hf.Flipbook.Anim:Play()
                    end
                else
                    if hf.Flipbook.Anim:IsPlaying() then
                        hf.Flipbook.Anim:Stop()
                    end
                end
            end
        end
    end
    mod._syncRotationCombatState = _rotSyncCombat

    function mod.InstallRotationHook()
        if mod._rotationHookInstalled then
            return
        end
        mod._rotationHookInstalled = true

        _rotSyncCombat()

        if EventRegistry and EventRegistry.RegisterCallback then
            EventRegistry:RegisterCallback("AssistedCombatManager.OnAssistedHighlightSpellChange", function()
                QueueRotationHighlightUpdate()
            end, "ECME_CDM_RotationHelper")
            -- Clear highlights if the user flips Blizzard's CVar off at runtime.
            EventRegistry:RegisterCallback("AssistedCombatManager.OnSetUseAssistedHighlight", function()
                QueueRotationHighlightUpdate()
            end, "ECME_CDM_RotationHelper_CVar")
        end

        if AssistedCombatManager and AssistedCombatManager.UpdateAllAssistedHighlightFramesForSpell then
            hooksecurefunc(AssistedCombatManager, "UpdateAllAssistedHighlightFramesForSpell", function()
                QueueRotationHighlightUpdate()
            end)
        end

        -- Re-run after bar rebuilds so the shine follows icon recycling.
        if mod.CollectAndReanchor then
            hooksecurefunc(mod, "CollectAndReanchor", QueueRotationHighlightUpdate)
        end

        QueueRotationHighlightUpdate()
    end
end

-- Show Item Count "Out of Combat" mode: re-run the icon restyle for bars using it whenever combat starts or ends (the gate inside the restyle reads the event-tracked combat flag). No-ops instantly when no bar uses the mode.
function mod.RefreshItemCountOOCBars()
    local profile = ECME.db and ECME.db.profile
    local barList = profile and profile.cdmBars and profile.cdmBars.bars
    if not barList or not mod.RefreshCDMIconAppearance then
        return
    end
    local any
    for _, edge in ipairs(barList) do
        if edge.itemCountOOC and edge.key then
            mod.RefreshCDMIconAppearance(edge.key)
            any = true
        end
    end
    if any then
        mod._RefreshNativeHealthstoneCounts()
    end
end

-- TAINT LAW (field-proven 2026-08-31, 24x error burst in the field): NEVER
-- write ANY field on a Blizzard CooldownViewer item frame, not even a key
-- Blizzard itself owns (spellOutOfRange), and never call its paint methods
-- from our execution. The written value is tainted; Blizzard's refresh
-- chains read it MID-EXECUTION and the taint poisons everything downstream:
-- forbidden secure caches (CheckAllowOnCooldownGeneric dataCache), secret
-- boolean fields (allowOnCooldownAlert), and map registrations made inside
-- the chain, which then convert every later event dispatch on the viewer
-- into tainted execution. A stale-range repaint is never worth that. The
-- range-on-override-swap staleness it replaced is cosmetic, and is repainted
-- below WITHIN this law: our own texture only, no frame field, no paint call.

-- Blizzard arms the range check on the BASE spell, so while an override is up the
-- icon tracks the wrong spell's range. Repainted on fd.tex and the side table,
-- never the frame. The hook RE-POLLS instead of replaying a stored answer: it
-- fires on every Blizzard repaint, including the one their own range event drives,
-- so walking back into range clears the tint without a second event of our own. A
-- secret or unknown answer leaves their colour alone. Cleared to nil when no
-- override is live, since Blizzard's own check is correct for the base spell.
-- On ns.* because the main chunk is at Lua 5.1's 200-local cap.
function mod.ApplyOverrideRangeTint(iconTex, overrideSpellID)
    local fd = _getFD(iconTex)
    local texture = fd and fd.tex
    local C = CooldownViewerConstants
    if not (texture and C) then
        return
    end
    -- Live-override count, kept on the nil<->value transitions of the ONLY
    -- writer of _oorSpellID: RepaintOverrideRange gates its whole icon walk on
    -- it, so the event dispatches Blizzard's own base-spell registrations
    -- produce (nearly all of them, for nearly every player) cost one integer
    -- read instead of a full bar scan.
    if (fd._oorSpellID ~= nil) ~= (overrideSpellID ~= nil) then
        mod._oorLiveCount = (mod._oorLiveCount or 0) + (overrideSpellID and 1 or -1)
    end
    fd._oorSpellID = overrideSpellID
    if not fd._oorHooked then
        fd._oorHooked = true
        local guard = false
        hooksecurefunc(texture, "SetVertexColor", function()
            local spellRef = fd._oorSpellID
            if guard or not spellRef then
                return
            end
            local region = C_Spell.IsSpellInRange(spellRef)
            if issecretvalue and issecretvalue(region) then
                return
            end
            if region ~= false then
                return
            end
            guard = true
            texture:SetVertexColor(C.ITEM_NOT_IN_RANGE_COLOR:GetRGBA())
            guard = false
        end)
    end
    -- Repaint once now: the hook only rides Blizzard's own writes, and the swap
    -- that brought us here does not produce one.
    local inRange = overrideSpellID and C_Spell.IsSpellInRange(overrideSpellID)
    if issecretvalue and issecretvalue(inRange) then
        return
    end
    if inRange == false then
        texture:SetVertexColor(C.ITEM_NOT_IN_RANGE_COLOR:GetRGBA())
        return
    end
    local spellRef = overrideSpellID or iconTex.rangeCheckSpellID
    if not spellRef then
        return
    end
    local usable, notEnoughMana = C_Spell.IsSpellUsable(spellRef)
    if issecretvalue and (issecretvalue(usable) or issecretvalue(notEnoughMana)) then
        return
    end
    if usable then
        texture:SetVertexColor(C.ITEM_USABLE_COLOR:GetRGBA())
    elseif notEnoughMana then
        texture:SetVertexColor(C.ITEM_NOT_ENOUGH_MANA_COLOR:GetRGBA())
    else
        texture:SetVertexColor(C.ITEM_NOT_USABLE_COLOR:GetRGBA())
    end
end

-- Blizzard arms its check on the BASE spell only, so a melee base with a 15yd
-- override never dispatches when you cross 15yd. Arming the override id closes that.
--
-- The registration is per SPELL, not per caller, and an override can be a CDM entry
-- in its own right (Hammer of Wrath overrides Judgment and is also its own icon), so
-- an id Blizzard holds is left alone in both directions -- re-checked at disarm time,
-- since a spell can become theirs while ours is armed.
function mod.BlizzardArmsRange(spellId)
    for _, icons in pairs(cdmBarIcons) do
        for _, iconTex in ipairs(icons) do
            if iconTex.rangeCheckSpellID == spellId then
                return true
            end
        end
    end
    return false
end

function mod.ArmOverrideRange(baseSpellID, overrideSpellID)
    local armed = mod._oorArmed
    if not armed then
        armed = {}
        mod._oorArmed = armed
    end
    local previous = armed[baseSpellID]
    if previous == overrideSpellID then
        return
    end
    if previous then
        -- Also left armed while a custom spell icon holds it (CdmHooks, Out of Range Coloring).
        if not mod.BlizzardArmsRange(previous) and not mod.CustomSpellRangeHolds(previous) then
            C_Spell.EnableSpellRangeCheck(previous, false)
        end
        armed[baseSpellID] = nil
    end
    if overrideSpellID and not mod.BlizzardArmsRange(overrideSpellID) then
        C_Spell.EnableSpellRangeCheck(overrideSpellID, true)
        armed[baseSpellID] = overrideSpellID
    end
end

-- Every registration dropped at once (spec change, logout): a leaked one costs a
-- dispatch we ignore, but they would accumulate across a session of swaps.
function mod.DisarmOverrideRanges()
    local armed = mod._oorArmed
    if not armed then
        return
    end
    for base, shade in pairs(armed) do
        if not mod.BlizzardArmsRange(shade) and not mod.CustomSpellRangeHolds(shade) then
            C_Spell.EnableSpellRangeCheck(shade, false)
        end
        armed[base] = nil
    end
    -- The tracked ids go with the registrations ("the new spec's overrides
    -- re-arm on their own events"): a value left behind would keep that icon's
    -- hook polling a dead spell and hold the repaint gate open. Also what
    -- keeps the live count exact across spec changes.
    for _, icons in pairs(cdmBarIcons) do
        for _, iconTex in ipairs(icons) do
            local fd = _getFD(iconTex)
            if fd and fd._oorSpellID ~= nil then
                fd._oorSpellID = nil
            end
        end
    end
    mod._oorLiveCount = 0
end

-- SPELL_RANGE_CHECK_UPDATE. Keyed off the icon's own stored override id rather than
-- our armed set, so it still repaints for an override Blizzard arms itself. The
-- payload's isInRange is ignored in favour of ApplyOverrideRangeTint's own poll,
-- which already guards a secret answer. Falls through immediately for the base-spell
-- registrations Blizzard makes, which is nearly every dispatch.
function mod.RepaintOverrideRange(spellId)
    -- No icon holds a live override: nothing here could match. Reads only our
    -- own counter, so it runs before any payload value is touched.
    if (mod._oorLiveCount or 0) <= 0 then
        return
    end
    if type(spellId) ~= "number" then
        return
    end
    if issecretvalue and issecretvalue(spellId) then
        return
    end
    for _, icons in pairs(cdmBarIcons) do
        for _, iconTex in ipairs(icons) do
            local fd = _getFD(iconTex)
            if fd and fd._oorSpellID == spellId then
                mod.ApplyOverrideRangeTint(iconTex, spellId)
            end
        end
    end
end

-- rangeCheckSpellID is READ, never written: the law is about writes.
function mod.ResyncCdmRange(baseSpellID, overrideSpellID)
    -- Secret payload fails open, before any truthiness test or comparison
    -- touches it: same guard the action bar dispatcher puts on this event.
    if issecretvalue and (issecretvalue(baseSpellID) or issecretvalue(overrideSpellID)) then
        return
    end
    if not (baseSpellID and C_Spell and C_Spell.IsSpellInRange) then
        return
    end
    -- nil once the override lapses, which hands the icon back to Blizzard: their
    -- own check is armed on the base spell and is right again from that moment.
    local liveOverride = (overrideSpellID and overrideSpellID ~= baseSpellID) and overrideSpellID or nil
    mod.ArmOverrideRange(baseSpellID, liveOverride)
    for _, icons in pairs(cdmBarIcons) do
        for _, iconTex in ipairs(icons) do
            if iconTex.rangeCheckSpellID == baseSpellID then
                mod.ApplyOverrideRangeTint(iconTex, liveOverride)
            end
        end
    end
end

Inner.broken = false
