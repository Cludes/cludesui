if CUI_CLIENT_BLOCKED then return end
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_QuestLinks.lua - a "Wowhead Link" entry in quest menus.
--
--  Adds the entry to the right-click menus of a quest in the quest log, the
--  quest details popup and the objective tracker; it opens a box with the
--  quest's Wowhead address to copy (optionally to its comments, and in the
--  game's language). The menu hooks exist only while the setting is on.
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT

local defaults = mod.QT_DEFAULTS.profile.questTracker
defaults.wowheadQuestLinks = false
defaults.wowheadQuestComments = false
defaults.wowheadQuestClientLanguage = false

local SITE = CludesUI.IS_FOREVER and "forever/" or ""
-- Wowhead's path per client language (English has none).
local LANGUAGE_PATH = {
    deDE = "de/",
    ptBR = "pt/",
    esES = "es/",
    esMX = "mx/",
    frFR = "fr/",
    itIT = "it/",
    ruRU = "ru/",
    zhTW = "tw/",
    zhCN = "cn/",
    koKR = "ko/",
}

local hooks -- the menu and hover registrations, while the setting is on
local done -- menus that already have the entry (weak keys)
local hoveredBlock -- the tracker quest whose header the cursor last entered

-- Whether links are on and questID is a plain positive whole number.
function EQT.WowheadQuestOK(questID)
    return EQT.Cfg("wowheadQuestLinks")
            and not issecretvalue(questID)
            and type(questID) == "number"
            and questID > 0
            and questID == math.floor(questID)
        or false
end

-- The copy box; WoW Forever's own tracker menu uses it too (Custom.lua).
function EQT.ShowWowheadLink(questID)
    if not EQT.WowheadQuestOK(questID) then return end
    local language = EQT.Cfg("wowheadQuestClientLanguage") and LANGUAGE_PATH[GetLocale()] or ""
    local anchor = EQT.Cfg("wowheadQuestComments") and "#comments" or ""
    local address = "https://www.wowhead.com/"
        .. SITE
        .. language
        .. "quest="
        .. string.format("%.0f", questID)
        .. "/"
        .. anchor
    -- The box translates its own texts.
    CludesUI:ShowInputPopup({
        title = "Wowhead Link",
        message = "Press Ctrl+C to copy, then paste the link into your browser.",
        initialText = address,
        maxLetters = 256,
        confirmText = "Close",
        hideCancel = true,
        selectText = true,
    })
end

local function AddEntry(questID, root)
    if done[root] or not EQT.WowheadQuestOK(questID) then return end
    -- A menu hook also runs for the last menu built when it registers.
    done[root] = true
    root:CreateDivider()
    root:CreateButton(CludesUI.L("Wowhead Link"), function() EQT.ShowWowheadLink(questID) end)
end

-- Quest log rows and the details popup carry their quest (waypoints share
-- the log's menu but have none).
local function OwnQuestMenu(owner, root) AddEntry(owner and owner.questID, root) end

-- The tracker's menu belongs to the tracker, not the quest. It opens from a
-- click on a quest's header, which Blizzard announces when the cursor
-- enters it, so the quest is that header's while the cursor is still there.
local function HeaderEntered(_, block) hoveredBlock = block end
local function TrackerMenu(_, root)
    local header = hoveredBlock and hoveredBlock.HeaderButton
    if header and header:IsMouseOver() then AddEntry(hoveredBlock.id, root) end
end

function EQT.ApplyQuestLinks()
    if not EQT.Cfg("wowheadQuestLinks") then
        if hooks then
            for _, handle in ipairs(hooks) do
                handle:Unregister()
            end
            hooks, hoveredBlock = nil, nil
        end
        return
    end
    if hooks then return end
    done = done or setmetatable({}, { __mode = "k" })
    hooks = {
        Menu.ModifyMenu("MENU_QUEST_MAP_LOG_TITLE", OwnQuestMenu),
        Menu.ModifyMenu("MENU_QUEST_LOG_POPUP_DETAIL_FRAME", OwnQuestMenu),
        Menu.ModifyMenu("MENU_QUEST_OBJECTIVE_TRACKER", TrackerMenu),
        EventRegistry:RegisterCallbackWithHandle("OnQuestBlockHeader.OnEnter", HeaderEntered),
    }
end
