-- Options window themes (CUI Options Theme on Global Settings > General): the
-- theme list, then for a few themes: pick it, let the crossfade finish, and
-- snapshot the window; fold the window to the mini
-- window and back (the mini window and the collapse button cut their boxes
-- out of the theme's art), recording any error.
local CUI = rawget(_G, "CludesUI")
if not (CUI and CUI._mainFrame) then CUI:SelectModule("CludesUIActionBars") end
local main = CUI._mainFrame
if not (main and CUI.SetActiveTheme) then
    OUT:write("== no panel or theme setter\n")
    return
end
OUT:write("== themes: " .. table.concat(CUI.THEME_ORDER or {}, ", ") .. "\n")

for _, name in ipairs({ "CludesUI Clean", "CludesUI", "CludesUI Forever", "Ember" }) do
    local ok, err = pcall(CUI.SetActiveTheme, name)
    if HARNESS_TICK then HARNESS_TICK(0.05, 30) end
    OUT:write("== theme " .. name .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
    SNAP("panel " .. name, main)
    if CUI._SetPanelCollapsed then
        local okFold, errFold = pcall(CUI._SetPanelCollapsed, true)
        if HARNESS_TICK then HARNESS_TICK(0.05, 10) end
        local okBack, errBack = pcall(CUI._SetPanelCollapsed, false)
        if HARNESS_TICK then HARNESS_TICK(0.05, 10) end
        OUT:write("   fold " .. (okFold and "ok" or tostring(errFold)) .. ", unfold " .. (okBack and "ok" or tostring(errBack)) .. "\n")
    end
end
