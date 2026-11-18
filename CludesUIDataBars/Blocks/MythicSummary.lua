if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- Mythic+ Tools does not load on WoW Forever (the main file drops the block type there too)
-------------------------------------------------------------------------------
--  Blocks\MythicSummary.lua - Info Bar block: the latest Mythic+ run.
--
--  Shows the newest run (level in its keystone colour, then the dungeon).
--  Hover lists every recorded run with its time (green in time, red over);
--  left-click opens the Run Summary (as /ov does), right-click clears the
--  history after asking.
--
--  The runs are kept by Mythic+ Tools (CludesUI._MythicRuns), which calls
--  OnChanged when one is added or the history is cleared. That hook is set
--  only while a block is enabled, so the block registers no events at all.
--
--  Settings (blockCfg.settings): hideWhenEmpty (no runs = no block).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local format, floor, max, min = string.format, math.floor, math.max, math.min

local blocks = {} -- every enabled block, as a set

local function RunsChanged()
    for block in pairs(blocks) do
        block:Refresh()
    end
end

-- The hook is held while any block is enabled (bars are built after
-- Mythic+ Tools has loaded, so it exists by then).
local function Hook()
    local store = CludesUI._MythicRuns
    if store then
        store.OnChanged = next(blocks) and RunsChanged or nil
    end
end

local function Runs()
    local store = CludesUI._MythicRuns
    return store and store.Get()
end

local function Newest()
    local runs = Runs()
    return runs and runs[1]
end

-- "+12 Ara-Kara", the level in its keystone colour as in the Run Summary.
local function RunName(run)
    if not run then
        return CludesUI.L("No runs recorded yet")
    end
    local level = "+" .. (run.level or 0)
    local color = C_ChallengeMode
        and C_ChallengeMode.GetKeystoneLevelRarityColor
        and C_ChallengeMode.GetKeystoneLevelRarityColor(run.level or 0)
    if type(color) == "table" and color.r then
        level = CludesUI.HexColor(color.r, color.g, color.b) .. level .. "|r"
    end
    return level .. " " .. (run.mapName or "?")
end

-- The run's time as m:ss, and its colour: green in time, red over.
local function RunTime(run)
    if not run.timeMS then
        return "-", 0.6, 0.6, 0.6
    end
    local secs = floor(run.timeMS / 1000)
    local text = format("%d:%02d", floor(secs / 60), secs % 60)
    if run.onTime then
        return text, 0.176, 0.796, 0.349
    end
    return text, 0.9, 0.3, 0.3
end

local function AskClear()
    local store = CludesUI._MythicRuns
    if not (store and store.Clear) then
        return
    end
    CludesUI:ShowConfirmPopup({
        title = "Clear Run History",
        message = "Delete every recorded Mythic+ run for this character?",
        confirmText = "Delete",
        cancelText = "Cancel",
        onConfirm = store.Clear,
    })
end

mod.BlockFactories.mplussummary = function(blockCfg, slot, contentFrame, barCtx)
    local inst = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    inst.key = K.InstKey(barCtx, blockCfg)
    local deferKey = "mplussummary:" .. inst.key

    local button = CreateFrame("Button", nil, contentFrame)
    button:SetAllPoints()
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")
    local label = button:CreateFontString(nil, "OVERLAY")
    K.AttachTextOffset(inst, label)

    local hovered = false

    local function PaintText()
        if hovered then
            label:SetTextColor(mod.GetAccent())
        else
            label:SetTextColor(K.BlockColorOf(blockCfg))
        end
    end

    local function AfterCombat()
        inst:Refresh()
    end

    function inst:Refresh()
        if self._dead then
            return
        end
        local run = Newest()
        -- Hide When Empty: no runs, no block (the bar drops its slot). A
        -- Show/Hide waits out combat.
        local collapsed = not run and (blockCfg.settings or {}).hideWhenEmpty == true
        if contentFrame:IsShown() == collapsed then
            if InCombatLockdown() then
                mod.DeferUntilOOC(deferKey, AfterCombat)
            else
                contentFrame:SetShown(not collapsed)
            end
        end
        if collapsed then
            K.MaybeRelayout(self)
            return
        end
        local text = RunName(run)
        mod.SetFont(label, max(9, floor(K.CONTENT_BASE * 0.4333 + 0.5)), barCtx.cfg)
        PaintText()
        -- A secure overlay elsewhere on the bar fixes its layout in combat:
        -- the text changes now, the size when combat ends.
        if InCombatLockdown() then
            label:SetText(text)
            mod.DeferUntilOOC(deferKey, AfterCombat)
            return
        end
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local slotW = K.VSlotW(self)
            label:SetText(text)
            mod.SetWrappedText(label, max(24, slotW - 8), "CENTER")
            label:ClearAllPoints()
            label:SetPoint("TOP", button, "TOP", 0, -4)
            local height = max(8 + mod.SnapToPixelGrid(label:GetStringHeight()) + 4, barH)
            contentFrame:SetSize(slotW, height)
            button:SetSize(slotW, height)
        else
            local budget = K.HBudget(self, 180)
            mod.ResetInlineText(label, "LEFT")
            label:SetText(text)
            label:ClearAllPoints()
            label:SetPoint("LEFT", button, "LEFT", 0, 0)
            local width = max(min(budget, mod.SnapToPixelGrid(label:GetStringWidth()) + 4), 10)
            contentFrame:SetSize(width, barH)
            button:SetSize(width, barH)
        end
        K.MaybeRelayout(self)
    end

    local function ShowTooltip()
        local region, g, b = mod.GetAccent()
        local runs = Runs()
        local count = runs and #runs or 0
        mod.Tip_Begin(button)
        mod.Tip_AddLine("|cFFFFFFFF[|r" .. CludesUI.L("Run Summary") .. "|cFFFFFFFF]|r", region, g, b)
        mod.Tip_AddLine(" ")
        if count == 0 then
            mod.Tip_AddLine(CludesUI.L("No runs recorded yet"), 0.6, 0.6, 0.6)
        end
        for i = 1, count do
            local time, tr, tg, tb = RunTime(runs[i])
            mod.Tip_AddDouble(RunName(runs[i]), time, 0.8, 0.8, 0.8, tr, tg, tb)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], CludesUI.L("Open Run Summary"), 1, 1, 1, region, g, b)
        if count > 0 then
            mod.Tip_AddDouble(L["RIGHT_CLICK"], CludesUI.L("Clear Run History"), 1, 1, 1, region, g, b)
        end
        mod.Tip_Show()
    end

    -- Hovering only recolours the text; nothing moves, so nothing is laid out again.
    button:SetScript("OnEnter", function()
        hovered = true
        PaintText()
        ShowTooltip()
    end)
    button:SetScript("OnLeave", function()
        hovered = false
        mod.Tip_Hide(button)
        PaintText()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            if Newest() then
                AskClear()
            end
        elseif mouseButton == "LeftButton" then
            -- The /ov path, so a disabled Run Summary says so the same way.
            local open = SlashCmdList and SlashCmdList.CUIMPLUS
            if open then
                open("")
            end
        end
    end)

    function inst:Enable()
        blocks[self] = true
        Hook()
        self:Refresh()
    end

    function inst:Disable()
        blocks[self] = nil
        Hook()
        mod.Tip_Hide(button)
        contentFrame:Hide()
    end

    function inst:GetAutoLength()
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function inst:Destroy()
        self._dead = true
        blocks[self] = nil
        Hook()
        contentFrame:Hide()
    end

    return inst
end
