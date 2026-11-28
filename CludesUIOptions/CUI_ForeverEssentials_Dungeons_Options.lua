if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Dungeons_Options.lua
--  Forever Tools > Dungeons: everything for dungeons and raids in one place:
--  the Dungeon Journal, Dungeon Map and Boss Kill History, the CC Marker
--  Bar, Looking For Group, Group Inspect, the Instance Tracker and Raid
--  Debuffs. Each section reads and writes its own feature's keys (the same
--  ones it had on the General page).
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverDungeonsPage(_, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    CUI:ClearContentHeader()

    ---------------------------------------------------------------------------
    --  DUNGEON JOURNAL
    ---------------------------------------------------------------------------
    if CUI._Journal then
        _, height = W:SectionHeader(hostFrame, "DUNGEON JOURNAL", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Dungeon Journal",
            buttonText = "Open",
            width = 90,
            tooltip = "Every dungeon and raid: bosses in kill order, their loot and drop chances, a tip per boss, and the quests. Alt+Shift-click an item to add it to your BiS list. /cjournal opens it too.",
            onClick = function() CUI._Journal.Show() end,
        }, { type = "label", text = "Opens on the dungeon you are in." })
        cursorY = cursorY - height
        local DM = CUI._DungeonMap
        if DM then
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Dungeon Map",
                tooltip = "Inside a dungeon, a small map with the route: bosses numbered in kill order and joined by a line, the next one ringed, killed ones dimmed. It turns to the next boss's floor and moves on with each kill. /cdmap shows or hides it; move it in Edit Layout.",
                getValue = function() return DM.Get("enabled") end,
                setValue = function(val)
                    DM.Cfg().enabled = val and true or false
                    DM.Apply()
                    CUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Open on Entering",
                tooltip = "Opens the Dungeon Map when you enter a dungeon, and closes it when you leave.",
                disabled = function() return not DM.Get("enabled") end,
                disabledTooltip = "Dungeon Map",
                getValue = function() return DM.Get("autoShow") end,
                setValue = function(val)
                    DM.Cfg().autoShow = val and true or false
                    DM.Apply()
                end,
            })
            cursorY = cursorY - height
        end
        local DQ = CUI._DungeonQuests
        if DQ then
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Dungeon Quests on Entering",
                tooltip = "A chat line as you enter a dungeon: how many of its quests are in your log, and how many you have not picked up yet (with where the first is given). The Dungeon Map's Quests button lists them; click it to share yours with your group.",
                getValue = function() return DQ.Get("summary") end,
                setValue = function(val)
                    DQ.Cfg().summary = val and true or false
                    DQ.Apply()
                end,
            }, {
                type = "toggle",
                text = "Accept Shared Dungeon Quests",
                tooltip = "A dungeon quest a group member shares with you is accepted as it opens. Other quests still ask.",
                getValue = function() return DQ.Get("acceptShared") end,
                setValue = function(val)
                    DQ.Cfg().acceptShared = val and true or false
                    DQ.Apply()
                end,
            })
            cursorY = cursorY - height
        end
        local BK = CUI._BossKills
        if BK then
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Boss Kill History",
                tooltip = "Remembers each boss this character kills: how many times, when, how long the fight took and who was with you. The Journal and the Dungeon Map show it under each boss, and a fight faster than your best says so in chat.",
                getValue = function() return BK.Get("enabled") end,
                setValue = function(val)
                    BK.Cfg().enabled = val and true or false
                    BK.Apply()
                end,
            }, {
                type = "labeledButton",
                text = "Forget This Character's Kills",
                buttonText = "Forget",
                width = 90,
                onClick = function() BK.Forget() end,
            })
            cursorY = cursorY - height
        end
    end

    ---------------------------------------------------------------------------
    --  CC MARKER BAR
    ---------------------------------------------------------------------------
    local CC = CUI._CCMarks
    if CC then
        local function Set(key, val)
            CC.Cfg()[key] = val
            CC.Apply()
        end
        local function cOff() return not CC.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "CC MARKER BAR", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, { key = "CUIFE_CCMarks", disabled = cOff, disabledTooltip = "CC Marker Bar" })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "CC Marker Bar",
            tooltip = "A bar with the raid marks, plus CC: target a mob and press it to give it the crowd control that works on it (Polymorph, Sap, Shackle Undead, Hibernate, Banish or Freezing Trap) from someone in your group who can cast it, mark it and say so in chat. Shift-drag to move it; /ccmark shows or hides it; key binding under CludesUI CC Marker Bar.",
            getValue = function() return not cOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only in Dungeons and Raids",
            disabled = cOff,
            tooltip = "Shows the bar only inside dungeons and raids.",
            getValue = function() return CC.Get("instancesOnly") end,
            setValue = function(val) Set("instancesOnly", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Announce in Chat",
            disabled = cOff,
            tooltip = "Each assignment goes to group chat as you make it, e.g. {Moon} Polymorph: Frostbolt.",
            getValue = function() return CC.Get("announce") end,
            setValue = function(val) Set("announce", val and true or false) end,
        }, {
            type = "toggle",
            text = "Whisper the Player",
            disabled = cOff,
            tooltip = "Also whispers the player you gave the crowd control to.",
            getValue = function() return CC.Get("whisper") end,
            setValue = function(val) Set("whisper", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Clear After Each Fight",
            disabled = cOff,
            tooltip = "Forgets the assignments when combat ends, ready for the next pull.",
            getValue = function() return CC.Get("resetAfterCombat") end,
            setValue = function(val) Set("resetAfterCombat", val and true or false) end,
        }, {
            type = "slider",
            text = "Bar Scale",
            min = 0.6,
            max = 1.6,
            step = 0.05,
            isPercent = false,
            disabled = cOff,
            tooltip = "Makes the bar bigger or smaller.",
            getValue = function() return CC.Get("scale") end,
            setValue = function(val) Set("scale", math.floor(val * 100 + 0.5) / 100) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  RES HELPER
    ---------------------------------------------------------------------------
    local RH = CUI._ResHelper
    if RH then
        local function rOff() return not RH.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "RES HELPER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, { key = "CUIFE_ResHelper", disabled = rOff, disabledTooltip = "Res Helper" })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Res Helper",
            tooltip = "After a wipe, a list of your dead group members: click a name to cast your resurrection on them. Shows out of combat, in a group, when you know a resurrection (Priest, Paladin, Shaman or Druid). Players already being resurrected are marked.",
            getValue = function() return not rOff() end,
            setValue = function(val)
                RH.Cfg().enabled = val and true or false
                RH.Apply()
            end,
        }, {
            type = "toggle",
            text = "Say Who You Resurrect",
            disabled = rOff,
            tooltip = "Says \"Resurrecting <name>\" in group chat as you start, so two healers do not pick the same player.",
            getValue = function() return RH.Get("announce") end,
            setValue = function(val)
                RH.Cfg().announce = val and true or false
                RH.Apply()
            end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  INTERRUPT TRACKER
    ---------------------------------------------------------------------------
    local KT = CUI._KickTracker
    if KT then
        local function kOff() return not KT.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "INTERRUPT TRACKER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, { key = "CUIFE_KickTracker", disabled = kOff, disabledTooltip = "Interrupt Tracker" })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Interrupt Tracker",
            tooltip = "Your group's interrupts (Kick, Pummel or Shield Bash, Earth Shock, Counterspell) in a small list: ready or how long until it is, the first ready one marked next. Read from your group's casts, so it works for everyone.",
            getValue = function() return not kOff() end,
            setValue = function(val)
                KT.Cfg().enabled = val and true or false
                KT.Apply()
            end,
        }, {
            type = "toggle",
            text = "Only in Dungeons and Raids",
            disabled = kOff,
            tooltip = "Shows the list only inside dungeons and raids.",
            getValue = function() return KT.Get("instancesOnly") end,
            setValue = function(val)
                KT.Cfg().instancesOnly = val and true or false
                KT.Apply()
            end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  WHO PULLED
    ---------------------------------------------------------------------------
    local PW = CUI._PullWatch
    if PW then
        local function wOff() return not PW.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "WHO PULLED", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Who Pulled",
            tooltip = "In a dungeon or raid group, says who was first into each fight, e.g. Pull: Sneaky on Defias Thug, or Holy was attacked first when a mob came to the group.",
            getValue = function() return not wOff() end,
            setValue = function(val)
                PW.Cfg().enabled = val and true or false
                PW.Apply()
            end,
        }, {
            type = "toggle",
            text = "Say in Group",
            disabled = wOff,
            tooltip = "Also says it in group chat. Off, only you see it.",
            getValue = function() return PW.Get("say") end,
            setValue = function(val)
                PW.Cfg().say = val and true or false
                PW.Apply()
            end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  LOOKING FOR GROUP
    ---------------------------------------------------------------------------
    local LF = CUI._LFG
    if LF then
        local function Set(key, val)
            LF.Cfg()[key] = val
            LF.Apply()
        end
        local function lOff() return not LF.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "LOOKING FOR GROUP", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Looking For Group",
            buttonText = "Open",
            width = 90,
            tooltip = "A better window for the game's group finder: every listing for your level with the leader's zone, roles and age, a filter and sorts, and Whisper on each. CludesUI players also see each other's Gear Score, boss kills and quests, and can apply to a group and be invited. /clfg opens it too.",
            onClick = function()
                LF.Show()
                CUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Looking For Group",
            tooltip = "Turns it on (opening the window does too). While you are listed, CludesUI players can ask for your card and apply.",
            getValue = function() return not lOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Share My Gear Score",
            disabled = lOff,
            tooltip = "Your Gear Score on the card other CludesUI players see.",
            getValue = function() return LF.Get("shareScore") end,
            setValue = function(val) Set("shareScore", val and true or false) end,
        }, {
            type = "toggle",
            text = "Share My Boss Kills",
            disabled = lOff,
            tooltip = "How often you have killed each boss of the dungeon (from Boss Kill History).",
            getValue = function() return LF.Get("shareKills") end,
            setValue = function(val) Set("shareKills", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Share My Quests",
            disabled = lOff,
            tooltip = "The dungeon's quests in your log, and the ones you still need.",
            getValue = function() return LF.Get("shareQuests") end,
            setValue = function(val) Set("shareQuests", val and true or false) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  GROUP INSPECT
    ---------------------------------------------------------------------------
    if CUI._GroupInspect then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "GROUP INSPECT", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Group Inspect",
            buttonText = "Open",
            width = 90,
            tooltip = "Everyone in your group with their level, item level and unenchanted slots. Click a name to open the game's inspect window on them. /cinspect opens it too.",
            onClick = function() CUI._GroupInspect.Show() end,
        }, { type = "label", text = "Players out of range answer when they come closer." })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  INSTANCE TRACKER
    ---------------------------------------------------------------------------
    local IT = CUI._InstanceTracker
    if IT then
        local function itOff() return not IT.Get("enabled") end
        local function ITSet(key, val)
            IT.Cfg()[key] = val
            IT.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "INSTANCE TRACKER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_InstanceTracker", disabled = itOff, disabledTooltip = "Instance Tracker" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Instance Tracker",
            tooltip = "Counts the new dungeons and raids your account enters in a rolling hour against the cap, times your runs, and prints a summary when you leave. Re-entering the same copy does not count again.",
            getValue = function() return not itOff() end,
            setValue = function(val) ITSet("enabled", val and true or false) end,
        }, {
            type = "slider",
            text = "Hourly Cap",
            min = 1,
            max = 30,
            step = 1,
            isPercent = false,
            disabled = itOff,
            tooltip = "WoW Forever allows 10 new instances an hour per account. Change this only if the game does.",
            getValue = function() return IT.Get("cap") end,
            setValue = function(val) ITSet("cap", math.floor(val + 0.5)) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show the Counter",
            disabled = itOff,
            getValue = function() return IT.Get("hud") end,
            setValue = function(val) ITSet("hud", val and true or false) end,
        }, {
            type = "toggle",
            text = "Summary When You Leave",
            disabled = itOff,
            getValue = function() return IT.Get("summary") end,
            setValue = function(val) ITSet("summary", val and true or false) end,
        })
        cursorY = cursorY - height
        if not itOff() then
            local runs = IT.Runs()
            for idx = 1, math.min(#runs, 6), 2 do
                local function Run(r)
                    if not r then return { type = "label", text = "" } end
                    return {
                        type = "label",
                        text = ("%s  |cff9aa6b2%d:%02d, %d deaths, %d items|r"):format(
                            r.name or "?",
                            math.floor(r.seconds / 60),
                            r.seconds % 60,
                            r.deaths or 0,
                            r.items or 0
                        ),
                    }
                end
                _, height = W:DualRow(hostFrame, cursorY, Run(runs[idx]), Run(runs[idx + 1]))
                cursorY = cursorY - height
            end
        end
    end

    ---------------------------------------------------------------------------
    --  RAID DEBUFFS
    ---------------------------------------------------------------------------
    local RD = CUI._RaidDebuffs
    if RD then
        local function rdOff() return not RD.Get("enabled") end
        local function RDSet(key, val)
            RD.Cfg()[key] = val
            RD.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "RAID DEBUFFS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_RaidDebuffs", disabled = rdOff, disabledTooltip = "Raid Debuffs" }
        )
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Raid Debuffs",
            tooltip = "Icons on your enemy target for the raid debuffs you pick: bright while up with their time, dim while missing. Changes to the picks apply out of combat.",
            getValue = function() return not rdOff() end,
            setValue = function(val) RDSet("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Only in a Group",
            disabled = rdOff,
            getValue = function() return RD.Get("groupOnly") end,
            setValue = function(val) RDSet("groupOnly", val and true or false) end,
        })
        cursorY = cursorY - height
        local entries = RD.Debuffs
        for idx = 1, #entries, 2 do
            local function Toggle(d)
                if not d then return { type = "label", text = "" } end
                return {
                    type = "toggle",
                    text = d.label,
                    disabled = rdOff,
                    getValue = function() return RD.Get("pick_" .. d.key) end,
                    setValue = function(val) RDSet("pick_" .. d.key, val and true or false) end,
                }
            end
            _, height = W:DualRow(hostFrame, cursorY, Toggle(entries[idx]), Toggle(entries[idx + 1]))
            cursorY = cursorY - height
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            disabled = rdOff,
            getValue = function() return RD.Get("iconSize") end,
            setValue = function(val) RDSet("iconSize", math.floor(val + 0.5)) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
