-- Settings search on Forever: the words players use for the Dungeons & Raids
-- tools (sheep, crowd control, rez, battle res, cc, lfg) find the CC Marker
-- Bar, Looking For Group and Res Helper rows.
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
for _, q in ipairs({ "sheep", "sap", "crowd control", "cc", "lfg", "group finder", "battle res", "rez", "res" }) do
    box:SetText(q)
    box:GetScript("OnTextChanged")(box)
    HARNESS_ADVANCE(0.3)
    local rows = Rows(CUI._mainFrame, {})
    local hits = {}
    for i, r in ipairs(rows) do
        if r:find("CC Marker") or r:find("Looking For Group") or r:find("Res Helper") then hits[#hits + 1] = i .. ": " .. r:gsub("|T.-|t", ""):sub(1, 60) end
    end
    OUT:write(("== %s: %d rows | %s\n"):format(q, #rows, table.concat(hits, " ; ")))
end
