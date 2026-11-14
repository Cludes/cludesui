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
                local name, icon, rank, maxRank, _, _, line = GetProfessionInfo(index)
                local row = rows[secondary and SECONDARY_ORDER[line] or i]
                if row then
                    local d = row.data
                    d.idx, d.name, d.icon, d.id = index, name or "", icon, line
                    d.rank, d.maxRank = rank or 0, maxRank or 0
                end
            end
        end
    end

    -- Everything the drawing depends on, as one string: equal = nothing to redraw.
    local function Fingerprint()
        local s = Settings()
        local parts = {
            tostring(s.textDisplay),
            tostring(s.iconStyle),
            tostring(s.showIcon),
            barCtx.IsVertical() and "V" or "H",
            barCtx.GetThickness(),
        }
        for _, row in ipairs(rows) do
            local d = row.data
            parts[#parts + 1] = d.idx
                    and table.concat({ d.idx, d.name, tostring(d.icon), d.id or 0, d.rank, d.maxRank }, ":")
                or "-"
        end
        return table.concat(parts, "|")
    end
    local drawn -- the fingerprint last drawn

    local function OpenProfession(d)
        if not d or not d.id or InCombatLockdown() then
            return
        end
        local open = C_TradeSkillUI
            and C_TradeSkillUI.GetBaseProfessionInfo
            and C_TradeSkillUI.GetBaseProfessionInfo()
        local frame = _G.ProfessionsFrame
        -- A second click on the open profession closes it.
        if open and open.professionID == d.id and frame and frame:IsShown() then
            C_TradeSkillUI.CloseTradeSkill()
        else
            C_TradeSkillUI.OpenTradeSkill(d.id)
        end
    end

    local function ShowTooltip(owner)
        mod.Tip_Begin(owner)
        local title = secondary and (SECONDARY_SKILLS or "Secondary Professions")
            or (TRADE_SKILLS or "Professions")
        mod.Tip_AddLine(title, 1, 1, 1)
        mod.Tip_AddLine(" ")
        for _, row in ipairs(rows) do
            local d = row.data
            if d.idx and d.name then
                local rank = CludesUI.COLOR_CODES.WHITE .. d.rank .. "|r / " .. d.maxRank
                mod.Tip_AddDouble(d.name, rank, 1, 1, 1, 1, 1, 1)
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
            local f = CreateFrame(
                "Button",
                "CludesUIDataBarsProf" .. i .. "_" .. inst.key,
                contentFrame,
                "SecureActionButtonTemplate"
            )
            f:SetSize(1, barCtx.GetThickness())
            f:EnableMouse(true)
            f:RegisterForClicks("AnyUp")
            f:SetAttribute("useOnKeyDown", false)
            if secondary then
                f:SetAttribute("*type2", "spell")
                f:SetAttribute("*spell2", CAMPFIRE)
            elseif _G.ProfessionMicroButton then
                f:SetAttribute("*type2", "click")
                f:SetAttribute("*clickbutton2", _G.ProfessionMicroButton)
            end
            local skill = CreateFrame("StatusBar", nil, f)
            skill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
            local track = skill:CreateTexture(nil, "BACKGROUND")
            track:SetAllPoints()
            row.frame, row.skill, row.track = f, skill, track
            row.icon = f:CreateTexture(nil, "OVERLAY")
            row.text = f:CreateFontString(nil, "OVERLAY")
            K.AttachTextOffset(inst, row.text)

            -- HookScript, not SetScript: replacing OnClick would drop the
            -- secure handler that does the right-click.
            f:HookScript("OnClick", function(_, mouseButton)
                if mouseButton == "LeftButton" then
                    OpenProfession(row.data)
                end
            end)
            f:SetScript("OnEnter", function(self)
                local r, g, b = mod.GetAccent()
                row.text:SetTextColor(r, g, b, 1)
                row.icon:SetVertexColor(r, g, b, 1)
                ShowTooltip(self)
            end)
            f:SetScript("OnLeave", function(self)
                local r, g, b = K.BlockColorOf(blockCfg)
                row.text:SetTextColor(r, g, b, 1)
                -- The icon goes back to the icon colour, not the text's.
                local ir, ig, ib = K.IconColorOf(blockCfg)
                row.icon:SetVertexColor(ir, ig, ib, 1)
                mod.Tip_Hide(self)
            end)
        end
    end

    local function FillSkillBar(row)
        local d = row.data
        local r, g, b = mod.GetAccent()
        row.skill:SetMinMaxValues(1, d.maxRank)
        row.skill:SetValue(d.rank)
        row.skill:SetStatusBarColor(r, g, b, 1)
        row.track:SetColorTexture(BAR_TRACK[1], BAR_TRACK[2], BAR_TRACK[3], BAR_TRACK[4])
    end

    -- Draws one profession into its row's button; hides the button if not learned.
    local function DrawRow(row)
        local d, f, icon, text, skill = row.data, row.frame, row.icon, row.text, row.skill
        if not d.idx then
            f:Hide()
            return
        end
        local s = Settings()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local iconSize = fontSize + 8
        local valuesOnly = s.textDisplay == "values"
        local withBar = not valuesOnly and d.rank ~= d.maxRank
        local withIcon = s.showIcon ~= false

        -- Ours, unless the setting asks for the game's (or we have none).
        local ours = s.iconStyle ~= "wow" and OUR_ICONS[d.id]
        icon:SetTexture(ours and (ART .. ours .. ".png") or d.icon)
        if ours then
            icon:SetTexCoord(0, 1, 0, 1)
        else
            K.CropStockIcon(icon) -- the game's icons have a border baked in
        end
        if withIcon then
            icon:SetSize(iconSize, iconSize)
            icon:Show()
        else
            icon:Hide()
        end
        local ir, ig, ib = K.IconColorOf(blockCfg)
        icon:SetVertexColor(ir, ig, ib, 1)

        mod.SetFont(text, fontSize, barCtx.cfg)
        local r, g, b = K.BlockColorOf(blockCfg)
        text:SetTextColor(r, g, b, 1)
        text:SetText(valuesOnly and (d.rank .. "/" .. d.maxRank) or (d.name or ""))

        if barCtx.IsVertical() then
            -- Icon, text and bar stacked, centred in the bar's width.
            local width = K.VSlotW(inst)
            local inner = max(30, width - 8)
            local height = withIcon and (8 + iconSize + 2) or (8 + 2)
            icon:ClearAllPoints()
            icon:SetPoint("TOP", f, "TOP", 0, -4)
            mod.SetWrappedText(text, inner, "CENTER")
            text:ClearAllPoints()
            if withIcon then
                text:SetPoint("TOP", icon, "BOTTOM", 0, -2)
            else
                text:SetPoint("TOP", f, "TOP", 0, -4)
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
            f:SetSize(width, max(height, barH))
            f:Show()
            return
        end

        -- Across: icon on the left; text beside it, or text over the bar,
        -- the bar as wide as the text and level with the icon's bottom. With
        -- no icon the text and bar keep the icon's band.
        mod.ResetInlineText(text, "LEFT")
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", f, "LEFT", 0, 0)
        local half = iconSize / 2
        text:ClearAllPoints()
        if not withBar then
            skill:Hide()
            if withIcon then
                text:SetPoint("LEFT", icon, "RIGHT", K.ICON_GAP, 0)
            else
                text:SetPoint("LEFT", f, "LEFT", 0, 0)
            end
        else
            skill:Show()
            if withIcon then
                text:SetPoint("TOPLEFT", icon, "TOPRIGHT", K.ICON_GAP, 0)
            else
                text:SetPoint("TOPLEFT", f, "LEFT", 0, half)
            end
            FillSkillBar(row)
            skill:SetSize(max(text:GetStringWidth(), 20), max(2, iconSize - fontSize - 3))
            skill:ClearAllPoints()
            if withIcon then
                skill:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", K.ICON_GAP, 0)
            else
                skill:SetPoint("BOTTOMLEFT", f, "LEFT", 0, -half)
            end
        end
        local lead = withIcon and (iconSize + K.ICON_GAP) or 0
        f:SetSize(lead + max(text:GetStringWidth(), 20), barH)
        f:Show()
    end

    -- Lays the learned professions out in a row (or a column), then sizes the block.
    local function Draw()
        local vertical = barCtx.IsVertical()
        local gap = vertical and 4 or 5
        local previous, extent = nil, 0
        for _, row in ipairs(rows) do
            DrawRow(row)
            if row.data.idx then
                local f = row.frame
                f:ClearAllPoints()
                if vertical then
                    if previous then
                        f:SetPoint("TOP", previous, "BOTTOM", 0, -gap)
                    else
                        f:SetPoint("TOP", contentFrame, "TOP", 0, 0)
                    end
                    extent = extent + f:GetHeight()
                else
                    if previous then
                        f:SetPoint("LEFT", previous, "RIGHT", gap, 0)
                    else
                        f:SetPoint("LEFT", contentFrame, "LEFT", 0, 0)
                    end
                    extent = extent + f:GetWidth()
                end
                if previous then
                    extent = extent + gap
                end
                previous = f
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
