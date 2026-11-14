if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Tank Kit is the same code as the standalone CoTankAuras addon. If that addon is
-- switched on, it runs and this module stays out of its way.
local _, ns = ...
local state = C_AddOns and C_AddOns.GetAddOnEnableState and C_AddOns.GetAddOnEnableState("CoTankAuras")
ns.standalone = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("CoTankAuras"))
    or (type(state) == "number" and state > 0)
    or false
-- The settings pages (CludesUIOptions/CUI_Tank_Options.lua) reach the module through this.
if not ns.standalone then
    CludesUI._ModuleNS["CludesUITank"] = ns
end
