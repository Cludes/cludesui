if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\Profession.lua - Info Bar blocks: professions.
--
--  "profession" shows the two primary professions, "profession2" the
--  secondary ones (Cooking, Fishing, and First Aid on WoW Forever). Each is an
--  icon, its name (or rank/max) and, below max rank, a thin skill bar.
--  Left-click opens that profession; right-click opens the profession book
--  (primary) or lights a Basic Campfire (secondary). Hover lists every
--  profession of the block with its rank.
--
--  Each profession is a secure button, so the right-click works in combat
--  and the block's layout is fixed in combat: changes are drawn once combat
--  ends. The game sends the skill events often (SPELLS_CHANGED especially),
--  so a redraw happens only when a profession or a setting actually changed.
--
--  Settings (blockCfg.settings): textDisplay = "values" (rank/max instead of
--  the name); iconStyle = "wow" (the game's icons instead of ours);
--  showIcon (default on).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local floor, max = math.floor, math.max

local ART = mod.MEDIA .. "profession\\"

-- Skill line -> our icon in media\profession\.
local OUR_ICONS = {
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

local CAMPFIRE = 818 -- Basic Campfire, the secondary block's right-click
-- Secondary professions go by skill line, not by where GetProfessions puts
-- them (First Aid is not always sixth).
local SECONDARY_ORDER = { [185] = 1, [356] = 2, [129] = 3 } -- Cooking, Fishing, First Aid

local BAR_TRACK = { 0.15, 0.15, 0.15, 0.6 }

local function MakeBlock(blockCfg, slot, contentFrame, barCtx, secondary)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "TRADE_SKILL_DETAILS_UPDATE", "SPELLS_CHANGED", "SKILL_LINES_CHANGED" }

    local function Settings()
        return blockCfg.settings or {}
    end

    -- One row per profession the block can show; First Aid's only on Forever.
    local rows = { { data = {} }, { data = {} } }
    if secondary and CludesUI.IS_FOREVER then
        rows[3] = { data = {} }
    end

    -- Reads the professions into the rows (idx nil = not learned).
    local function Read(...)
        for _, row in ipairs(rows) do
            row.data.idx = nil
        end
        local count = secondary and select("#", ...) or 2
        for i = 1, count do
            local index = select(i, ...)
            if index then
                local name, iconTex, rank, maxRank, _, _, line = GetProfessionInfo(index)
                local row = rows[secondary and SECONDARY_ORDER[line] or i]
                if row then
                    local skinData = row.data
                    skinData.idx, skinData.name, skinData.icon, skinData.id = index, name or "", iconTex, line
                    skinData.rank, skinData.maxRank = rank or 0, maxRank or 0
                end
            end
        end
    end

    -- Everything the drawing depends on, as one string: equal = nothing to redraw.
    local function Fingerprint()
        local cfg = Settings()
        local parts = {
            tostring(cfg.textDisplay),
            tostring(cfg.iconStyle),
            tostring(cfg.showIcon),
            barCtx.IsVertical() and "V" or "H",
            barCtx.GetThickness(),
        }
        for _, row in ipairs(rows) do
            local skinData = row.data
            parts[#parts + 1] = skinData.idx
                    and table.concat({ skinData.idx, skinData.name, tostring(skinData.icon), skinData.id or 0, skinData.rank, skinData.maxRank }, ":")
                or "-"
        end
        return table.concat(parts, "|")
    end
    local drawn -- the fingerprint last drawn

    local function OpenProfession(skinData)
        if not skinData or not skinData.id or InCombatLockdown() then
            return
        end
        local open = C_TradeSkillUI
            and C_TradeSkillUI.GetBaseProfessionInfo
            and C_TradeSkillUI.GetBaseProfessionInfo()
        local frame = _G.ProfessionsFrame
        -- A second click on the open profession closes it.
        if open and open.professionID == skinData.id and frame and frame:IsShown() then
            C_TradeSkillUI.CloseTradeSkill()
        else
            C_TradeSkillUI.OpenTradeSkill(skinData.id)
        end
    end

    local function ShowTooltip(owner)
        mod.Tip_Begin(owner)
        local title = secondary and (SECONDARY_SKILLS or "Secondary Professions")
            or (TRADE_SKILLS or "Professions")
        mod.Tip_AddLine(title, 1, 1, 1)
        mod.Tip_AddLine(" ")
        for _, row in ipairs(rows) do
            local skinData = row.data
            if skinData.idx and skinData.name then
                local rank = CludesUI.COLOR_CODES.WHITE .. skinData.rank .. "|r / " .. skinData.maxRank
                mod.Tip_AddDouble(skinData.name, rank, 1, 1, 1, 1, 1, 1)
            end
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], L["OPEN_PROFESSION"], 1, 1, 1, 1, 1, 1)
        local right = secondary and L["START_CAMPFIRE"] or L["OPEN_PROFESSION_BOOK"]
        mod.Tip_AddDouble(L["RIGHT_CLICK"], right, 1, 1, 1, 1, 1, 1)
        mod.Tip_Show()
    end

    -- The secure buttons, made out of combat only.
    local built = false
    local function Build()
        if built then
            return
        end
        built = true
        for i, row in ipairs(rows) do
            local frame = CreateFrame(
                "Button",
                "CludesUIDataBarsProf" .. i .. "_" .. inst.key,
                contentFrame,
                "SecureActionButtonTemplate"
            )
            frame:SetSize(1, barCtx.GetThickness())
            frame:EnableMouse(true)
            frame:RegisterForClicks("AnyUp")
            frame:SetAttribute("useOnKeyDown", false)
            if secondary then
                frame:SetAttribute("*type2", "spell")
                frame:SetAttribute("*spell2", CAMPFIRE)
            elseif _G.ProfessionMicroButton then
                frame:SetAttribute("*type2", "click")
                frame:SetAttribute("*clickbutton2", _G.ProfessionMicroButton)
            end
            local skill = CreateFrame("StatusBar", nil, frame)
            skill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local track = skill:CreateTexture(nil, "BACKGROUND")
            track:SetAllPoints()
            row.frame, row.skill, row.track = frame, skill, track
            row.icon = frame:CreateTexture(nil, "OVERLAY")
            row.text = frame:CreateFontString(nil, "OVERLAY")
            K.AttachTextOffset(inst, row.text)

            -- HookScript, not SetScript: replacing OnClick would drop the
            -- secure handler that does the right-click.
            frame:HookScript("OnClick", function(_, mouseButton)
                if mouseButton == "LeftButton" then
                    OpenProfession(row.data)
                end
            end)
            frame:SetScript("OnEnter", function(self)
                local red, green, blue = mod.GetAccent()
                row.text:SetTextColor(red, green, blue, 1)
                row.icon:SetVertexColor(red, green, blue, 1)
                ShowTooltip(self)
            end)
            frame:SetScript("OnLeave", function(self)
                local red, green, blue = K.BlockColorOf(blockCfg)
                row.text:SetTextColor(red, green, blue, 1)
                -- The icon goes back to the icon colour, not the text's.
                local ir, ig, ib = K.IconColorOf(blockCfg)
                row.icon:SetVertexColor(ir, ig, ib, 1)
                mod.Tip_Hide(self)
            end)
        end
    end

    local function FillSkillBar(row)
        local skinData = row.data
        local red, green, blue = mod.GetAccent()
        row.skill:SetMinMaxValues(1, skinData.maxRank)
        row.skill:SetValue(skinData.rank)
        row.skill:SetStatusBarColor(red, green, blue, 1)
        row.track:SetColorTexture(BAR_TRACK[1], BAR_TRACK[2], BAR_TRACK[3], BAR_TRACK[4])
    end

    -- Draws one profession into its row's button; hides the button if not learned.
    local function DrawRow(row)
        local skinData, frame, iconTex, text, skill = row.data, row.frame, row.icon, row.text, row.skill
        if not skinData.idx then
            frame:Hide()
            return
        end
        local cfg = Settings()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local iconSize = fontSize + 8
        local valuesOnly = cfg.textDisplay == "values"
        local withBar = not valuesOnly and skinData.rank ~= skinData.maxRank
        local withIcon = cfg.showIcon ~= false

        -- Ours, unless the setting asks for the game's (or we have none).
        local ours = cfg.iconStyle ~= "wow" and OUR_ICONS[skinData.id]
        iconTex:SetTexture(ours and (ART .. ours .. ".png") or skinData.icon)
        if ours then
            iconTex:SetTexCoord(0, 1, 0, 1)
        else
            K.CropStockIcon(iconTex) -- the game's icons have a border baked in
        end
        if withIcon then
            iconTex:SetSize(iconSize, iconSize)
            iconTex:Show()
        else
            iconTex:Hide()
        end
        local ir, ig, ib = K.IconColorOf(blockCfg)
        iconTex:SetVertexColor(ir, ig, ib, 1)

        mod.SetFont(text, fontSize, barCtx.cfg)
        local red, green, blue = K.BlockColorOf(blockCfg)
        text:SetTextColor(red, green, blue, 1)
        text:SetText(valuesOnly and (skinData.rank .. "/" .. skinData.maxRank) or (skinData.name or ""))

        if barCtx.IsVertical() then
            -- Icon, text and bar stacked, centred in the bar's width.
            local width = K.VSlotW(inst)
            local inner = max(30, width - 8)
            local height = withIcon and (8 + iconSize + 2) or (8 + 2)
            iconTex:ClearAllPoints()
            iconTex:SetPoint("TOP", frame, "TOP", 0, -4)
            mod.SetWrappedText(text, inner, "CENTER")
            text:ClearAllPoints()
            if withIcon then
                text:SetPoint("TOP", iconTex, "BOTTOM", 0, -2)
            else
                text:SetPoint("TOP", frame, "TOP", 0, -4)
            end
            height = height + mod.SnapToPixelGrid(text:GetStringHeight())
            if withBar then
                FillSkillBar(row)
                skill:SetSize(inner, 3)
                skill:ClearAllPoints()
                skill:SetPoint("TOP", text, "BOTTOM", 0, -3)
                skill:Show()
                height = height + 3 + 3
            else
                skill:Hide()
            end
            frame:SetSize(width, max(height, barH))
            frame:Show()
            return
        end

        -- Across: icon on the left; text beside it, or text over the bar,
        -- the bar as wide as the text and level with the icon's bottom. With
        -- no icon the text and bar keep the icon's band.
        mod.ResetInlineText(text, "LEFT")
        iconTex:ClearAllPoints()
        iconTex:SetPoint("LEFT", frame, "LEFT", 0, 0)
        local half = iconSize / 2
        text:ClearAllPoints()
        if not withBar then
            skill:Hide()
            if withIcon then
                text:SetPoint("LEFT", iconTex, "RIGHT", K.ICON_GAP, 0)
            else
                text:SetPoint("LEFT", frame, "LEFT", 0, 0)
            end
        else
            skill:Show()
            if withIcon then
                text:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", K.ICON_GAP, 0)
            else
                text:SetPoint("TOPLEFT", frame, "LEFT", 0, half)
            end
            FillSkillBar(row)
            skill:SetSize(max(text:GetStringWidth(), 20), max(2, iconSize - fontSize - 3))
            skill:ClearAllPoints()
            if withIcon then
                skill:SetPoint("BOTTOMLEFT", iconTex, "BOTTOMRIGHT", K.ICON_GAP, 0)
            else
                skill:SetPoint("BOTTOMLEFT", frame, "LEFT", 0, -half)
            end
        end
        local lead = withIcon and (iconSize + K.ICON_GAP) or 0
        frame:SetSize(lead + max(text:GetStringWidth(), 20), barH)
        frame:Show()
    end

    -- Lays the learned professions out in a row (or a column), then sizes the block.
    local function Draw()
        local vertical = barCtx.IsVertical()
        local gap = vertical and 4 or 5
        local previous, extent = nil, 0
        for _, row in ipairs(rows) do
            DrawRow(row)
            if row.data.idx then
                local frame = row.frame
                frame:ClearAllPoints()
                if vertical then
                    if previous then
                        frame:SetPoint("TOP", previous, "BOTTOM", 0, -gap)
                    else
                        frame:SetPoint("TOP", contentFrame, "TOP", 0, 0)
                    end
                    extent = extent + frame:GetHeight()
                else
                    if previous then
                        frame:SetPoint("LEFT", previous, "RIGHT", gap, 0)
                    else
                        frame:SetPoint("LEFT", contentFrame, "LEFT", 0, 0)
                    end
                    extent = extent + frame:GetWidth()
                end
                if previous then
                    extent = extent + gap
                end
                previous = frame
            end
        end
        if vertical then
            contentFrame:SetSize(K.VSlotW(inst), max(extent, 1))
        else
            contentFrame:SetSize(max(extent, 1), barCtx.GetThickness())
        end
        contentFrame:SetShown(previous ~= nil)
        drawn = Fingerprint()
        K.MaybeRelayout(inst)
    end

    -- In combat the secure buttons cannot move: one pass runs when it ends.
    local function AfterCombat()
        if not inst._dead then
            inst:Refresh()
        end
    end

    -- A full pass (settings, the bar's layout): always draws.
    function inst:Refresh()
        if not built then
            return
        end
        if InCombatLockdown() then
            mod.DeferUntilOOC("prof:" .. inst.key, AfterCombat)
            return
        end
        Read(GetProfessions())
        Draw()
    end

    -- A skill event: draws only if a profession changed.
    inst.eventFrame = K.MakeEventFrame(inst, function(self)
        if not built then
            return
        end
        if InCombatLockdown() then
            mod.DeferUntilOOC("prof:" .. inst.key, AfterCombat)
            return
        end
        Read(GetProfessions())
        if Fingerprint() ~= drawn then
            Draw()
        end
    end)

    if InCombatLockdown() then
        mod.DeferUntilOOC("prof:build:" .. inst.key, function()
            if not inst._dead then
                Build()
                inst:Refresh()
            end
        end)
    else
        Build()
    end

    function inst:Enable()
        contentFrame:Show()
        K.RegisterInstEvents(self)
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if not built then
            return 40
        end
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight(), barCtx.GetThickness(), 50)
        end
        return max(contentFrame:GetWidth() or 80, 30)
    end

    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        for i, row in ipairs(rows) do
            if row.frame then
                K.ParkSecureFrame(row.frame, self.key .. "_prof" .. i)
            end
        end
        contentFrame:Hide()
    end

    return inst
end

mod.BlockFactories.profession = function(blockCfg, slot, contentFrame, barCtx)
    return MakeBlock(blockCfg, slot, contentFrame, barCtx, false)
end

mod.BlockFactories.profession2 = function(blockCfg, slot, contentFrame, barCtx)
    return MakeBlock(blockCfg, slot, contentFrame, barCtx, true)
end
