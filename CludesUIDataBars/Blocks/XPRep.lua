if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Blocks\XPRep.lua - Info Bar block: an XP or reputation bar.
--
--  A label (percent, values or nothing; with or without "to level N" / the
--  faction's name) over a thin bar: XP in the accent colour with rested XP
--  behind it, or the watched faction in its standing colour (friendships and
--  renown use their own rank ranges). Automatic mode shows XP below max level
--  and reputation at it; right-click switches and remembers the choice.
--
--  XP and reputation change constantly (every kill, every rep gain), and the
--  label only changes at a whole percent, so a gain that leaves the label as
--  it is just moves the bar.
--
--  Settings (blockCfg.settings): mode = "xp" | "rep" | nil (automatic);
--  textDisplay = "percentage" | "values" | "off"; textFormat = "plain" (no
--  "to level" / faction name). blockCfg.labelAlign places the label.
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local floor, max, min = math.floor, math.max, math.min

function mod.GetXPRepTextDisplay(settings)
    return settings.textDisplay or "percentage"
end

local function Number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or n
end

-- The watched faction: the old global where it exists (WoW Forever), else
-- C_Reputation's table, as name, reaction, min, max, current, faction id.
local function Watched()
    local legacy = rawget(_G, "GetWatchedFactionInfo")
    if legacy then
        return legacy()
    end
    local d = C_Reputation and C_Reputation.GetWatchedFactionData and C_Reputation.GetWatchedFactionData()
    if d then
        return d.name,
            d.reaction,
            d.currentReactionThreshold,
            d.nextReactionThreshold,
            d.currentStanding,
            d.factionID
    end
end

local function Grey(label)
    return { label = label, minV = 0, maxV = 1, curV = 0, r = 0.5, g = 0.5, b = 0.5, rested = 0 }
end

mod.BlockFactories.xprep = function(blockCfg, slot, content, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = content, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    inst.events = { "PLAYER_XP_UPDATE", "UPDATE_FACTION", "PLAYER_ENTERING_WORLD" }

    local function Settings()
        return blockCfg.settings or {}
    end

    local function NoXP()
        return K.AtMaxLevel() or (IsXPUserDisabled and IsXPUserDisabled())
    end

    -- "xp" or "rep": the setting, or automatic (XP while there is XP to earn).
    local mode = "rep"
    local function PickMode()
        local chosen = Settings().mode
        if chosen == "xp" or chosen == "rep" then
            mode = chosen
        else
            mode = NoXP() and "rep" or "xp"
        end
    end

    -- The label for cur of total, and whether "to level" / the name goes with it.
    local function Label(cur, total)
        local s = Settings()
        local display = mod.GetXPRepTextDisplay(s)
        if display == "off" then
            return "", false
        end
        local context = s.textFormat ~= "plain"
        if display == "values" then
            return Number(cur) .. " / " .. Number(total), context, true
        end
        return floor(cur / max(1, total) * 100) .. "%", context
    end

    local function XPState()
        if NoXP() then
            -- Automatic mode hides the block here. A mode the player chose
            -- must still show: the block is the only place to right-click back,
            -- and a hidden block cannot be clicked.
            if Settings().mode ~= "xp" then
                return nil
            end
            local off = IsXPUserDisabled and IsXPUserDisabled()
            return Grey(CludesUI.L(off and "XP Off (Right-Click: Rep)" or "Max Level (Right-Click: Rep)"))
        end
        local maxXP = UnitXPMax("player") or 1
        if maxXP <= 0 then
            maxXP = 1
        end
        local cur = max(0, min(maxXP, UnitXP("player") or 0))
        local level = UnitLevel and UnitLevel("player") or 0
        local label, context, values = Label(cur, maxXP)
        if context then
            label = label .. (values and " XP" or "") .. " to level " .. (level + 1)
        end
        local r, g, b = mod.GetAccent()
        return {
            label = label,
            tooltipLabel = "Level " .. level .. " XP",
            minV = 0,
            maxV = maxXP,
            curV = cur,
            r = r,
            g = g,
            b = b,
            rested = GetXPExhaustion() or 0,
            isXP = true,
        }
    end

    local function RepState()
        local name, reaction, low, high, cur, factionID = Watched()
        if not name then
            -- As above: hidden in automatic mode only.
            if Settings().mode ~= "rep" then
                return nil
            end
            return Grey(CludesUI.L("No Rep Tracked"))
        end
        -- A friendship's thresholds come back equal (a permanent 0%); its own
        -- API has the real rank range. Checked before renown.
        local friend = factionID
            and C_GossipInfo
            and C_GossipInfo.GetFriendshipReputation
            and C_GossipInfo.GetFriendshipReputation(factionID)
        local isFriend = friend and friend.friendshipFactionID and friend.friendshipFactionID > 0
        if isFriend then
            low = friend.reactionThreshold or 0
            cur = friend.standing or low
            if friend.nextThreshold and friend.nextThreshold > low then
                high = friend.nextThreshold
            else
                low, high, cur = 0, 1, 1 -- the top rank: a full bar
            end
        end
        -- Renown: progress towards the next renown level.
        if not isFriend and factionID and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
            local major = C_MajorFactions.GetMajorFactionData(factionID)
            if major and type(major.renownLevelThreshold) == "number" and major.renownLevelThreshold > 0 then
                low, high, cur = 0, major.renownLevelThreshold, major.renownReputationEarned or 0
            end
        end
        -- Counted from the bottom of the current standing.
        if type(low) == "number" and type(high) == "number" and type(cur) == "number" and high - low > 0 then
            low, high, cur = 0, high - low, cur - low
        end
        low = type(low) == "number" and low or 0
        high = type(high) == "number" and high or 1
        cur = type(cur) == "number" and cur or 0
        if high <= low then
            high = low + 1
        end
        cur = max(low, min(high, cur))

        local label, context = Label(cur - low, high - low)
        if context then
            local short = #name > 20 and (name:sub(1, 20) .. "...") or name
            label = short .. " " .. label
        end
        local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        local r, g, b
        if color then
            r, g, b = color.r, color.g, color.b
        else
            r, g, b = mod.GetAccent()
        end
        return {
            label = label,
            tooltipLabel = name,
            minV = low,
            maxV = high,
            curV = cur,
            r = r,
            g = g,
            b = b,
            rested = 0,
        }
    end

    -- What to show, or nil to hide the block. The tooltip uses the same, so
    -- it always agrees with the bar.
    local function State()
        PickMode()
        if mode == "xp" then
            return XPState()
        end
        return RepState()
    end

    local hit = CreateFrame("Button", nil, content)
    hit:SetAllPoints()
    hit:EnableMouse(true)
    hit:RegisterForClicks("AnyUp")
    local label = content:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)
    local fill = CreateFrame("StatusBar", nil, content)
    fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local track = content:CreateTexture(nil, "BACKGROUND")
    local rested = CreateFrame("StatusBar", nil, content)
    rested:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rested:SetStatusBarColor(0.3, 0.3, 1, 0.5)
    rested:Hide()

    local drawnLabel -- the layout on screen; nil = none (hidden, or not drawn yet)

    -- The bar's colour and fill, and rested XP behind it.
    local function Fill(state)
        rested:Hide()
        fill:SetStatusBarColor(state.r, state.g, state.b, 1)
        fill:SetMinMaxValues(state.minV, state.maxV)
        fill:SetValue(state.curV)
        if state.rested > 0 then
            rested:SetMinMaxValues(state.minV, state.maxV)
            rested:SetValue(min(state.curV + state.rested, state.maxV))
            rested:Show()
        end
    end

    local function Track(width, height)
        track:SetSize(width, height)
        track:SetColorTexture(1, 1, 1, 0.1)
        fill:ClearAllPoints()
        rested:ClearAllPoints()
    end

    function inst:Refresh()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5))
        local thin = max(2, floor(K.CONTENT_BASE * 0.2 + 0.5) - 1)

        local state = State()
        if not state then
            drawnLabel = nil
            content:Hide()
            K.MaybeRelayout(self)
            return
        end
        content:Show()
        local withText = mod.GetXPRepTextDisplay(Settings()) ~= "off"
        label:SetShown(withText)
        -- XP's bar runs 40px past the label; GetAutoLength counts it in.
        self._xpExtend = state.isXP and 40 or 0
        -- The block colour is the label's; the bar keeps its own colour.
        local r, g, b = K.BlockColorOf(blockCfg)
        label:SetTextColor(r, g, b, 1)
        Fill(state)
        -- A font first: SetText on a FontString that never had one errors.
        mod.SetFont(label, fontSize, barCtx.cfg)

        if not withText then
            -- Just the bar, centred.
            label:SetText("")
            self._xpExtend = 0
            local vertical = barCtx.IsVertical()
            local width = vertical and max(24, K.VSlotW(self) - 8) or max(20, min(120, K.HBudget(self, 300)))
            content:SetSize(vertical and K.VSlotW(self) or width, vertical and 40 or barH)
            track:ClearAllPoints()
            track:SetPoint("CENTER", content, "CENTER", 0, 0)
            Track(width, thin)
            fill:SetAllPoints(track)
            rested:SetAllPoints(fill)
        elseif barCtx.IsVertical() then
            -- The label above the bar, both the bar's width.
            local slotW = K.VSlotW(self)
            local inner = max(24, slotW - 8)
            label:SetText(state.label)
            mod.SetWrappedText(label, inner, "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", content, "TOP", 0, -3)
            local textH = mod.SnapToPixelGrid(label:GetStringHeight())
            local top = -(3 + textH + 3)
            track:ClearAllPoints()
            track:SetPoint("TOP", content, "TOP", 0, top)
            Track(inner, 4)
            fill:SetSize(inner, 4)
            fill:SetPoint("TOP", content, "TOP", 0, top)
            rested:SetAllPoints(fill)
            content:SetSize(slotW, max(3 + textH + 3 + 4 + 3, 40))
        else
            -- The label over the bar, the bar as wide as the label (XP: 40px
            -- more), the pair centred in the bar's height.
            local budget = max(K.HBudget(self, 300), 60)
            local align = blockCfg.labelAlign or "LEFT"
            local anchor = align == "LEFT" and "TOPLEFT" or align == "RIGHT" and "TOPRIGHT" or "TOP"
            mod.ResetInlineText(label, align)
            label:SetText(state.label)
            local most = max(20, budget)
            local textW = label:GetStringWidth() or 0
            if textW > most then
                textW = most
                label:SetWidth(textW)
            end
            textW = mod.SnapToPixelGrid(max(textW, 20))
            local barW = state.isXP and min(textW + 40, most) or textW
            local textH = mod.SnapToPixelGrid(label:GetStringHeight() or fontSize)
            local pad = max(0, floor((barH - (textH + 2 + thin)) / 2 + 0.5))
            content:SetSize(min(budget, barW), barH)
            label:ClearAllPoints()
            label:SetPoint(anchor, content, anchor, 0, -pad)
            local top = -(pad + textH + 2)
            track:ClearAllPoints()
            track:SetPoint("TOPLEFT", content, "TOPLEFT", 0, top)
            Track(barW, thin)
            fill:SetSize(barW, thin)
            fill:SetPoint("TOPLEFT", content, "TOPLEFT", 0, top)
            rested:SetAllPoints(fill)
        end
        drawnLabel = (state.isXP and "xp:" or "rep:") .. state.label
        K.MaybeRelayout(self)
    end

    -- A gain: if the label (and so the layout) is the same, only the bar moves.
    inst.eventFrame = K.MakeEventFrame(inst, function(self)
        local state = drawnLabel and State()
        if state and (state.isXP and "xp:" or "rep:") .. state.label == drawnLabel then
            Fill(state)
            return
        end
        self:Refresh()
    end)

    hit:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and not InCombatLockdown() then
            Settings().mode = mode == "xp" and "rep" or "xp"
            inst:Refresh()
        end
    end)
    hit:SetScript("OnEnter", function()
        local state = State()
        if not state then
            return
        end
        local r, g, b = mod.GetAccent()
        mod.Tip_Begin(hit)
        -- With the text off there is no label, so the bar is named instead.
        mod.Tip_AddLine(state.label ~= "" and state.label or state.tooltipLabel, 1, 1, 1)
        if state.maxV and state.maxV > 1 then
            mod.Tip_AddDouble(
                L["PROGRESS"],
                Number(state.curV) .. " / " .. Number(state.maxV),
                0.6,
                0.6,
                0.6,
                1,
                1,
                1
            )
        end
        if state.rested and state.rested > 0 then
            mod.Tip_AddDouble(L["RESTED"], Number(state.rested), 0.6, 0.6, 0.6, 0.3, 0.3, 1)
        end
        mod.Tip_AddLine(" ")
        local switch = mode == "xp" and L["SWITCH_TO_REP"] or L["SWITCH_TO_XP"]
        mod.Tip_AddDouble(L["RIGHT_CLICK"], switch, 1, 1, 1, r, g, b)
        mod.Tip_Show()
    end)
    hit:SetScript("OnLeave", function()
        mod.Tip_Hide(hit)
    end)

    function inst:Enable()
        content:Show()
        K.RegisterInstEvents(self)
    end

    function inst:Disable()
        K.UnregisterInstEvents(self)
        content:Hide()
    end

    function inst:GetAutoLength()
        -- Hidden (nothing to show): no length, so the bar keeps no empty gap.
        if not content:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(content:GetHeight() or 40, 40)
        end
        -- The label's width (the bar matches it), plus XP's 40px.
        local width = label:GetStringWidth() or 0
        if width < 20 then
            width = 120
        end
        return width + (self._xpExtend or 0)
    end

    -- A removed block stops listening too (the old one kept redrawing its
    -- hidden frames on every XP and reputation change until a reload).
    function inst:Destroy()
        self._dead = true
        K.UnregisterInstEvents(self)
        content:Hide()
    end

    return inst
end
