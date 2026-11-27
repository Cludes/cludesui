-- Description coverage (CludesUI_Widgets_Rows.lua hints): rebuilds every page and
-- counts, per module, the setting rows that reach the search index without a
-- description. A coverage check, not a pass/fail: watch the totals fall.
local CUI = rawget(_G, "CludesUI")
local counts, missing, samples = {}, {}, {}
local orig = CUI._RegisterSearchEntry
CUI._RegisterSearchEntry = function(label, localLabel, tipText, moduleFolder, pageEntry, sectionName, a, b, isSection)
    if not isSection and label and moduleFolder then
        counts[moduleFolder] = (counts[moduleFolder] or 0) + 1
        if type(tipText) ~= "string" or tipText == "" then
            missing[moduleFolder] = (missing[moduleFolder] or 0) + 1
            samples[moduleFolder] = samples[moduleFolder] or {}
            if #samples[moduleFolder] < 8 then table.insert(samples[moduleFolder], (pageEntry or "?") .. ": " .. label) end
        end
    end
    return orig(label, localLabel, tipText, moduleFolder, pageEntry, sectionName, a, b, isSection)
end
CUI:Show()
HARNESS_ADVANCE(0.2)
local MODS = { "_CUIGlobal", "CludesUIActionBars", "CludesUIUnitFrames", "CludesUINameplates", "CludesUIRaidFrames", "CludesUICooldownManager", "CludesUIResourceBars", "CludesUIAuraBuffReminders", "CludesUIDamageMeters", "CludesUIMythicTimer", "CludesUIRaidLead", "CludesUITank", "CludesUITitleLine", "CludesUIGroupFinder", "CludesUIBlizzardSkin", "CludesUIMinimap", "CludesUIChat", "CludesUIBags", "CludesUIQuestTracker", "CludesUIFriends", "CludesUIDataBars", "CludesUIQoL", "CludesUIQuickdraw", "CludesUIForeverEssentials" }
for _, key in ipairs(MODS) do
    if CUI.InvalidatePageCache then CUI:InvalidatePageCache() end
    CUI:SelectModule(key)
    HARNESS_ADVANCE(0.05)
    local pages = {}
    for _, kid in ipairs({ CUI._addonScrollChild:GetChildren() }) do
        if kid:IsShown() and kid._page and kid._module == key then pages[#pages + 1] = kid._page end
    end
    for _, page in ipairs(pages) do if CUI.InvalidatePageCache then CUI:InvalidatePageCache() end pcall(CUI.SelectPage, CUI, page) HARNESS_ADVANCE(0.05) end
end
local keys = {}
for k in pairs(counts) do keys[#keys + 1] = k end
table.sort(keys, function(x, y) return (missing[x] or 0) > (missing[y] or 0) end)
for _, k in ipairs(keys) do
    OUT:write(("== %s: %d of %d without a description | %s\n"):format(k, missing[k] or 0, counts[k], table.concat(samples[k] or {}, " ; ")))
end
