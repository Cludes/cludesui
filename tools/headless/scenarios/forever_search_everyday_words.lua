-- Settings search: everyday words (sell grey, ah, pathing, directions,
-- tomtom, dps meter) find Auto Sell Junk, auction settings, Journeys and the
-- Damage Meters.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local box = CUI._sidebarSearchBox
local function Rows(frame, out)
    for _, kid in ipairs({ frame:GetChildren() }) do
        if kid._label and kid._sub and kid:IsShown() then out[#out + 1] = (kid._label:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. " [" .. (kid._sub:GetText() or ""):gsub("|T.-|t", ">") .. "]" end
        Rows(kid, out)
    end
    return out
end
for _, q in ipairs({ "sell grey", "sell gray", "skip gray", "ah", "pathing", "directions", "navigation", "tomtom", "dps meter", "recount" }) do
    box:SetText(q)
    box:GetScript("OnTextChanged")(box)
    HARNESS_ADVANCE(0.3)
    local rows = Rows(CUI._mainFrame, {})
    OUT:write(("== %s: %d | %s\n"):format(q, #rows, table.concat(rows, " ; "):sub(1, 230)))
end
