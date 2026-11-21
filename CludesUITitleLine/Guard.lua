if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- Title Line is the same code as the standalone TitleLine addon. If that addon is
-- switched on, it runs and this module stays out of its way.
local _, mod = ...
local status = C_AddOns and C_AddOns.GetAddOnEnableState and C_AddOns.GetAddOnEnableState("TitleLine")
mod.standalone = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("TitleLine"))
    or (type(status) == "number" and status > 0)
    or false
if not mod.standalone then CludesUI._ModuleNS["CludesUITitleLine"] = mod end
