-- Option rows (CludesUI_Widgets_Rows.lua): the hint line under a setting's
-- name is often cut short; it answers hover like the name, with the full text.
local CUI = rawget(_G, "CludesUI")
CUI:Show()
HARNESS_ADVANCE(0.2)
CUI:SelectModule("_CUIGlobal")
HARNESS_ADVANCE(0.2)
local hints, covered = 0, 0
local function Walk(frame)
    for _, kid in ipairs({ frame:GetChildren() }) do
        if kid._hint and kid._label then
            hints = hints + 1
            for _, f in ipairs({ kid:GetChildren() }) do
                local _, rel = f:GetPoint(1)
                if rel == kid._hint and f:GetScript("OnEnter") then covered = covered + 1 break end
            end
        end
        Walk(kid)
    end
end
Walk(rawget(_G, "CludesUIScrollFrame"))
OUT:write(("== Core Settings rows with a hint: %d, hint answers hover: %d\n"):format(hints, covered))
