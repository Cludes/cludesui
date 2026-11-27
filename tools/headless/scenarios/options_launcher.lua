-- The addon compartment entry (CludesUI.toc AddonCompartmentFunc*) and the
-- launcher clicks (CUI.LauncherClick): left toggles the options.
local CUI = rawget(_G, "CludesUI")
OUT:write("== compartment functions: " .. tostring(type(CludesUI_OnAddonCompartmentClick) == "function"
    and type(CludesUI_OnAddonCompartmentEnter) == "function") .. "\n")
if CUI._mainFrame and CUI._mainFrame:IsShown() then CUI:Hide() end
CludesUI_OnAddonCompartmentClick("CludesUI", "LeftButton")
HARNESS_ADVANCE(0.2)
OUT:write("== left click opens: " .. tostring(CUI._mainFrame and CUI._mainFrame:IsShown()) .. "\n")
OUT:write("== right-click hint: " .. CUI.L("|cff4cc9f0Right-click:|r |cffE0E0E0Enter Layout Mode|r") .. "\n")
