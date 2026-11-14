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
    for _, ind in ipairs(indicators) do
        if ind.enabled and ind.spells and (ind.type == "icon" or ind.type == "square") then
            for _, spellRef in ipairs(ind.spells) do
                if not seen[spellRef] then
                    seen[spellRef] = true
                    local iconTex
                    if ind.type == "icon" then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellRef)
                        iconTex = details and details.iconID or 136243
                    end
                    spells[#spells + 1] = {
                        id = spellRef,
                        icon = iconTex,
                        indType = ind.type,
                        color = (ind.spellColors and ind.spellColors[spellRef]) or ind.color,
                        size = mod.RFC_BmSize(ind, iscale),
                        position = ind.position or "TOPLEFT",
                        offsetX = ind.offsetX or 0,
                        offsetY = ind.offsetY or 0,
                        growDirection = ind.growDirection or "RIGHT",
                        spacing = ind.spacing or 0,
                        indicator = ind,
                        permanent = mod.BM_PREVIEW_NO_DURATION and mod.BM_PREVIEW_NO_DURATION[spellRef],
                    }
                end
            end
        end
    end
    return spells
end

mod.PvBuffAnchor = function(icon, f, spellInfo, prevIcon)
    if not f._health then
        return
    end
    icon:SetSize(spellInfo.size, spellInfo.size)
    icon:ClearAllPoints()
    if prevIcon then
        -- Chain from previous icon using growth direction
        local spc = PixelSnap(spellInfo.spacing or 0)
        local grow = spellInfo.growDirection or "RIGHT"
        if grow == "RIGHT" then
            icon:SetPoint("LEFT", prevIcon, "RIGHT", spc, 0)
        elseif grow == "LEFT" then
            icon:SetPoint("RIGHT", prevIcon, "LEFT", -spc, 0)
        elseif grow == "UP" then
            icon:SetPoint("BOTTOM", prevIcon, "TOP", 0, spc)
        elseif grow == "DOWN" then
            icon:SetPoint("TOP", prevIcon, "BOTTOM", 0, -spc)
        end
    else
        local place = spellInfo.position and spellInfo.position:upper() or "BOTTOMLEFT"
        local ox, oy = spellInfo.offsetX or 0, spellInfo.offsetY or 0
        icon:SetPoint(place, mod.RF_AnchorHost(f._health, PvSettings()), place, ox, oy)
    end
end

mod.PvBuffApply = function(spellInfo, frameIndex, slot)
    local f = previewFrames[frameIndex]
    if not f or not f._pvBuffs then
        return
    end
    local icon = f._pvBuffs[slot]
    if not icon then
        return
    end

    if spellInfo.indType == "icon" then
        icon._tex:SetTexture(spellInfo.icon or 136243)
        icon._tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon._tex:SetVertexColor(1, 1, 1)
    else
        local c = spellInfo.color or { r = 0.30, g = 0.79, b = 0.94 }
        icon._tex:SetColorTexture(c.r, c.g, c.b, 1)
        icon._tex:SetTexCoord(0, 1, 0, 1)
    end

    mod.PvBuffAnchor(icon, f, spellInfo)

    -- Border
    mod.RFC_PreviewAuraBorder(icon, icon._borderFrame, spellInfo.indicator, "indBorder")

    -- Cooldown
    if icon._cooldown then
        if not spellInfo.permanent then
            local dur = 15
            local startTime = GetTime() - math.random() * 10
            icon._cooldown:SetCooldown(startTime, dur)
            icon._cooldown:SetDrawSwipe(true)
            icon._cooldown:SetHideCountdownNumbers(true)
            icon._cooldown:Show()
        else
            icon._cooldown:Hide()
        end
    end

    icon:Show()
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
            local f = previewFrames[details.frameIndex]
            if f and f._pvBuffs and f._pvBuffs[details.slot] then
                local ic = f._pvBuffs[details.slot]
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
                local prev = posLastIcon[place]
                mod.PvBuffApply(sp, 1, playerSlot)
                local icon = playerF._pvBuffs[playerSlot]
                if icon then
                    mod.PvBuffAnchor(icon, playerF, sp, prev)
                    posLastIcon[place] = icon
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
    for idx, sp in ipairs(spells) do
        local fi = ((idx - 1) % (PREVIEW_COUNT2 - 1)) + 2
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
    for _, f in ipairs(previewFrames) do
        if f._pvBuffs then
            for _, ic in ipairs(f._pvBuffs) do
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

    for fi, f in ipairs(_pvFrames) do
        if f._pvDebuffs then
            for _, ic in ipairs(f._pvDebuffs) do
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
        if f._pvDefs then
            for _, ic in ipairs(f._pvDefs) do
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
