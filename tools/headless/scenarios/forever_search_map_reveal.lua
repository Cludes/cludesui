-- Settings search on Forever: the words players use for Map Reveal (map
-- reveal, fog of war, whole map) find Reveal Unexplored Areas.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
local box = CUI._sidebarSearchBox
local function Rows(frame, out)
    for _, kid in ipairs({ frame:GetChildren() }) do
        if kid._label and kid._sub and kid:IsShown() then out[#out + 1] = (kid._label:GetText() or "") .. " [" .. (kid._sub:GetText() or "") .. "]" end
        Rows(kid, out)
    end
    return out
end
for _, q in ipairs({ "map reveal", "reveal", "reveal map", "fog", "fog of war", "unexplored", "explore", "whole map", "map" }) do
    box:SetText(q)
    box:GetScript("OnTextChanged")(box)
    HARNESS_ADVANCE(0.3)
    local rows = Rows(CUI._mainFrame, {})
    local hits = {}
    for i, r in ipairs(rows) do
        if r:find("Reveal") then hits[#hits + 1] = i .. ": " .. r:gsub("|T.-|t", ""):sub(1, 60) end
    end
    OUT:write(("== %s: %d rows | %s\n"):format(q, #rows, table.concat(hits, " ; ")))
end
