if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewBuffs.lua
--
--  The preview buff ticker (test mode) and the refresh of the preview aura
--  visuals.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local C_Timer = C_Timer

local PixelSnap = mod._internals.PixelSnap

local previewFrames, PvActive = Inner.previewFrames, Inner.PvActive
local PvAuraReanchorFrame, PvFrames = Inner.PvAuraReanchorFrame, Inner.PvFrames
local PvSettings, StartPvAuraTicker = Inner.PvSettings, Inner.StartPvAuraTicker
local StopPvAuraTicker = Inner.StopPvAuraTicker

local previewActive = false
Inner.previewActiveSetters[#Inner.previewActiveSetters + 1] = function(val)
    previewActive = val
end

-------------------------------------------------------------------------------
--  Preview Buff Ticker (test mode only: cycles configured buffs across frames)
-------------------------------------------------------------------------------
mod._pvBuffTicker = nil
mod._pvBuffAssignments = {}

local function GetConfiguredBuffSpells()
    -- The Buff Manager groups the live raid frames render for the player's
    -- spec (every bucket it draws from, Show In and per-spec disables applied,
    -- spell unions resolved), at the live frames' size.
    local indicators = mod.BM2_SpecIndicators and mod.BM2_SpecIndicators("raid")
    if not indicators then
        return {}
    end
    local iscale = mod._bmScale or 1
    local spells = {}
    local seen = {}
    for _, indicator in ipairs(indicators) do
        if indicator.enabled and indicator.spells and (indicator.type == "icon" or indicator.type == "square") then
            for _, spellRef in ipairs(indicator.spells) do
                if not seen[spellRef] then
                    seen[spellRef] = true
                    local iconTex
                    if indicator.type == "icon" then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellRef)
                        iconTex = details and details.iconID or 136243
                    end
                    spells[#spells + 1] = {
                        id = spellRef,
                        icon = iconTex,
                        indType = indicator.type,
                        color = (indicator.spellColors and indicator.spellColors[spellRef]) or indicator.color,
                        size = mod.RFC_BmSize(indicator, iscale),
                        position = indicator.position or "TOPLEFT",
                        offsetX = indicator.offsetX or 0,
                        offsetY = indicator.offsetY or 0,
                        growDirection = indicator.growDirection or "RIGHT",
                        spacing = indicator.spacing or 0,
                        indicator = indicator,
                        permanent = mod.BM_PREVIEW_NO_DURATION and mod.BM_PREVIEW_NO_DURATION[spellRef],
                    }
                end
            end
        end
    end
    return spells
end

mod.PvBuffAnchor = function(iconTex, frame, spellInfo, prevIcon)
    if not frame._health then
        return
    end
    iconTex:SetSize(spellInfo.size, spellInfo.size)
    iconTex:ClearAllPoints()
    if prevIcon then
        -- Chain from previous icon using growth direction
        local spc = PixelSnap(spellInfo.spacing or 0)
        local grow = spellInfo.growDirection or "RIGHT"
        if grow == "RIGHT" then
            iconTex:SetPoint("LEFT", prevIcon, "RIGHT", spc, 0)
        elseif grow == "LEFT" then
            iconTex:SetPoint("RIGHT", prevIcon, "LEFT", -spc, 0)
        elseif grow == "UP" then
            iconTex:SetPoint("BOTTOM", prevIcon, "TOP", 0, spc)
        elseif grow == "DOWN" then
            iconTex:SetPoint("TOP", prevIcon, "BOTTOM", 0, -spc)
        end
    else
        local place = spellInfo.position and spellInfo.position:upper() or "BOTTOMLEFT"
        local ox, oy = spellInfo.offsetX or 0, spellInfo.offsetY or 0
        iconTex:SetPoint(place, mod.RF_AnchorHost(frame._health, PvSettings()), place, ox, oy)
    end
end

mod.PvBuffApply = function(spellInfo, frameIndex, slot)
    local frame = previewFrames[frameIndex]
    if not frame or not frame._pvBuffs then
        return
    end
    local iconTex = frame._pvBuffs[slot]
    if not iconTex then
        return
    end

    if spellInfo.indType == "icon" then
        iconTex._tex:SetTexture(spellInfo.icon or 136243)
        iconTex._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex._tex:SetVertexColor(1, 1, 1)
    else
        local color = spellInfo.color or { r = 0.30, g = 0.79, b = 0.94 }
        iconTex._tex:SetColorTexture(color.r, color.g, color.b, 1)
        iconTex._tex:SetTexCoord(0, 1, 0, 1)
    end

    mod.PvBuffAnchor(iconTex, frame, spellInfo)

    -- Border
    mod.RFC_PreviewAuraBorder(iconTex, iconTex._borderFrame, spellInfo.indicator, "indBorder")

    -- Cooldown
    if iconTex._cooldown then
        if not spellInfo.permanent then
            local dur = 15
            local startTime = GetTime() - math.random() * 10
            iconTex._cooldown:SetCooldown(startTime, dur)
            iconTex._cooldown:SetDrawSwipe(true)
            iconTex._cooldown:SetHideCountdownNumbers(true)
            iconTex._cooldown:Show()
        else
            iconTex._cooldown:Hide()
        end
    end

    iconTex:Show()
