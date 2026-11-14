if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- Mythic+ Tools does not load on WoW Forever: no runs, no factory (the main file drops the block from BLOCK_TYPES too)
-- Blocks\MythicSummary.lua
-- Mythic+ run summary block factory.

local ADDON_NAME, mod = ...
local L = mod.L
local K = mod.BlockKit

-- Upvalues
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local pairs = pairs
local type = type
local format = string.format
local floor = math.floor
local max = math.max
local min = math.min

local CONTENT_BASE = K.CONTENT_BASE
local InstKey = K.InstKey
local HBudget = K.HBudget
local VSlotW = K.VSlotW
local MaybeRelayout = K.MaybeRelayout
local AttachTextOffset = K.AttachTextOffset
local BlockColorOf = K.BlockColorOf

-------------------------------------------------------------------------------
--  M+ SUMMARY (newest Run Summary record; click opens it like /ov, the
--  tooltip lists every stored run, Right Click clears them)
--
--  Runs are stored by Mythic+ Tools (CludesUI._MythicRuns), which calls its
--  OnChanged when one is added or the history is cleared. The hook is set only
--  while a block is enabled and cleared with the last one, so this registers
--  no events.
-------------------------------------------------------------------------------
local liveInsts = {}

local function OnRunsChanged()
    for instance in pairs(liveInsts) do
        instance:Refresh()
    end
end

-- Bars are built at login, after Mythic+ Tools has loaded.
local function SyncRunsHook()
    local mr = CludesUI._MythicRuns
    if mr then
        mr.OnChanged = next(liveInsts) and OnRunsChanged or nil
    end
end

local function Runs()
    local mr = CludesUI._MythicRuns
    return mr and mr.Get()
end

local function LatestRun()
    local runs = Runs()
    return runs and runs[1]
end

-- Level in its keystone-rarity color, as in the Run Summary header.
local function RunText(rec)
    if not rec then
        return CludesUI.L("No runs recorded yet")
    end
    local level = "+" .. (rec.level or 0)
    local kcol = C_ChallengeMode
        and C_ChallengeMode.GetKeystoneLevelRarityColor
        and C_ChallengeMode.GetKeystoneLevelRarityColor(rec.level or 0)
    if type(kcol) == "table" and kcol.r then
        level = CludesUI.HexColor(kcol.r, kcol.g, kcol.b) .. level .. "|r"
    end
    return level .. " " .. (rec.mapName or "?")
end

-- Completion time as m:ss, green when timed, red when depleted.
local function RunTime(rec)
    local ms = rec.timeMS
    if not ms then
        return "-", 0.6, 0.6, 0.6
    end
    local secs = floor(ms / 1000)
    local textValue = format("%d:%02d", floor(secs / 60), secs % 60)
    if rec.onTime then
        return textValue, 0.176, 0.796, 0.349
    end
    return textValue, 0.9, 0.3, 0.3
end

local function ConfirmClear()
    local mr = CludesUI._MythicRuns
    local clear = mr and mr.Clear
    if not clear then
        return
    end
    CludesUI:ShowConfirmPopup({
        title = "Clear Run History",
        message = "Delete every recorded Mythic+ run for this character?",
        confirmText = "Delete",
        cancelText = "Cancel",
        onConfirm = clear,
    })
end

