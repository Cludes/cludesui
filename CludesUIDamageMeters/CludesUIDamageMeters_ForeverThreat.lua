if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIDamageMeters_ForeverThreat.lua  (WoW Forever only)
--  The "Threat" meter type: Forever Essentials' threat list in a Damage Meters
--  window, painted by the window like any other type and in its style (the
--  rows carry their own value text, rank and highlight colours). Offered only
--  while Forever Essentials is loaded, which hands the list over as
--  CludesUI._ThreatFeed; a window saved on the type reads as Damage Done
--  wherever it is not offered. The other Damage Meters files reach this file
--  only through nil-guarded ns hooks.
-------------------------------------------------------------------------------
local _, mod = ...
local THREAT = "threat"

-- Icons: the target crosshair glyph (on its plate under the WoW Forever look)
-- and the vanilla taunt icon under Classic WoW UI.
do
    local enemy = Enum.DamageMeterType.EnemyDamageTaken
    mod._DM_TYPE_ICONS[THREAT] = mod._DM_TYPE_ICONS[enemy]
    local fv = mod.DM_HDR_ART.forever
    fv.types[THREAT] = fv.types[enemy]
    mod.DM_HDR_ART.classic.types[THREAT] =
        { file = "Interface\\Icons\\Spell_Nature_Reincarnation", crop = 0.08, scale = 0.85 }
end

-- Repaints every shown Threat window after the list rebuilt (a hidden one
-- repaints on its show).
function mod.DMThreatNotify()
    for _, wid in ipairs(mod._windows) do
        if wid.curDMType == THREAT and wid.frame and wid.frame:IsVisible() then
            wid.Refresh()
        end
    end
end

-- The session a visible Threat window paints. The first one starts the feed.
function mod.DMThreatSession()
    local feed = CludesUI._ThreatFeed
    if not feed then
        return nil
    end
    if not feed.IsActive() then
        feed.Start(mod.DMThreatNotify)
    end
    -- The value text follows the meter's Force English Units, as every type's does.
    local saved = mod.EDM.DB()
    return feed.Session(saved and saved.forceEnglishUnits == true)
end

-- Stops the feed once no Threat window is on screen; `except` is a window in
-- the middle of hiding.
function mod.DMThreatSync(except)
    local feed = CludesUI._ThreatFeed
    if not (feed and feed.IsActive()) then
        return
    end
    for _, wid in ipairs(mod._windows) do
        if wid ~= except and wid.curDMType == THREAT and wid.frame and wid.frame:IsVisible() then
            return
        end
    end
    feed.Stop()
end

-- The list's own settings (tracked unit, displayed value, pets) head a
-- Threat window's settings menu, and the clock and segment rows (noThreat)
-- leave it.
function mod.DMThreatMenu(itemList)
    local feed = CludesUI._ThreatFeed
    if not feed then
        return
    end
    for index = #itemList, 1, -1 do
        local e = itemList[index]
        if type(e) == "table" and e.noThreat then
            table.remove(itemList, index)
        end
    end
    local head = feed.MenuItems({})
    head[#head + 1] = "---"
    for index = #head, 1, -1 do
        table.insert(itemList, 1, head[index])
    end
end

-- Forever Essentials loads after this addon: the type is offered from login
-- on, before the windows are built, when it is there.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if CludesUI._ThreatFeed then
        mod._DM_TYPE_NAMES[THREAT] = "Threat"
    end
end)
