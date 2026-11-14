-- The Mythic+ tab: a one-line readout under your rating, the line distances
-- in its tooltip, and a click on it opens the graph.

local _, mod = ...
if mod.standalone then
    return
end

local function Readout()
    local context = mod.Context()
    if context.error then
        return ""
    end
    local parts = {}
    for _, s in ipairs(context.summary.tiers) do
        parts[#parts + 1] = mod.Key(s.tier.color)
            .. " "
            .. s.tier.short
            .. "  |cfff0efec"
            .. (s.gap > 0 and (mod.Fmt(s.gap) .. " to go") or "reached")
            .. "|r"
    end
    local lineTex = table.concat(parts, "     ")
    -- Titles are account-wide: on an alt, the distances are your best character's.
    if not context.subject.isCurrent and context.subject.name then
        lineTex = lineTex .. "   |cff898781(" .. context.subject.name .. ")|r"
    end
    return lineTex
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_ChallengesUI", function()
    local childFrame = ChallengesFrame and ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child
    local details = childFrame and childFrame.DungeonScoreInfo
    if not details or not details.Score then
        return
    end

    details:HookScript("OnEnter", function()
        mod.AddTooltipLines(GameTooltip, true)
        GameTooltip:Show()
    end)
    details:HookScript("OnClick", function()
        if not IsModifiedClick("CHATLINK") then
            mod.Graph:Toggle()
        end
    end)

    local readout = details:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    readout:SetPoint("TOP", details.Score, "BOTTOM", 0, -3)
    local c = mod.COLORS.ink2
    readout:SetTextColor(c[1], c[2], c[3])
    hooksecurefunc(ChallengesFrame, "Update", function()
        readout:SetText(Readout())
    end)
end)
