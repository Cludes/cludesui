-- Talent Reminders page (retail): with saved reminders (one per zone list,
-- one in the older single-zone form, one Not Needed in season instances, one
-- only for a rotated-out zone, which stays hidden) and its kept zone and
-- talent popups, then with none.
local CUI = rawget(_G, "CludesUI")
if CUI.IS_FOREVER then return end
local db = rawget(_G, "_CUABR_AceDB")
local p = db and db.profile
local zones = rawget(_G, "_CUABR_TALENT_REMINDER_ZONES") or {}
local z1, z2 = zones[1] and zones[1].name, zones[2] and zones[2].name
OUT:write("== zones " .. #zones .. " " .. tostring(z1) .. " " .. tostring(z2) .. "\n")
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIAuraBuffReminders")
    CUI:SelectPage("Talent Reminders")
end
local function Popups(label)
    local n = 0
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 200 then
            n = n + 1
            SNAP(label .. " popup " .. n, c)
        end
    end
end
if p then
    p.talentReminders = {
        { zoneNames = { z1, z2 }, spellID = 100, spellName = "Alpha Talent", notNeededMode = "never", class = "PALADIN" },
        { zoneName = z2, spellID = 200, spellName = "Beta Talent", showNotNeeded = true, class = "PALADIN" },
        { zoneNames = { z1 }, spellID = 300, spellName = "Gamma Talent", notNeededMode = "season", class = "PALADIN" },
        { zoneNames = { "Gone From The Season" }, spellID = 400, spellName = "Hidden Talent", class = "PALADIN" },
    }
end
Rebuild()
SNAP("talent page", CUI._scrollFrame)
Popups("with reminders")
if p then p.talentReminders = {} end
Rebuild()
SNAP("talent page empty", CUI._scrollFrame)
