-- Quest Tracker > Wowhead quest links: which IDs count, the link built for
-- each setting, the menu hooks registered and removed, a menu getting the
-- button once, and the tracker menu only while its header is hovered.
local mod = rawget(_G, "CludesUI")._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
local hooks, live = {}, {}
Menu = { ModifyMenu = function(tag, fn)
    hooks[tag] = fn
    live[tag] = true
    return { Unregister = function() live[tag] = nil end }
end }
local hover
EventRegistry = { RegisterCallbackWithHandle = function(_, name, fn)
    hover = fn
    live[name] = true
    return { Unregister = function() live[name] = nil end }
end }
local popup
CludesUI.ShowInputPopup = function(_, opts) popup = opts end
local function Root()
    local r = { items = {} }
    function r:CreateDivider() self.items[#self.items + 1] = "divider" end
    function r:CreateButton(text, fn) self.items[#self.items + 1] = text; self.fn = fn end
    return r
end
local function Live()
    local t = {}
    for k in pairs(live) do t[#t + 1] = k end
    table.sort(t)
    return table.concat(t, ",")
end

Put("off ok", EQT.WowheadQuestOK(123))
EQT.ApplyQuestLinks()
Put("off hooks", Live())
EQT.Set("wowheadQuestLinks", true)
for _, id in ipairs({ 123, 0, -5, 1.5, "7", 99999 }) do
    Put("ok", id, EQT.WowheadQuestOK(id))
end
EQT.ApplyQuestLinks()
EQT.ApplyQuestLinks()
Put("on hooks", Live())
for _, combo in ipairs({ { false, false }, { true, false }, { false, true }, { true, true } }) do
    EQT.Set("wowheadQuestComments", combo[1])
    EQT.Set("wowheadQuestClientLanguage", combo[2])
    popup = nil
    EQT.ShowWowheadLink(4567)
    Put("link", combo[1], combo[2], popup and popup.initialText, popup and popup.title, popup and popup.maxLetters)
end
popup = nil
EQT.ShowWowheadLink(0)
Put("link bad id", popup)
local r = Root()
hooks.MENU_QUEST_MAP_LOG_TITLE({ questID = 42 }, r)
hooks.MENU_QUEST_MAP_LOG_TITLE({ questID = 42 }, r)
Put("log menu", table.concat(r.items, ","))
local w = Root()
hooks.MENU_QUEST_MAP_LOG_TITLE({}, w)
Put("waypoint menu", table.concat(w.items, ","))
local t = Root()
local header = { IsMouseOver = function() return true end }
hover(nil, { id = 77, HeaderButton = header })
hooks.MENU_QUEST_OBJECTIVE_TRACKER(nil, t)
Put("tracker menu hovered", table.concat(t.items, ","))
local t2 = Root()
header.IsMouseOver = function() return false end
hooks.MENU_QUEST_OBJECTIVE_TRACKER(nil, t2)
Put("tracker menu left", table.concat(t2.items, ","))
popup = nil
if t.fn then t.fn() end
Put("tracker click", popup and popup.initialText)
EQT.Set("wowheadQuestLinks", false)
EQT.ApplyQuestLinks()
Put("off again hooks", Live())
