-- The Mythic+ tab: a one-line readout under your rating, the line distances
-- in its tooltip, and a click on it opens the graph.

local _, ns = ...
if ns.standalone then
    return
end

local function Readout()
    local ctx = ns.Context()
    if ctx.error then
        return ""
    end
    local parts = {}
    for _, s in ipairs(ctx.summary.tiers) do
        parts[#parts + 1] = ns.Key(s.tier.color)
            .. " "
            .. s.tier.short
            .. "  |cfff0efec"
            .. (s.gap > 0 and (ns.Fmt(s.gap) .. " to go") or "reached")
            .. "|r"
    end
    local line = table.concat(parts, "     ")
    -- Titles are account-wide: on an alt, the distances are your best character's.
    if not ctx.subject.isCurrent and ctx.subject.name then
        line = line .. "   |cff898781(" .. ctx.subject.name .. ")|r"
    end
    return line
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_ChallengesUI", function()
    local child = ChallengesFrame and ChallengesFrame.WeeklyInfo and ChallengesFrame.WeeklyInfo.Child
    local info = child and child.DungeonScoreInfo
    if not info or not info.Score then
        return
    end

    info:HookScript("OnEnter", function()
        ns.AddTooltipLines(GameTooltip, true)
        GameTooltip:Show()
    end)
    info:HookScript("OnClick", function()
        if not IsModifiedClick("CHATLINK") then
            ns.Graph:Toggle()
        end
    end)

    local readout = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    readout:SetPoint("TOP", info.Score, "BOTTOM", 0, -3)
    local c = ns.COLORS.ink2
    readout:SetTextColor(c[1], c[2], c[3])
    hooksecurefunc(ChallengesFrame, "Update", function()
        readout:SetText(Readout())
    end)
end)
