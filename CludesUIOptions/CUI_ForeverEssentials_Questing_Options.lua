if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Questing_Options.lua
--  Forever Tools > Questing: quests and levelling: quest automation, Discovery, the quest list and rares, the guide window, XP per hour and group XP. Each section reads and writes its own feature's
--  keys (the same ones it had on the General page).
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverQuestingPage(_, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    CUI:ClearContentHeader()

    ---------------------------------------------------------------------------
    --  QUEST AUTOMATION
    ---------------------------------------------------------------------------
    local QA = CUI._QuestAutomation
    if QA then
        local function qaOff() return not QA.Get("enabled") end
        local function QASet(key, val)
            QA.Cfg()[key] = val and true or false
            QA.Apply()
        end
        _, height = W:SectionHeader(hostFrame, "QUEST AUTOMATION", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Quest Automation",
            tooltip = "Accepts and turns in quests for you. Hold Shift while talking to an NPC to do it yourself. With a choice of rewards it always stops for you to pick.",
            getValue = function() return not qaOff() end,
            setValue = function(val) QASet("enabled", val) end,
        }, {
            type = "toggle",
            text = "Skip Gray Quests",
            disabled = qaOff,
            tooltip = "Leave quests far below your level alone.",
            getValue = function() return QA.Get("skipGrey") end,
            setValue = function(val) QASet("skipGrey", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auto Accept",
            disabled = qaOff,
            getValue = function() return QA.Get("accept") end,
            setValue = function(val) QASet("accept", val) end,
        }, {
            type = "toggle",
            text = "Auto Turn In",
            disabled = qaOff,
            getValue = function() return QA.Get("turnIn") end,
            setValue = function(val) QASet("turnIn", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Progress to Party",
            disabled = qaOff,
            tooltip = "Says your quest objective progress (Kobold Vermin slain: 4/10) in party chat. Never in a raid.",
            getValue = function() return QA.Get("progress") end,
            setValue = function(val) QASet("progress", val) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  DISCOVERY
    ---------------------------------------------------------------------------
    local DC = CUI._Discovery
    if DC then
        local function dOff() return not DC.Get("enabled") end
        local function Set(key, val)
            DC.Cfg()[key] = val
            DC.Apply()
        end
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = dOff,
                getValue = function() return DC.Get(key) end,
                setValue = function(val) Set(key, val and true or false) end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "DISCOVERY", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_DiscoveryTracker", disabled = dOff, disabledTooltip = "Discovery Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Discovery",
            tooltip = "A window (/cdiscovery) of the library books, the Cozy Sleeping Bag's hidden chain, the Field Journal, and every quest and rare by zone, with trackers and map pins.",
            getValue = function() return not dOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Discovery Window",
            buttonText = "Open",
            width = 90,
            disabled = dOff,
            tooltip = "Opens the Discovery window. Also /cdiscovery.",
            onClick = function() DC.Open() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "tracker",
                "Library Books Tracker",
                "Lists the books still to find in your zone, and the ones you carry. Its X closes it until you enter another zone. Move it in Edit Layout."
            ),
            Tog(
                "bagTracker",
                "Sleeping Bag Tracker",
                "From level 14 until you have the bag, the chain's next step on the same tracker."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("mapPins", "Library Book Pins", "A pin on the world map for each book you still need."),
            Tog(
                "mapTurnIn",
                "Librarian Pin",
                "While you carry books, a pin at the librarian or mage trainer who takes them."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("bagMapPins", "Sleeping Bag Pins", "A pin on the world map at the chain's next step."),
            Tog(
                "fieldJournal",
                "Count the Field Journal",
                "Counts the fish you catch, the herbs you pick from their nodes and the dishes you cook, for this character."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "nearby",
                "Nearby Book Alert",
                "A ping and a chat line when you come within range of a book you still need."
            ),
            {
                type = "slider",
                text = "Alert Range (yards)",
                min = 10,
                max = 100,
                step = 5,
                isPercent = false,
                disabled = dOff,
                getValue = function() return DC.Get("nearbyRange") end,
                setValue = function(val) Set("nearbyRange", math.floor(val + 0.5)) end,
            }
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("nearbyPing", "Alert Sound", "The map ping sound with the alert."),
            Tog("nearbyChat", "Alert Chat Line", "A chat line with the book's name and how far it is.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Map Pin Size",
            min = 12,
            max = 36,
            step = 1,
            isPercent = false,
            disabled = dOff,
            getValue = function() return DC.Get("pinSize") end,
            setValue = function(val) Set("pinSize", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  QUEST LIST AND RARES (Discovery's last two tabs)
    ---------------------------------------------------------------------------
    local QL = CUI._QuestList
    if QL and DC then
        local function qOff() return not DC.Get("enabled") end
        local function Set(key, val)
            QL.Cfg()[key] = val
            QL.Apply()
        end
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = qOff,
                getValue = function() return QL.Get(key) end,
                setValue = function(val) Set(key, val and true or false) end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "QUEST LIST AND RARES", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_RareAlert",
            disabled = function() return qOff() or not QL.Get("rareAlert") end,
            disabledTooltip = "Rare Alert",
        })
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "questPins",
                "Quest Giver Pins",
                "A ! on the world map at each quest giver with a quest you can take now. Green for dungeon quests, blue for repeatable ones."
            ),
            Tog("pinGrey", "Low Level Quests", "Pins givers whose quests are gray to you too.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("chainsOnly", "Chains Only", "Pins only quests that are part of a chain, and dungeon quests."),
            Tog("rarePins", "Rare Pins", "A star on the world map where each rare spawns.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "rarePinsKilled",
                "Pins for Killed Rares",
                "Keeps the stars of rares you have killed, greyed."
            ),
            {
                type = "slider",
                text = "Quest and Rare Pin Size",
                min = 12,
                max = 36,
                step = 1,
                isPercent = false,
                disabled = qOff,
                getValue = function() return QL.Get("pinSize") end,
                setValue = function(val) Set("pinSize", math.floor(val + 0.5)) end,
            }
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "rareAlert",
                "Rare Alerts",
                "A card and a sound when a rare's nameplate, your target, your mouseover or the minimap shows one. Left-click the card to target it, right-click to close it. Move it in Edit Layout."
            ),
            Tog("rareAlertKilled", "Alert for Killed Rares", "Also alerts for rares you have killed before.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("rareSound", "Alert Sound", "The Gruntling Horn with each alert."),
            Tog(
                "rareAlertSkull",
                "Skull on Click",
                "Clicking the card also puts a skull on the rare. Your whole group sees the mark."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Alert Time (seconds)",
            min = 5,
            max = 60,
            step = 1,
            isPercent = false,
            disabled = qOff,
            getValue = function() return QL.Get("rareAlertTime") end,
            setValue = function(val) Set("rareAlertTime", math.floor(val + 0.5)) end,
        }, {
            type = "labeledButton",
            text = "Test the Alert",
            buttonText = "Test",
            width = 90,
            disabled = qOff,
            tooltip = "Shows the card for your target, or a sample rare.",
            onClick = function() QL.TestAlert() end,
        })
        cursorY = cursorY - height
    end

    -- GUIDE WINDOW (CludesUIForeverEssentials_GuideWindow.lua).
    local GUIDE = CUI._GuideWindow
    if GUIDE then
        local function gwOff() return not GUIDE.Get("enabled") end
        local function GWSet(key, val, refresh)
            GUIDE.Cfg()[key] = val
            GUIDE.Apply()
            if refresh then CUI:RefreshPage() end
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        local gwHeading
        gwHeading, height = W:SectionHeader(hostFrame, "GUIDE WINDOW", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(gwHeading, { key = "CUI_GuideWindow", disabled = gwOff, disabledTooltip = "Guide Window" })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "RestedXP Guide Window",
            tooltip = "Shows your RestedXP levelling guide in a CludesUI window in place of RestedXP's own: the guide and its progress, the active steps with their objectives, and the next steps. Shift-click a step to skip it or go to it; right-click for RestedXP's menu. Needs RestedXP with its V2 interface turned on.",
            getValue = function() return GUIDE.Get("enabled") end,
            setValue = function(val) GWSet("enabled", val and true or false, true) end,
        }, {
            type = "dropdown",
            text = "Skipping Steps",
            disabled = gwOff,
            values = { shift = "Shift-click", click = "Click", off = "Off" },
            order = { "shift", "click", "off" },
            getValue = function() return GUIDE.Get("skip") end,
            setValue = function(val) GWSet("skip", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Width",
            min = 260,
            max = 640,
            step = 10,
            isPercent = false,
            disabled = gwOff,
            getValue = function() return GUIDE.Get("width") end,
            setValue = function(val) GWSet("width", math.floor(val + 0.5)) end,
        }, {
            type = "slider",
            text = "Next Steps Shown",
            min = 0,
            max = 12,
            step = 1,
            isPercent = false,
            disabled = gwOff,
            getValue = function() return GUIDE.Get("steps") end,
            setValue = function(val) GWSet("steps", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Lock Window",
            disabled = gwOff,
            getValue = function() return GUIDE.Get("lock") == true end,
            setValue = function(val) GWSet("lock", val and true or false) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  XP PER HOUR AND GROUP XP
    ---------------------------------------------------------------------------
    local XP = CUI._XP
    if XP then
        local xt, gx = XP.ticker, XP.group
        local function Set(f, key, val)
            f.Cfg()[key] = val
            f.Apply()
        end
        local function Tog(f, key, textValue, tipText, off)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, val and true or false) end,
            }
        end
        local function Num(f, key, textValue, min, max, step, off)
            return {
                type = "slider",
                text = textValue,
                min = min,
                max = max,
                step = step,
                isPercent = false,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, math.floor(val + 0.5)) end,
            }
        end
        local function xOff() return not xt.Get("enabled") end
        local function gOff() return not gx.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "XP PER HOUR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_XPTicker", disabled = xOff, disabledTooltip = "XP per Hour" }
        )
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                xt,
                "enabled",
                "XP per Hour",
                "This session's XP per hour, the time to your next level, the session's time and how long your last levels took. Pause and reset on the card, or /cxp start, pause, reset."
            ),
            Tog(xt, "hideResting", "Hide While Resting", nil, xOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(xt, "splits", "Show Level Times", nil, xOff),
            Num(xt, "history", "Levels Shown", 1, 10, 1, xOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(xt, "size", "Text Size", 10, 28, 1, xOff),
            { type = "label", text = "" }
        )
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "GROUP XP", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_GroupXP", disabled = gOff, disabledTooltip = "Group XP" }
        )
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                gx,
                "enabled",
                "Group XP",
                "A bar per group member with their level and XP. They need CludesUI (or another addon that shares group XP)."
            ),
            Tog(gx, "showSelf", "Show Yourself", nil, gOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(gx, "raid", "Also in Raids", nil, gOff),
            Num(gx, "width", "Width", 160, 500, 10, gOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(gx, "size", "Text Size", 8, 20, 1, gOff),
            { type = "label", text = "" }
        )
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
