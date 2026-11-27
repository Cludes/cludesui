-- Settings search (CludesUI_GlobalSearch.lua): old names still find renamed
-- settings (layout mode -> Edit Layout), and a page named like its module
-- shows once in a result's breadcrumb.
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
for _, q in ipairs({ "layout mode", "unlock", "edit layout", "move frames", "reload", "import profile", "export", "theme" }) do
    box:SetText(q)
    box:GetScript("OnTextChanged")(box)
    HARNESS_ADVANCE(0.3)
    local rows = Rows(CUI._mainFrame, {})
    OUT:write(("== %s: %d | %s\n"):format(q, #rows, table.concat(rows, " ; "):sub(1, 400)))
end
