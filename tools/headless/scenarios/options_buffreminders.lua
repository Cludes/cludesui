-- Auras, Buffs & Consumables: the Reminders page (header preview and the
-- whole scroll page), the Talent Reminders page on retail, then Reminders
-- again from the page cache.
local CUI = rawget(_G, "CludesUI")
CUI:SelectModule("CludesUIAuraBuffReminders")
local list = { "Auras, Buffs & Consumables" }
if not CUI.IS_FOREVER then
    list[2] = "Talent Reminders"
end
for _, name in ipairs(list) do
    CUI:SelectPage(name)
    SNAP("page " .. name, CUI._scrollFrame)
    SNAP("header " .. name, CUI._contentHeader or CUI._headerFrame)
end
CUI:SelectPage(list[1])
SNAP("again", CUI._scrollFrame)
SNAP("header again", CUI._contentHeader or CUI._headerFrame)