end

mod.PvBuffTick = function()
    if not previewActive or not mod._testBuffsVisible then
        return
    end
    local nowTime = GetTime()
    local PREVIEW_COUNT2 = #previewFrames

    -- Loop cooldown swipes on player frame buffs (permanent, but swipe should cycle)
    local playerF = previewFrames[1]
    if playerF and playerF._pvBuffs then
        for _, details in pairs(mod._pvBuffAssignments) do
            if details.permanent and details.frameIndex == 1 and not details.spellInfo.permanent then
                if not details.cdEndTime or nowTime >= details.cdEndTime then
                    local ic = playerF._pvBuffs[details.slot]
                    if ic and ic._cooldown then
                        local dur = 12 + math.random() * 8 -- 12-20s
                        ic._cooldown:SetCooldown(nowTime, dur)
                        details.cdEndTime = nowTime + dur
                    end
                end
            end
        end
    end

    -- Expire and reassign
    for spellRef, details in pairs(mod._pvBuffAssignments) do
        if not details.permanent and details.expTime and details.expTime <= nowTime then
            -- Hide old
            local frame = previewFrames[details.frameIndex]
            if frame and frame._pvBuffs and frame._pvBuffs[details.slot] then
                local ic = frame._pvBuffs[details.slot]
                ic:Hide()
                if ic._cooldown then
                    ic._cooldown:SetCooldown(0, 0)
                end
            end
            -- Pick new frame (skip frame 1 = player)
            local newFi = math.random(2, PREVIEW_COUNT2)
            local tries = 0
            while newFi == details.frameIndex and tries < 5 do
                newFi = math.random(2, PREVIEW_COUNT2)
                tries = tries + 1
            end
            details.frameIndex = newFi
            details.expTime = nowTime + 15
            mod.PvBuffApply(details.spellInfo, newFi, details.slot)
        end
    end
end

mod.StartPvBuffTicker = function()
    if mod._pvBuffTicker then
        return
    end
    wipe(mod._pvBuffAssignments)

    local spells = GetConfiguredBuffSpells()
    if #spells == 0 then
        return
    end

    local nowTime = GetTime()
    local PREVIEW_COUNT2 = #previewFrames
    local playerSlot = 0

    -- Player frame (1): show all buffs, max 3 per position, chained
    local posCounts = {} -- [position] = count
    local posLastIcon = {} -- [position] = last icon frame for chaining
    local playerF = previewFrames[1]
    if playerF and playerF._pvBuffs then
        for _, sp in ipairs(spells) do
            local place = sp.position
            posCounts[place] = (posCounts[place] or 0) + 1
            if posCounts[place] <= 3 then
                playerSlot = playerSlot + 1
                if playerSlot > 8 then
                    break
                end
                local previous = posLastIcon[place]
                mod.PvBuffApply(sp, 1, playerSlot)
                local iconTex = playerF._pvBuffs[playerSlot]
                if iconTex then
                    mod.PvBuffAnchor(iconTex, playerF, sp, previous)
                    posLastIcon[place] = iconTex
                end
                mod._pvBuffAssignments[sp.id .. ":p"] = {
                    spellInfo = sp,
                    frameIndex = 1,
                    slot = playerSlot,
                    expTime = nowTime + 99999,
                    permanent = true, -- always visible on player
                }
            end
        end
    end

    -- Other frames: spread spells across frames 2+, one each, cycling on expiry
    local frameSlotsUsed = {}
    for index, sp in ipairs(spells) do
        local fi = ((index - 1) % (PREVIEW_COUNT2 - 1)) + 2
        frameSlotsUsed[fi] = (frameSlotsUsed[fi] or 0) + 1
        local slot = frameSlotsUsed[fi]
        if slot > 4 then
            break
        end
        mod._pvBuffAssignments[sp.id] = {
            spellInfo = sp,
            frameIndex = fi,
            slot = slot,
            expTime = sp.permanent and (nowTime + 99999) or (nowTime + math.random(3, 15)),
            permanent = sp.permanent,
        }
        mod.PvBuffApply(sp, fi, slot)
    end

    mod._pvBuffTicker = C_Timer.NewTicker(0.5, mod.PvBuffTick)
end

mod.StopPvBuffTicker = function()
    if mod._pvBuffTicker then
        mod._pvBuffTicker:Cancel()
        mod._pvBuffTicker = nil
    end
    wipe(mod._pvBuffAssignments)
    for _, frame in ipairs(previewFrames) do
        if frame._pvBuffs then
            for _, ic in ipairs(frame._pvBuffs) do
                ic:Hide()
                if ic._cooldown then
                    ic._cooldown:SetCooldown(0, 0)
                end
            end
        end
    end
