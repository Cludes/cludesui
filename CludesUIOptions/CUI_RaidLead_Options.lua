if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_RaidLead_Options.lua
--  The Raid Lead page of the CludesUI settings panel: the setup manager's
--  buttons. Each one runs the same code as its /raidlead command.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIRaidLead"
local mod = CUI._ModuleNS[ADDON_NAME]
if not mod then return end

local PAGE = "Setup"

CUI.AtOptionsLogin(function()
    local function Run(cmd)
        return function()
            if mod.Command then mod.Command(cmd) end
        end
    end

    local function BuildPage(_, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height

        CUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "RAID GROUPS", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Sort by Role",
            buttonText = "Sort",
            width = 90,
            tooltip = "Tanks, melee, ranged, then healers, filling group 1 upward. Raid leader or assistant, out of combat.",
            onClick = Run("roles"),
        }, {
            type = "labeledButton",
            text = "Split Into Two Halves",
            buttonText = "Split",
            width = 90,
            tooltip = "Two balanced halves for split runs. Each kind is dealt out in turn, so both sides get the same mix.",
            onClick = Run("split"),
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Put Everyone Back",
            buttonText = "Undo",
            width = 90,
            tooltip = "Back to how the groups were before the last sort or split.",
            onClick = Run("undo"),
        }, {
            type = "labeledButton",
            text = "Stop a Sort",
            buttonText = "Stop",
            width = 90,
            tooltip = "Stops a sort that is under way. Players already moved stay where they are.",
            onClick = Run("stop"),
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "label",
            text = "Melee and ranged are told apart by class, which is a guess for Druids, Shamans and Hunters. Results print in chat.",
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "INVITES", cursorY)
        cursorY = cursorY - height

        local inv = mod.InviteSettings()
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Roster",
            inputWidth = 220,
            placeholder = "Name, Name-Realm, ...",
            tooltip = "Everyone to invite, separated by commas or spaces. Press Enter to save.",
            getValue = function() return inv.list end,
            setValue = function(val) inv.list = val or "" end,
        }, {
            type = "labeledButton",
            text = "Invite the Roster",
            buttonText = "Invite",
            width = 90,
            tooltip = "Invites everyone on the roster who is not in the group yet. A party becomes a raid when it needs to.",
            onClick = function() mod.InviteList() end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Assistants",
            inputWidth = 220,
            placeholder = "Name, Name, ...",
            tooltip = "Players to make raid assistants. Press Enter to save.",
            getValue = function() return inv.promote end,
            setValue = function(val) inv.promote = val or "" end,
        }, {
            type = "labeledButton",
            text = "Promote Assistants Now",
            buttonText = "Promote",
            width = 90,
            onClick = function() mod.PromoteList(false) end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Promote Assistants When They Join",
            tooltip = "While you lead the raid, everyone on the assistants list is promoted as they join.",
            getValue = function() return inv.autoPromote end,
            setValue = function(val) inv.autoPromote = val and true or false end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "READY CHECK", cursorY)
        cursorY = cursorY - height

        local rc = mod.ReadyCheckSettings()
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Gear and Cooldown Check",
            tooltip = "On every ready check, CludesUI users report their durability, item level, missing enchants and raid cooldowns that are not ready. The leader and assistants see a list.",
            getValue = function() return rc.enabled end,
            setValue = function(val) rc.enabled = val and true or false end,
        }, {
            type = "slider",
            text = "Flag Durability Below",
            min = 0,
            max = 100,
            step = 5,
            getValue = function() return rc.minDurability end,
            setValue = function(val) rc.minDurability = math.floor(val + 0.5) end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "See Your Own Report",
            buttonText = "Show",
            width = 90,
            tooltip = "Opens the ready check list with just your own report.",
            onClick = function() mod.ShowReadyWindow() end,
        }, {
            type = "toggle",
            text = "Consumables Check",
            tooltip = "Adds missing flask, food, augment rune and healthstone to each report. Food counts any buff with the Well Fed icon. If the game is hiding buffs from addons at that moment, the report says so.",
            getValue = function() return rc.consumables end,
            setValue = function(val) rc.consumables = val and true or false end,
        })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "BREAK TIMER", cursorY)
        cursorY = cursorY - height
        local bt = mod.BreakSettings()
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Break Timers",
            tooltip = "When the leader or an assistant starts a break, a bar counts it down for every CludesUI user in the group. Move it in Edit Layout.",
            getValue = function() return bt.enabled end,
            setValue = function(val) bt.enabled = val and true or false end,
        }, {
            type = "toggle",
            text = "Sound When It Ends",
            getValue = function() return bt.sound end,
            setValue = function(val) bt.sound = val and true or false end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Start a Break",
            buttonText = "5 min",
            width = 90,
            tooltip = "Starts a 5 minute break for the group. /raidlead break 10 starts one of any length.",
            onClick = function() mod.StartBreak(5) end,
        }, {
            type = "labeledButton",
            text = "End the Break",
            buttonText = "End",
            width = 90,
            onClick = function() mod.StartBreak(0) end,
        })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "KICK ROTATION", cursorY)
        cursorY = cursorY - height
        local ks = mod.KickSettings()
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Kick Rotation",
            tooltip = "Shows whose interrupt is next. The order comes from an intstart / intend block in the boss's note (one line of names per rotation), or the Kick Order below for other fights. Each cast of the tracked unit moves the turn on.",
            getValue = function() return ks.enabled end,
            setValue = function(val) ks.enabled = val and true or false end,
        }, {
            type = "segmented",
            text = "Track",
            values = { focus = "Focus", boss1 = "Boss 1" },
            order = { "focus", "boss1" },
            tooltip = "The unit whose casts count. Put the mob you kick on focus.",
            getValue = function() return ks.unit end,
            setValue = function(val) ks.unit = val end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Kick Order",
            inputWidth = 160,
            inputStyle = "popup",
            placeholder = "Alice Bob Carol",
            tooltip = "Names in kick order, separated by spaces, for fights without a note block. Nicknames work.",
            getValue = function() return ks.order end,
            setValue = function(textValue) ks.order = (textValue or ""):match("^%s*(.-)%s*$") end,
        }, {
            type = "labeledButton",
            text = "Preview",
            buttonText = "Show",
            width = 90,
            tooltip = "Shows the box for a few seconds so you can place it in Edit Layout.",
            onClick = function() mod.PreviewKicks() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Sound on Your Turn",
            getValue = function() return ks.sound end,
            setValue = function(val) ks.sound = val and true or false end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "VERSIONS", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Check CludesUI Versions",
            buttonText = "Check",
            width = 90,
            tooltip = "Asks everyone in the group which CludesUI version they run. The answer prints in chat after a few seconds.",
            onClick = function() mod.VersionCheck() end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Tracking page: Immunities on You and Boss Pace
    ---------------------------------------------------------------------------
    local PAGE_TRACKING = "Tracking"
    local PAGE_NICKNAMES = "Nicknames"

    local function Refresh()
        CUI:InvalidatePageCache()
        CUI:RefreshPage(true)
    end

    local function BuildTrackingPage(_, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height
        local im, pace = mod.ImmunitySettings(), mod.PaceSettings()

        CUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "IMMUNITIES ON YOU", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Immunities on You",
            tooltip = "Icons for Divine Shield, Blessing of Protection, Blessing of Spellwarding, Ice Block, Aspect of the Turtle and Cloak of Shadows while they are on you. Works in combat. Move it in Edit Layout.",
            getValue = function() return im.enabled end,
            setValue = function(val)
                im.enabled = val and true or false
                mod.RefreshImmunities()
            end,
        }, {
            type = "slider",
            text = "Icon Size",
            min = 20,
            max = 64,
            step = 1,
            getValue = function() return im.size end,
            setValue = function(val)
                im.size = math.floor(val + 0.5)
                mod.RefreshImmunities()
            end,
        })
        cursorY = cursorY - height
        local extra = {}
        for _, ident in ipairs(im.extra) do
            local num = C_Spell.GetSpellName(ident)
            extra[#extra + 1] = (type(num) == "string" and num or "Spell") .. " (" .. ident .. ")"
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Add an Immunity",
            inputStyle = "popup",
            placeholder = "Spell ID",
            inputWidth = 110,
            tooltip = "The spell ID of another immunity buff to show.",
            getValue = function() return "" end,
            setValue = function(textValue)
                local ident = tonumber(textValue)
                if ident and ident > 0 then
                    table.insert(im.extra, math.floor(ident))
                    mod.RefreshImmunities()
                    Refresh()
                end
            end,
        }, #extra > 0 and {
            type = "labeledButton",
            text = "Added: " .. table.concat(extra, ", "),
            buttonText = "Clear",
            width = 90,
            onClick = function()
                wipe(im.extra)
                mod.RefreshImmunities()
                Refresh()
            end,
        } or { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "AURA GLOWS", cursorY)
        cursorY = cursorY - height
        local ag = mod.AuraGlowSettings()
        local glowNames = {}
        for _, ident in ipairs(ag.spells) do
            local num = C_Spell.GetSpellName(ident)
            glowNames[#glowNames + 1] = (type(num) == "string" and num or "Spell") .. " (" .. ident .. ")"
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Aura Glows",
            tooltip = "While an aura you add here is on you, its icon shows with a glowing border and its time. Works in boss fights. Changes apply out of combat. Move it in Edit Layout.",
            getValue = function() return ag.enabled end,
            setValue = function(val)
                ag.enabled = val and true or false
                mod.RebuildAuraGlows()
            end,
        }, {
            type = "slider",
            text = "Icon Size",
            min = 20,
            max = 80,
            step = 1,
            getValue = function() return ag.size end,
            setValue = function(val)
                ag.size = math.floor(val + 0.5)
                mod.RebuildAuraGlows()
            end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Add an Aura",
            inputStyle = "popup",
            placeholder = "Spell IDs",
            inputWidth = 110,
            tooltip = "The spell ID of a buff or debuff to glow for. Several, separated by commas or spaces, work too.",
            getValue = function() return "" end,
            setValue = function(textValue)
                for _, ident in ipairs(mod.ParseSpellIDs(textValue)) do
                    table.insert(ag.spells, ident)
                end
                mod.RebuildAuraGlows()
                Refresh()
            end,
        }, #glowNames > 0 and {
            type = "labeledButton",
            text = "Added: " .. table.concat(glowNames, ", "),
            buttonText = "Clear",
            width = 90,
            onClick = function()
                wipe(ag.spells)
                mod.RebuildAuraGlows()
                Refresh()
            end,
        } or { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "GROUP HELPERS", cursorY)
        cursorY = cursorY - height
        local hs = mod.HelperSettings()
        local function HSet(key, val)
            hs[key] = val and true or false
            mod.RefreshHelpers()
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Feast and Cauldron Alerts",
            tooltip = "A chat line naming who dropped a feast, cauldron, Soulwell or repair bot. Only drops by CludesUI users are seen: the game shows addons no one else's casts.",
            getValue = function() return hs.drops end,
            setValue = function(val) HSet("drops", val) end,
        }, {
            type = "toggle",
            text = "Alert Sound",
            getValue = function() return hs.dropSound end,
            setValue = function(val) HSet("dropSound", val) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Gateway Usable",
            tooltip = "Gateway usable shows while you are close enough to a warlock's Demonic Gateway to click it. Move it in Edit Layout.",
            getValue = function() return hs.gateway end,
            setValue = function(val) HSet("gateway", val) end,
        }, {
            type = "toggle",
            text = "Stats Panel",
            tooltip = "Your crit, haste, mastery and versatility on screen, kept up to date through procs. Move it in Edit Layout.",
            getValue = function() return hs.stats end,
            setValue = function(val) HSet("stats", val) end,
        })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "BOSS PACE", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Boss Pace",
            tooltip = "A bar with the boss's health and a marker for where it should be to kill it in your target time: green while ahead, red while behind. The pace is a straight line, so phases and intermissions throw it off. Move it in Edit Layout.",
            getValue = function() return pace.enabled end,
            setValue = function(val) pace.enabled = val and true or false end,
        }, {
            type = "input",
            text = "Add a Boss",
            inputStyle = "popup",
            placeholder = "Boss name",
            inputWidth = 160,
            tooltip = "The boss's name as the game shows it at the pull. Set its target kill time below.",
            getValue = function() return "" end,
            setValue = function(textValue)
                textValue = textValue and textValue:match("^%s*(.-)%s*$") or ""
                if textValue ~= "" then
                    table.insert(pace.targets, { boss = textValue, seconds = 300 })
                    Refresh()
                end
            end,
        })
        cursorY = cursorY - height
        for idx, t in ipairs(pace.targets) do
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "input",
                text = t.boss .. ": Target Kill Time",
                inputWidth = 80,
                placeholder = "5:00",
                tooltip = "Minutes and seconds, like 5:30. Press Enter to save.",
                getValue = function() return mod.FormatDuration(t.seconds) end,
                setValue = function(textValue)
                    local s = mod.ParseDuration(textValue)
                    if s and s > 0 then t.seconds = s end
                end,
            }, {
                type = "labeledButton",
                text = "Try It Now",
                buttonText = "Test",
                width = 70,
                tooltip = "Shows the bar for this boss now, with your target as the clock. With no boss targeted the bar stays empty.",
                onClick = function() mod.StartPace(t.boss, t.seconds) end,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Remove " .. t.boss,
                buttonText = "Remove",
                width = 90,
                onClick = function()
                    table.remove(pace.targets, idx)
                    Refresh()
                end,
            }, { type = "label", text = "" })
            cursorY = cursorY - height
        end

        if mod.TimelineSettings then
            local tl = mod.TimelineSettings()
            _, height = W:SectionHeader(hostFrame, "BOSS TIMELINES", cursorY)
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Upcoming Ability Bars",
                tooltip = "During a Midnight raid boss, the next abilities as countdown bars, colored by kind of mechanic. Each phase runs from when it really began, read from the boss's timeline; phases still to come are estimates, shown faded. Move them in Edit Layout.",
                getValue = function() return tl.bars end,
                setValue = function(val) tl.bars = val and true or false end,
            }, {
                type = "toggle",
                text = "Encounter Alerts",
                tooltip = "Timed calls on the reminder display a few seconds before each mechanic (Soak, Spread, Defensives), only the ones for your role, restarted at each phase change.",
                getValue = function() return tl.alerts end,
                setValue = function(val) tl.alerts = val and true or false end,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Only My Role",
                tooltip = "Bars and the timeline window show only the mechanics for your role: raid damage and soaks for healers, tankbusters and frontals for tanks.",
                getValue = function() return tl.mine end,
                setValue = function(val) tl.mine = val and true or false end,
            }, {
                type = "toggle",
                text = "Speak Alerts",
                tooltip = "Text to speech says each alert as it shows.",
                getValue = function() return tl.tts end,
                setValue = function(val) tl.tts = val and true or false end,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Bars Shown",
                min = 3,
                max = 12,
                step = 1,
                isPercent = false,
                getValue = function() return tl.count end,
                setValue = function(val) tl.count = math.floor(val + 0.5) end,
            }, {
                type = "slider",
                text = "Look Ahead (seconds)",
                min = 10,
                max = 60,
                step = 5,
                isPercent = false,
                getValue = function() return tl.ahead end,
                setValue = function(val) tl.ahead = math.floor(val + 0.5) end,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Boss Timeline Window",
                buttonText = "Open",
                width = 90,
                tooltip = "Each boss's abilities and when they come, Heroic or Mythic, with Test to run one as if pulled. Also /cbt.",
                onClick = function() mod.OpenTimeline() end,
            }, {
                type = "toggle",
                text = "Say Phase Changes",
                tooltip = "A chat line when a phase change is read, to check the timings against the fight.",
                getValue = function() return tl.phaseChat end,
                setValue = function(val) tl.phaseChat = val and true or false end,
            })
            cursorY = cursorY - height
        end

        return math.abs(cursorY)
    end

    local function BuildNicknamesPage(_, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height

        CUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "NICKNAMES", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Your Nickname",
            inputWidth = 160,
            placeholder = "Nickname",
            tooltip = "Sent to your guild when you log in and to your group when it changes. Other CludesUI users see it on their raid and unit frames. Press Enter to save.",
            getValue = function() return mod.MyNickname() end,
            setValue = function(textValue)
                mod.SetMyNickname(textValue)
                Refresh()
            end,
        }, {
            type = "toggle",
            text = "Show CludesUI Nicknames",
            tooltip = "Raid frames show nicknames in place of character names. Unit frames also need their own Show Nicknames setting on.",
            getValue = function() return not CludesUIDB.cuiNicknamesOff end,
            setValue = function(val) CludesUIDB.cuiNicknamesOff = not val or nil end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Paste Nicknames",
            buttonText = "Paste",
            width = 90,
            tooltip = 'One "Character=Nickname" per line.',
            onClick = function()
                CUI:ShowImportPopup(function(str)
                    local num = mod.ImportNicknames(str)
                    CUI.Print(
                        ("|cff4cc9f0Raid Lead:|r added %d nickname%s."):format(num, num == 1 and "" or "s")
                    )
                    Refresh()
                end, "Nicknames", "One Character=Nickname per line")
            end,
        }, { type = "label", text = "Known nicknames: " .. mod.NicknameCount() })
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Reminders page
    ---------------------------------------------------------------------------
    local PAGE_REMINDERS = "Reminders"

    local function Redraw()
        CUI:InvalidatePageCache()
        CUI:RefreshPage(true)
    end
    mod.OnSharedChanged = function()
        if CUI._mainFrame and CUI._mainFrame:IsShown() then Redraw() end
    end

    local function Summary(textValue)
        local entries, skipped = mod.NoteParser.Parse(textValue or "", function(ident)
            local num = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
            return type(num) == "string" and num or nil
        end)
        local text = #entries .. " reminder" .. (#entries == 1 and "" or "s")
        if skipped > 0 then
            text = text .. ", " .. skipped .. " phase line" .. (skipped == 1 and "" or "s") .. " skipped"
        end
        return text
    end

    local function BuildRemindersPage(_, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height
        local r = mod.ReminderSettings()

        CUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "REMINDERS", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show Encounter Reminders",
            tooltip = "When a boss is pulled, its note's lines for you appear before their time with a countdown. Move them in Edit Layout.",
            getValue = function() return r.enabled end,
            setValue = function(val) r.enabled = val and true or false end,
        }, {
            type = "toggle",
            text = "Accept Reminders From the Raid Leader",
            tooltip = "Notes the leader or an assistant sends replace your own for that boss, for this session.",
            getValue = function() return r.acceptShared end,
            setValue = function(val) r.acceptShared = val and true or false end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Show Seconds Before",
            min = 1,
            max = 10,
            step = 1,
            getValue = function() return r.lead end,
            setValue = function(val) r.lead = math.floor(val + 0.5) end,
        }, {
            type = "slider",
            text = "Text Size",
            min = 14,
            max = 48,
            step = 1,
            getValue = function() return r.fontSize end,
            setValue = function(val)
                r.fontSize = math.floor(val + 0.5)
                mod.ApplyReminderLook()
            end,
        })
        cursorY = cursorY - height

        local soundValues, soundOrder = { [""] = "None" }, { "" }
        for _, f in ipairs(mod.SOUND_FILES) do
            soundValues[f] = f:gsub("%.%a+$", ""):gsub("(%l)(%u)", "%1 %2")
            soundOrder[#soundOrder + 1] = f
        end
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Speak Reminders",
            tooltip = "Reads each reminder aloud with the game's text to speech voice.",
            getValue = function() return r.tts end,
            setValue = function(val) r.tts = val and true or false end,
        }, {
            type = "dropdown",
            text = "Reminder Sound",
            values = soundValues,
            order = soundOrder,
            getValue = function() return r.sound or "" end,
            setValue = function(val)
                r.sound = val
                if val ~= "" then mod.PreviewSound(val) end
            end,
        })
        cursorY = cursorY - height

        _, height = W:SectionHeader(hostFrame, "BOSS NOTES", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Add a Boss",
            inputStyle = "popup",
            placeholder = "Boss name",
            inputWidth = 160,
            tooltip = 'The boss\'s name as the game shows it at the pull. Use "any" for a note that runs on every boss.',
            getValue = function() return "" end,
            setValue = function(textValue)
                textValue = textValue and textValue:match("^%s*(.-)%s*$") or ""
                if textValue == "" then return end
                table.insert(r.notes, { boss = textValue, text = "" })
                Redraw()
            end,
        }, {
            type = "label",
            text = "Lines are {time:1:30} then the text. Names on a line make it theirs; {tank}, {healer}, {dps} and {everyone} work too.",
        })
        cursorY = cursorY - height

        for idx, note in ipairs(r.notes) do
            _, height =
                W:SectionHeader(hostFrame, note.boss:upper() .. "  -  " .. Summary(note.text), cursorY)
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Paste or Replace the Note",
                buttonText = "Paste",
                width = 90,
                tooltip = "Paste a note from wowutils, wowaudit or a Method Raid Tools note.",
                onClick = function()
                    CUI:ShowImportPopup(function(str)
                        note.text = str or ""
                        Redraw()
                    end, "Reminders for " .. note.boss, "Paste the note, then press Save")
                end,
            }, {
                type = "labeledButton",
                text = "Try It Now",
                buttonText = "Test",
                width = 90,
                tooltip = "Runs the note as if the boss was pulled now. Lines for you appear on screen.",
                onClick = function()
                    local num, skipped = mod.RunNote(note.text)
                    CUI.Print(
                        ("|cff4cc9f0Raid Lead:|r testing %s: %d reminder%s for you%s."):format(
                            note.boss,
                            num,
                            num == 1 and "" or "s",
                            skipped > 0 and (", " .. skipped .. " phase lines skipped") or ""
                        )
                    )
                end,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "labeledButton",
                text = "Send to the Group",
                buttonText = "Send",
                width = 90,
                tooltip = "Sends this note to everyone in the group who runs CludesUI. Leader or assistant only.",
                onClick = function() mod.ShareNote(note.boss, note.text) end,
            }, {
                type = "labeledButton",
                text = "Remove This Note",
                buttonText = "Remove",
                width = 90,
                onClick = function()
                    table.remove(r.notes, idx)
                    Redraw()
                end,
            })
            cursorY = cursorY - height
        end

        local sharedAny = next(mod.sharedNotes)
        if sharedAny then
            _, height = W:SectionHeader(hostFrame, "SENT BY THE RAID LEADER (THIS SESSION)", cursorY)
            cursorY = cursorY - height
            for boss, s in pairs(mod.sharedNotes) do
                _, height = W:DualRow(
                    hostFrame,
                    cursorY,
                    { type = "label", text = boss .. ", from " .. s.from .. ": " .. Summary(s.text) },
                    {
                        type = "labeledButton",
                        text = "Forget It",
                        buttonText = "Forget",
                        width = 90,
                        onClick = function()
                            mod.sharedNotes[boss] = nil
                            Redraw()
                        end,
                    }
                )
                cursorY = cursorY - height
            end
        end

        return math.abs(cursorY)
    end

    ---------------------------------------------------------------------------
    --  Aura Sounds page
    ---------------------------------------------------------------------------
    local PAGE_SOUNDS = "Aura Sounds"

    local function Rebuild()
        mod.RebuildAuraSounds()
        CUI:InvalidatePageCache()
        CUI:RefreshPage(true)
    end

    local soundValues, soundOrder = {}, {}
    for _, f in ipairs(mod.SOUND_FILES) do
        soundValues[f] = f:gsub("%.%a+$", ""):gsub("(%l)(%u)", "%1 %2")
        soundOrder[#soundOrder + 1] = f
    end
    local whenValues, whenOrder = {}, {}
    for _, wid in ipairs(mod.SOUND_WHEN) do
        whenValues[wid.id] = wid.label
        whenOrder[#whenOrder + 1] = wid.id
    end

    local function SpellName(ident)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
        if type(name) == "string" and name ~= "" then return name end
        return "Spell " .. ident
    end

    local function BuildSoundsPage(_, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height
        local entries = mod.RaidLeadDB().sounds

        CUI:ClearContentHeader()

        _, height = W:SectionHeader(hostFrame, "AURA SOUNDS", cursorY)
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "input",
            text = "Add a Spell ID",
            inputStyle = "popup",
            placeholder = "Spell ID",
            inputWidth = 110,
            tooltip = "The spell ID of a buff or debuff that lands on you. It plays a siren when applied; change that below. The game plays these itself, so they work in boss fights.",
            getValue = function() return "" end,
            setValue = function(textValue)
                local ident = tonumber(textValue)
                if not ident or ident <= 0 then return end
                entries[#entries + 1] =
                    { id = math.floor(ident), when = "added", sound = "WarningSiren.ogg", on = true }
                Rebuild()
            end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        for idx, entry in ipairs(entries) do
            local name = SpellName(entry.id)
            _, height = W:SectionHeader(hostFrame, name:upper(), cursorY)
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Play a Sound for " .. name,
                tooltip = "Spell ID " .. entry.id,
                getValue = function() return entry.on ~= false end,
                setValue = function(val)
                    entry.on = val and true or false
                    mod.RebuildAuraSounds()
                end,
            }, {
                type = "dropdown",
                text = "Play When",
                values = whenValues,
                order = whenOrder,
                getValue = function() return entry.when or "added" end,
                setValue = function(val)
                    entry.when = val
                    mod.RebuildAuraSounds()
                end,
            })
            cursorY = cursorY - height
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Sound",
                values = soundValues,
                order = soundOrder,
                getValue = function() return entry.sound or "WarningSiren.ogg" end,
                setValue = function(val)
                    entry.sound = val
                    mod.PreviewSound(val)
                    mod.RebuildAuraSounds()
                end,
            }, {
                type = "labeledButton",
                text = "Remove This Sound",
                buttonText = "Remove",
                width = 90,
                onClick = function()
                    table.remove(entries, idx)
                    Rebuild()
                end,
            })
            cursorY = cursorY - height
        end

        return math.abs(cursorY)
    end

    CUI:RegisterModule(ADDON_NAME, {
        title = "Raid Lead",
        description = "Tools for raid leaders: sort or split the raid, and sounds for auras on you.",
        pages = { PAGE, PAGE_REMINDERS, PAGE_TRACKING, PAGE_SOUNDS, PAGE_NICKNAMES },
        buildPage = function(page, hostFrame, yOffset)
            if page == PAGE then return BuildPage(page, hostFrame, yOffset) end
            if page == PAGE_REMINDERS then return BuildRemindersPage(page, hostFrame, yOffset) end
            if page == PAGE_TRACKING then return BuildTrackingPage(page, hostFrame, yOffset) end
            if page == PAGE_NICKNAMES then return BuildNicknamesPage(page, hostFrame, yOffset) end
            if page == PAGE_SOUNDS then return BuildSoundsPage(page, hostFrame, yOffset) end
        end,
    })
end)
