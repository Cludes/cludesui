-- WoW Forever Auras, Buffs & Consumables page as built (run it as a Mage too
-- for the class-only rows). Custom spells and spell groups added after the
-- build cannot be shown headlessly: rebuilding this page hands a pooled
-- font string the fake client cannot stand in for (same before and after).
local CUI = rawget(_G, "CludesUI")
CUI:SelectModule("CludesUIAuraBuffReminders")
CUI:SelectPage("Auras, Buffs & Consumables")
SNAP("forever page", CUI._scrollFrame)