end

-- Restart: stop (instant clear) then start if any eyeball is on
local function RestartPvAuraTicker()
    StopPvAuraTicker()
    if PvActive() and (mod._defensivesPreviewVisible or mod._debuffsPreviewVisible) then
        StartPvAuraTicker()
    end
end
mod.RestartPvAuraTicker = RestartPvAuraTicker

-- Re-anchor + resize + re-border all active preview aura icons (settings changed, no icon swap)
-- Reads shared state via ns to stay under the 60-upvalue cap.
mod._PvAuraReanchorFrame = PvAuraReanchorFrame
mod.RefreshPvAuraVisuals = function()
    local s2 = PvSettings()
    if not s2 then
        return
    end
    local _pvFrames = PvFrames()
    local _reanchor = mod._PvAuraReanchorFrame
    local fp = (CludesUI.GetFontPath("raidFrames")) or "Fonts\\FRIZQT__.TTF"

    local dbZ = s2.debuffIconZoom or 0.08
    local defZ = s2.defIconZoom or 0.08
    local dbShowSwipe = s2.debuffShowSwipe ~= false
    local dbShowDurText = s2.debuffShowDurText
    local dbDtC = s2.debuffDurTextColor or { r = 1, g = 1, b = 1 }
    local dbDtSz = s2.debuffDurTextSize or 8
    local dbDtOX = s2.debuffDurTextOffsetX or 0
    local dbDtOY = s2.debuffDurTextOffsetY or 0
    local defShowSwipe = s2.defShowSwipe ~= false
    local defShowDurText = s2.defShowDurText
    local defDtC = s2.defDurTextColor or { r = 1, g = 1, b = 1 }
    local defDtSz = s2.defDurTextSize or 8
    local defDtOX = s2.defDurTextOffsetX or 0
    local defDtOY = s2.defDurTextOffsetY or 0
    local stc = s2.debuffStacksTextColor or { r = 1, g = 1, b = 1 }
    local sSz = s2.debuffStacksTextSize or 8
    local sOX = s2.debuffStacksOffsetX or 0
    local sOY = s2.debuffStacksOffsetY or 0

    for fi, frame in ipairs(_pvFrames) do
        if frame._pvDebuffs then
            for _, ic in ipairs(frame._pvDebuffs) do
                if ic:IsShown() then
                    ic:SetSize(mod.RFC_DebuffSize(s2), mod.RFC_DebuffSize(s2))
                    ic._tex:SetTexCoord(dbZ, 1 - dbZ, dbZ, 1 - dbZ)
                    mod.RFC_PreviewAuraBorder(ic, ic._borderFrame, s2, "debuffBorder")
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(dbShowSwipe)
                        ic._cooldown:SetHideCountdownNumbers(not dbShowDurText)
                        if dbShowDurText then
                            local cdText = ic._cooldown.GetCountdownFontString
                                and ic._cooldown:GetCountdownFontString()
                            if cdText then
                                CludesUI.ApplyIconTextFont(cdText, fp, dbDtSz, "raidFrames")
                                cdText:SetTextColor(dbDtC.r, dbDtC.g, dbDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", dbDtOX, dbDtOY)
                            end
                        end
                    end
                    if ic._count and ic._count:GetText() ~= "" then
                        CludesUI.ApplyIconTextFont(ic._count, fp, sSz, "raidFrames")
                        ic._count:SetTextColor(stc.r, stc.g, stc.b)
                        ic._count:ClearAllPoints()
                        ic._count:SetPoint("BOTTOMRIGHT", ic, "BOTTOMRIGHT", 1 + sOX, -1 + sOY)
                    end
                end
            end
            _reanchor(fi, "db")
        end
        if frame._pvDefs then
            for _, ic in ipairs(frame._pvDefs) do
                if ic:IsShown() then
                    ic:SetSize(s2.defSize or 22, s2.defSize or 22)
                    ic._tex:SetTexCoord(defZ, 1 - defZ, defZ, 1 - defZ)
                    mod.RFC_PreviewAuraBorder(ic, ic._borderFrame, s2, "defBorder")
                    if ic._cooldown then
                        ic._cooldown:SetDrawSwipe(defShowSwipe)
                        ic._cooldown:SetHideCountdownNumbers(not defShowDurText)
                        if defShowDurText then
                            local cdText = ic._cooldown.GetCountdownFontString
                                and ic._cooldown:GetCountdownFontString()
                            if cdText then
                                CludesUI.ApplyIconTextFont(cdText, fp, defDtSz, "raidFrames")
                                cdText:SetTextColor(defDtC.r, defDtC.g, defDtC.b)
                                cdText:ClearAllPoints()
                                cdText:SetPoint("CENTER", ic, "CENTER", defDtOX, defDtOY)
                            end
                        end
                    end
                end
            end
            _reanchor(fi, "def")
        end
    end
end

Inner.broken = false
