if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Blocks\Profession.lua
-- Profession block factories (primary and secondary).

local ADDON_NAME, mod = ...
local L = mod.L
local MEDIA = mod.MEDIA
local Keys = mod.BlockKit

-- Upvalues
local _G = _G
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local floor = math.floor
local upper = math.max

local ICON_GAP = Keys.ICON_GAP
local CONTENT_BASE = Keys.CONTENT_BASE
local InstKey = Keys.InstKey
local MakeEventFrame = Keys.MakeEventFrame
local RegisterInstEvents = Keys.RegisterInstEvents
local UnregisterInstEvents = Keys.UnregisterInstEvents
local VSlotW = Keys.VSlotW
local MaybeRelayout = Keys.MaybeRelayout
local AttachTextOffset = Keys.AttachTextOffset
local BlockColorOf = Keys.BlockColorOf
local IconColorOf = Keys.IconColorOf
local ParkSecureFrame = Keys.ParkSecureFrame

-------------------------------------------------------------------------------
--  PROFESSION (SECURE right-click passthrough to ProfessionMicroButton)
-------------------------------------------------------------------------------
-- Skill-line ID -> icon file in media\profession\ (one PNG per profession; filenames follow the art set's own stems, e.g. "blacksmith"/"engineer").
local profIcons = {
    [164] = "prof-blacksmith",
    [165] = "prof-leatherworking",
    [171] = "prof-alchemy",
    [182] = "prof-herbalism",
    [186] = "prof-mining",
    [202] = "prof-engineer",
    [333] = "prof-enchanting",
    [755] = "prof-jewelcrafting",
    [773] = "prof-inscription",
    [197] = "prof-tailoring",
    [393] = "prof-skinning",
    [185] = "prof-cooking",
    [356] = "prof-fishing",
    [129] = "prof-firstaid",
}

-- Shared builder for both profession blocks. secondary=false shows the two primary
-- professions (right-click = profession book); secondary=true also includes
-- First Aid when available (right-click = Basic Campfire, a secure spell cast).
local CAMPFIRE_SPELL = 818 -- Basic Campfire
local SECONDARY_SLOT = { [185] = 1, [356] = 2, [129] = 3 } -- Cooking, Fishing, First Aid
local function MakeProfessionBlock(blockCfg, slot, contentFrame, barCtx, secondary)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)
    instance.events = { "TRADE_SKILL_DETAILS_UPDATE", "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }

    local MEDIA_PROF = MEDIA .. "profession\\"
    local entries = { { data = {} }, { data = {} } }
    if secondary and CludesUI.IS_FOREVER then
        entries[3] = { data = {} }
    end

    local function BC()
        return barCtx.cfg
    end

    local built = false
    local function UpdateProfValues(...)
        for _, record in ipairs(entries) do
            record.data.idx = nil
        end
        -- Secondary professions are identified by skill line, not the position
        -- returned by GetProfessions (First Aid need not occupy the sixth slot).
        local total = secondary and select("#", ...) or 2
        for i = 1, total do
            local slotPos = select(i, ...)
            if slotPos then
                local name, glyph, rank, maxRank, _, _, ident = GetProfessionInfo(slotPos)
                local slotIndex = i
                if secondary then
                    slotIndex = SECONDARY_SLOT[ident]
                end
                -- First Aid (slot 3) has an entry only on WoW Forever.
                local record = slotIndex and entries[slotIndex]
                if record then
                    local payload = record.data
                    payload.idx = slotPos
                    payload.name, payload.icon, payload.id = name or "", glyph, ident
                    payload.rank, payload.maxRank = rank or 0, maxRank or 0
                end
            end
        end
    end

    local function StyleProfFrame(profData, profFrame, profIcon, profText, profBar, profBarBg)
        if not profData or not profData.idx then
            profFrame:Hide()
            return
        end
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = upper(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local iconSize = fontSize + 8
        local isSide = barCtx.IsVertical()
        local s = blockCfg.settings or {}
        local valuesOnly = s.textDisplay == "values"
        local showBar = not valuesOnly and profData.rank ~= profData.maxRank

        local iconTex = profData.icon
        local custom = (blockCfg.settings or {}).iconStyle ~= "wow" and profIcons[profData.id]
        if custom then
            iconTex = MEDIA_PROF .. custom .. ".png"
        end
        -- Show Icon (default ON): hidden drops the icon and its gap from the layout; the text/bar stack keeps the icon's vertical band.
        local showIcon = (blockCfg.settings or {}).showIcon ~= false
        profIcon:SetTexture(iconTex)
        -- The profession's stock icon (Blizzard style, or no custom art) has a baked-in border.
        if custom then
            profIcon:SetTexCoord(0, 1, 0, 1)
        else
            Keys.CropStockIcon(profIcon)
        end
        if showIcon then
            profIcon:SetSize(iconSize, iconSize)
            profIcon:Show()
        else
            profIcon:Hide()
        end
        local pbr, pbg, pbb = BlockColorOf(blockCfg)
        do
            local ir, ig, ib = IconColorOf(blockCfg)
            profIcon:SetVertexColor(ir, ig, ib, 1)
        end

        -- Font derives from CONTENT_BASE like every other block: the bar Height setting must never resize content.
        mod.SetFont(profText, fontSize, barCfg)
        profText:SetTextColor(pbr, pbg, pbb, 1)
        profText:SetText(valuesOnly and (profData.rank .. "/" .. profData.maxRank) or (profData.name or ""))

        if isSide then
            local frameW = VSlotW(instance)
            local innerW = upper(30, frameW - 8)
            local totalH = 8 + iconSize + 2

            profIcon:ClearAllPoints()
            profIcon:SetPoint("TOP", profFrame, "TOP", 0, -4)

            if not showIcon then
                totalH = 8 + 2
            end

            mod.SetWrappedText(profText, innerW, "CENTER")
            profText:ClearAllPoints()
            if showIcon then
                profText:SetPoint("TOP", profIcon, "BOTTOM", 0, -2)
            else
                profText:SetPoint("TOP", profFrame, "TOP", 0, -4)
            end
            totalH = totalH + mod.SnapToPixelGrid(profText:GetStringHeight())

            if showBar then
                local ar, ag, ab = mod.GetAccent()
                local bH = 3
                profBar:Show()
                profBar:SetMinMaxValues(1, profData.maxRank)
                profBar:SetValue(profData.rank)
                profBar:SetStatusBarColor(ar, ag, ab, 1)
                profBarBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                profBar:SetSize(innerW, bH)
                profBar:ClearAllPoints()
                profBar:SetPoint("TOP", profText, "BOTTOM", 0, -3)
                totalH = totalH + 3 + bH
            else
                profBar:Hide()
            end

            profFrame:SetSize(frameW, upper(totalH, barH))
            profFrame:Show()
        else
            mod.ResetInlineText(profText, "LEFT")
            profIcon:ClearAllPoints()
            profIcon:SetPoint("LEFT", profFrame, "LEFT", 0, 0)

            -- Hidden icon: the stack anchors to the frame's LEFT center with the icon rect's half-band offsets, keeping vertical rhythm flush left.
            local halfBand = iconSize / 2
            if not showBar then
                profBar:Hide()
                profText:ClearAllPoints()
                if showIcon then
                    profText:SetPoint("LEFT", profIcon, "RIGHT", ICON_GAP, 0)
                else
                    profText:SetPoint("LEFT", profFrame, "LEFT", 0, 0)
                end
            else
                profBar:Show()
                profText:ClearAllPoints()
                if showIcon then
                    profText:SetPoint("TOPLEFT", profIcon, "TOPRIGHT", ICON_GAP, 0)
                else
                    profText:SetPoint("TOPLEFT", profFrame, "LEFT", 0, halfBand)
                end
                local ar, ag, ab = mod.GetAccent()
                profBar:SetMinMaxValues(1, profData.maxRank)
                profBar:SetValue(profData.rank)
                profBar:SetStatusBarColor(ar, ag, ab, 1)
                profBarBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
                -- Icon left; text top-right; bar bottom-right, sharing the text's
                -- left edge and tracking TEXT width, bottom-aligned to the icon (same recipe as xprep).
                local textW = upper(profText:GetStringWidth(), 20)
                local bH = upper(2, iconSize - fontSize - 3)
                profBar:SetSize(textW, bH)
                profBar:ClearAllPoints()
                if showIcon then
                    profBar:SetPoint("BOTTOMLEFT", profIcon, "BOTTOMRIGHT", ICON_GAP, 0)
                else
                    profBar:SetPoint("BOTTOMLEFT", profFrame, "LEFT", 0, -halfBand)
                end
            end
            local textW = upper(profText:GetStringWidth(), 20)
            local effIcon = showIcon and (iconSize + ICON_GAP) or 0
            profFrame:SetSize(effIcon + textW, barH)
            profFrame:Show()
        end
    end

    local function OpenProf(prof)
        if not prof or not prof.id or InCombatLockdown() then
            return
        end
        local currInfo = C_TradeSkillUI
            and C_TradeSkillUI.GetBaseProfessionInfo
            and C_TradeSkillUI.GetBaseProfessionInfo()
        if
            currInfo
            and currInfo.professionID == prof.id
            and _G.ProfessionsFrame
            and _G.ProfessionsFrame:IsShown()
        then
            C_TradeSkillUI.CloseTradeSkill()
        elseif prof.id then
            C_TradeSkillUI.OpenTradeSkill(prof.id)
        end
    end

    local function Build()
        if built then
            return
        end
        built = true

        local function MakeProfFrame(name)
            local f = CreateFrame("Button", name, contentFrame, "SecureActionButtonTemplate")
            f:SetSize(1, barCtx.GetThickness())
            f:EnableMouse(true)
            f:RegisterForClicks("AnyUp")
            f:SetAttribute("useOnKeyDown", false)
            if secondary then
                -- Right-click = Basic Campfire, cast securely.
                f:SetAttribute("*type2", "spell")
                f:SetAttribute("*spell2", CAMPFIRE_SPELL)
            elseif _G.ProfessionMicroButton then
                f:SetAttribute("*type2", "click")
                f:SetAttribute("*clickbutton2", _G.ProfessionMicroButton)
            end
            local glyph = f:CreateTexture(nil, "OVERLAY")
            local textValue = f:CreateFontString(nil, "OVERLAY")
            local barFrame = CreateFrame("StatusBar", nil, f)
            barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local backdrop = barFrame:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            return f, glyph, textValue, barFrame, backdrop
        end

        for i, record in ipairs(entries) do
            record.frame, record.icon, record.text, record.bar, record.bg =
                MakeProfFrame("CludesUIDataBarsProf" .. i .. "_" .. instance.key)
            AttachTextOffset(instance, record.text)
            local widget = record.frame
            -- HookScript, NOT SetScript: SetScript("OnClick") would overwrite SecureActionButton_OnClick
            -- and kill the secure *clickbutton2 passthrough to ProfessionMicroButton (right-click).
            widget:HookScript("OnClick", function(_, btnFrame)
                if btnFrame == "LeftButton" then
                    OpenProf(record.data)
                end
            end)
            widget:SetScript("OnEnter", function(f)
                local txt, ic = record.text, record.icon
                local ar, ag, ab = mod.GetAccent()
                txt:SetTextColor(ar, ag, ab, 1)
                if ic then
                    ic:SetVertexColor(ar, ag, ab, 1)
                end
                mod.Tip_Begin(f)
                local titleText
                if secondary then
                    titleText = SECONDARY_SKILLS or "Secondary Professions"
                else
                    titleText = TRADE_SKILLS or "Professions"
                end
                mod.Tip_AddLine(titleText, 1, 1, 1)
                mod.Tip_AddLine(" ")
                local function AddLine(p)
                    if not p or not p.name then
                        return
                    end
                    mod.Tip_AddDouble(
                        p.name,
                        CludesUI.COLOR_CODES.WHITE .. p.rank .. "|r / " .. p.maxRank,
                        1,
                        1,
                        1,
                        1,
                        1,
                        1
                    )
                end
                for _, rowFrame in ipairs(entries) do
                    if rowFrame.data.idx then
                        AddLine(rowFrame.data)
                    end
                end
                mod.Tip_AddLine(" ")
                local rightLabel = L["OPEN_PROFESSION_BOOK"]
                if secondary then
                    rightLabel = L["START_CAMPFIRE"]
                end
                mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_PROFESSION"], 1, 1, 1, 1, 1, 1)
                mod.Tip_AddDouble(L["RIGHT_CLICK"], rightLabel, 1, 1, 1, 1, 1, 1)
                mod.Tip_Show()
            end)
            widget:SetScript("OnLeave", function(f)
                local txt, ic = record.text, record.icon
                local br, bgr, bb = BlockColorOf(blockCfg)
                txt:SetTextColor(br, bgr, bb, 1)
                -- Icon restores through ICON color (accent by default for professions), NOT the text color, which paints it white.
                if ic then
                    local ir, ig, ib = IconColorOf(blockCfg)
                    ic:SetVertexColor(ir, ig, ib, 1)
                end
                mod.Tip_Hide(f)
            end)
        end
    end

    if InCombatLockdown() then
        mod.DeferUntilOOC("edbbuild:" .. instance.key, function()
            if instance._dead then
                return
            end
            Build()
            instance:Refresh()
        end)
    else
        Build()
    end

    -- Built once: combat refreshes (Forever skill-ups) reuse the key and callback.
    local deferKey = "edbprof:" .. instance.key
    local function DeferredRefresh()
        if not instance._dead then
            instance:Refresh()
        end
    end

    function instance:Refresh()
        if not built then
            return
        end
        -- Secure frames: a refresh skipped in combat runs once on regen.
        if InCombatLockdown() then
            mod.DeferUntilOOC(deferKey, DeferredRefresh)
            return
        end
        UpdateProfValues(GetProfessions())
        local barH, gap = barCtx.GetThickness(), 5
        local isSide = barCtx.IsVertical()

        local previous, extent = nil, 0
        if isSide then
            gap = 4
        end
        for _, record in ipairs(entries) do
            local widget = record.frame
            StyleProfFrame(record.data, widget, record.icon, record.text, record.bar, record.bg)
            if record.data.idx then
                widget:ClearAllPoints()
                if isSide then
                    if previous then
                        widget:SetPoint("TOP", previous, "BOTTOM", 0, -gap)
                    else
                        widget:SetPoint("TOP", contentFrame, "TOP", 0, 0)
                    end
                    extent = extent + widget:GetHeight()
                else
                    if previous then
                        widget:SetPoint("LEFT", previous, "RIGHT", gap, 0)
                    else
                        widget:SetPoint("LEFT", contentFrame, "LEFT", 0, 0)
                    end
                    extent = extent + widget:GetWidth()
                end
                if previous then
                    extent = extent + gap
                end
                previous = widget
            end
        end
        if isSide then
            contentFrame:SetSize(VSlotW(instance), upper(extent, 1))
        else
            contentFrame:SetSize(upper(extent, 1), barH)
        end
        if previous then
            contentFrame:Show()
        else
            contentFrame:Hide()
        end
        MaybeRelayout(instance)
    end

    instance.eventFrame = MakeEventFrame(instance, function(self)
        self:Refresh()
    end)

    function instance:Enable()
        contentFrame:Show()
        RegisterInstEvents(self)
    end

    function instance:Disable()
        UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if not built then
            return 40
        end
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            local barH = barCtx.GetThickness()
            return upper(contentFrame:GetHeight(), barH, 50)
        end
        return upper(contentFrame:GetWidth() or 80, 30)
    end

    function instance:Destroy()
        self._dead = true
        UnregisterInstEvents(self)
        for i, record in ipairs(entries) do
            if record.frame then
                ParkSecureFrame(record.frame, self.key .. "_prof" .. i)
            end
        end
        contentFrame:Hide()
    end

    return instance
end

mod.BlockFactories.profession = function(blockCfg, slot, contentFrame, barCtx)
    return MakeProfessionBlock(blockCfg, slot, contentFrame, barCtx, false)
end

mod.BlockFactories.profession2 = function(blockCfg, slot, contentFrame, barCtx)
    return MakeProfessionBlock(blockCfg, slot, contentFrame, barCtx, true)
end