mod.BlockFactories.mplussummary = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = InstKey(barCtx, blockCfg)

    local mouseOver = false

    local function D()
        return blockCfg.settings or {}
    end

    local btnFrame = CreateFrame("Button", nil, contentFrame)
    btnFrame:SetAllPoints()
    btnFrame:EnableMouse(true)
    btnFrame:RegisterForClicks("AnyUp")

    local labelText = btnFrame:CreateFontString(nil, "OVERLAY")
    AttachTextOffset(instance, labelText)

    function instance:Refresh()
        if self._dead then
            return
        end
        local barCfg = barCtx.cfg
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        local rec = LatestRun()
        -- Hide When Empty: no runs collapses the block (GetAutoLength reports
        -- 0, so the solver drops the slot). Show/Hide wait out lockdown.
        local collapsed = not rec and D().hideWhenEmpty == true
        if contentFrame:IsShown() == collapsed then
            if InCombatLockdown() then
                mod.DeferUntilOOC("mplussummary:" .. instance.key, function()
                    instance:Refresh()
                end)
            elseif collapsed then
                contentFrame:Hide()
            else
                contentFrame:Show()
            end
        end
        if collapsed then
            MaybeRelayout(instance)
            return
        end
        local textValue = RunText(rec)

        mod.SetFont(labelText, fontSize, barCfg)
        if mouseOver then
            labelText:SetTextColor(mod.GetAccent())
        else
            labelText:SetTextColor(BlockColorOf(blockCfg))
        end
        -- A secure overlay elsewhere on the bar protects its geometry in
        -- lockdown: only the text updates now, sizing waits for regen.
        if InCombatLockdown() then
            labelText:SetText(textValue)
            mod.DeferUntilOOC("mplussummary:" .. instance.key, function()
                instance:Refresh()
            end)
            return
        end
        if barCtx.IsVertical() then
            local slotW = VSlotW(instance)
            local innerW = max(24, slotW - 8)
            labelText:SetText(textValue)
            mod.SetWrappedText(labelText, innerW, "CENTER")
            labelText:ClearAllPoints()
            labelText:SetPoint("TOP", btnFrame, "TOP", 0, -4)
            local totalH = max(8 + mod.SnapToPixelGrid(labelText:GetStringHeight()) + 4, barH)
            contentFrame:SetSize(slotW, totalH)
            btnFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 180)
            mod.ResetInlineText(labelText, "LEFT")
            labelText:SetText(textValue)
            labelText:ClearAllPoints()
            labelText:SetPoint("LEFT", btnFrame, "LEFT", 0, 0)
            local tw = mod.SnapToPixelGrid(labelText:GetStringWidth())
            local totalW = max(min(slotW, tw + 4), 10)
            contentFrame:SetSize(totalW, barH)
            btnFrame:SetSize(totalW, barH)
        end
        MaybeRelayout(instance)
    end

    local function ShowSummaryTooltip()
        local ar, ag, ab = mod.GetAccent()
        local runs = Runs()
        local total = runs and #runs or 0
        mod.Tip_Begin(btnFrame)
        mod.Tip_AddLine("|cFFFFFFFF[|r" .. CludesUI.L("Run Summary") .. "|cFFFFFFFF]|r", ar, ag, ab)
        mod.Tip_AddLine(" ")
        if total == 0 then
            mod.Tip_AddLine(CludesUI.L("No runs recorded yet"), 0.6, 0.6, 0.6)
        end
        for idx = 1, total do
            local rec = runs[idx]
            local t, tr, tg, tb = RunTime(rec)
            mod.Tip_AddDouble(RunText(rec), t, 0.8, 0.8, 0.8, tr, tg, tb)
        end
        mod.Tip_AddLine(" ")
        mod.Tip_AddDouble(L["LEFT_CLICK"], CludesUI.L("Open Run Summary"), 1, 1, 1, ar, ag, ab)
        if total > 0 then
            mod.Tip_AddDouble(L["RIGHT_CLICK"], CludesUI.L("Clear Run History"), 1, 1, 1, ar, ag, ab)
        end
        mod.Tip_Show()
    end

    btnFrame:SetScript("OnEnter", function()
        mouseOver = true
        instance:Refresh()
        ShowSummaryTooltip()
    end)
    btnFrame:SetScript("OnLeave", function()
        mouseOver = false
        mod.Tip_Hide(btnFrame)
        instance:Refresh()
    end)
    -- Same path as typing /ov, so a disabled Run Summary prints the same error.
    btnFrame:SetScript("OnClick", function(_, mb)
        if mb == "RightButton" then
            if LatestRun() then
                ConfirmClear()
            end
            return
        end
        if mb ~= "LeftButton" then
            return
        end
        local shade = SlashCmdList and SlashCmdList.CUIMPLUS
        if shade then
            shade("")
        end
    end)

    function instance:Enable()
        liveInsts[self] = true
        SyncRunsHook()
        self:Refresh()
    end

    function instance:Disable()
        liveInsts[self] = nil
        SyncRunsHook()
        mod.Tip_Hide(btnFrame)
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        if not contentFrame:IsShown() then
            return 0
        end
        if barCtx.IsVertical() then
            return max(contentFrame:GetHeight() or 40, 30)
        end
        return max(contentFrame:GetWidth() or 60, 24)
    end

    function instance:Destroy()
        self._dead = true
        liveInsts[self] = nil
        SyncRunsHook()
        contentFrame:Hide()
    end

    return instance
end
