if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidLead_Options.lua
--  The Raid Lead page of the CludesUI settings panel: the setup manager's
--  buttons. Each one runs the same code as its /raidlead command.
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIRaidLead"
local ns = CludesUI._ModuleNS[ADDON_NAME]
if not ns then return end

local PAGE = "Setup"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CludesUI or not CludesUI.RegisterModule then return end

    local function Run(cmd)
        return function() if ns.Command then ns.Command(cmd) end end
    end

    local function BuildPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "RAID GROUPS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Sort by Role", buttonText = "Sort", width = 90,
              tooltip = "Tanks, melee, ranged, then healers, filling group 1 upward. Raid leader or assistant, out of combat.",
              onClick = Run("roles") },
            { type = "labeledButton", text = "Split Into Two Halves", buttonText = "Split", width = 90,
              tooltip = "Two balanced halves for split runs. Each kind is dealt out in turn, so both sides get the same mix.",
              onClick = Run("split") }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Put Everyone Back", buttonText = "Undo", width = 90,
              tooltip = "Back to how the groups were before the last sort or split.",
              onClick = Run("undo") },
            { type = "labeledButton", text = "Stop a Sort", buttonText = "Stop", width = 90,
              tooltip = "Stops a sort that is under way. Players already moved stay where they are.",
              onClick = Run("stop") }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "label", text = "Melee and ranged are told apart by class, which is a guess for Druids, Shamans and Hunters. Results print in chat." },
            { type = "label", text = "" }
        );  y = y - h

        _, h = W:SectionHeader(parent, "INVITES", y);  y = y - h

        local inv = ns.InviteSettings()
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Roster", inputWidth = 220, placeholder = "Name, Name-Realm, ...",
              tooltip = "Everyone to invite, separated by commas or spaces. Press Enter to save.",
              getValue = function() return inv.list end,
              setValue = function(v) inv.list = v or "" end },
            { type = "labeledButton", text = "Invite the Roster", buttonText = "Invite", width = 90,
              tooltip = "Invites everyone on the roster who is not in the group yet. A party becomes a raid when it needs to.",
              onClick = function() ns.InviteList() end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "input", text = "Assistants", inputWidth = 220, placeholder = "Name, Name, ...",
              tooltip = "Players to make raid assistants. Press Enter to save.",
              getValue = function() return inv.promote end,
              setValue = function(v) inv.promote = v or "" end },
            { type = "labeledButton", text = "Promote Assistants Now", buttonText = "Promote", width = 90,
              onClick = function() ns.PromoteList(false) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Promote Assistants When They Join",
              tooltip = "While you lead the raid, everyone on the assistants list is promoted as they join.",
              getValue = function() return inv.autoPromote end,
              setValue = function(v) inv.autoPromote = v and true or false end },
            { type = "label", text = "" }
        );  y = y - h

        _, h = W:SectionHeader(parent, "READY CHECK", y);  y = y - h

        local rc = ns.ReadyCheckSettings()
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Gear and Cooldown Check",
              tooltip = "On every ready check, CludesUI users report their durability, item level, missing enchants and raid cooldowns that are not ready. The leader and assistants see a list.",
              getValue = function() return rc.enabled end,
              setValue = function(v) rc.enabled = v and true or false end },
            { type = "slider", text = "Flag Durability Below", min = 0, max = 100, step = 5,
              getValue = function() return rc.minDurability end,
              setValue = function(v) rc.minDurability = math.floor(v + 0.5) end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "See Your Own Report", buttonText = "Show", width = 90,
              tooltip = "Opens the ready check list with just your own report.",
              onClick = function() ns.ShowReadyWindow() end },
            { type = "toggle", text = "Consumables Check",
              tooltip = "Adds missing flask, food, augment rune and healthstone to each report. Food counts any buff with the Well Fed icon. If the game is hiding buffs from addons at that moment, the report says so.",
              getValue = function() return rc.consumables end,
              setValue = function(v) rc.consumables = v and true or false end }
        );  y = y - h

        _, h = W:SectionHeader(parent, "BREAK TIMER", y);  y = y - h
        local bt = ns.BreakSettings()
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Break Timers",
              tooltip = "When the leader or an assistant starts a break, a bar counts it down for every CludesUI user in the group. Move it in Layout Mode.",
              getValue = function() return bt.enabled end,
              setValue = function(v) bt.enabled = v and true or false end },
            { type = "toggle", text = "Sound When It Ends",
              getValue = function() return bt.sound end,
              setValue = function(v) bt.sound = v and true or false end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Start a Break", buttonText = "5 min", width = 90,
              tooltip = "Starts a 5 minute break for the group. /raidlead break 10 starts one of any length.",
              onClick = function() ns.StartBreak(5) end },
            { type = "labeledButton", text = "End the Break", buttonText = "End", width = 90,
              onClick = function() ns.StartBreak(0) end }
        );  y = y - h

        _, h = W:SectionHeader(parent, "KICK ROTATION", y);  y = y - h
        local ks = ns.KickSettings()
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Kick Rotation",
              tooltip = "Shows whose interrupt is next. The order comes from an intstart / intend block in the boss's note (one line of names per rotation), or the Kick Order below for other fights. Each cast of the tracked unit moves the turn on.",
              getValue = function() return ks.enabled end,
              setValue = function(v) ks.enabled = v and true or false end },
            { type = "segmented", text = "Track", values = { focus = "Focus", boss1 = "Boss 1" }, order = { "focus", "boss1" },
              tooltip = "The unit whose casts count. Put the mob you kick on focus.",
              getValue = function() return ks.unit end,
              setValue = function(v) ks.unit = v end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Kick Order", inputWidth = 160, inputStyle = "popup",
              placeholder = "Alice Bob Carol",
              tooltip = "Names in kick order, separated by spaces, for fights without a note block. Nicknames work.",
              getValue = function() return ks.order end,
              setValue = function(text) ks.order = (text or ""):match("^%s*(.-)%s*$") end },
            { type = "labeledButton", text = "Preview", buttonText = "Show", width = 90,
              tooltip = "Shows the box for a few seconds so you can place it in Layout Mode.",
              onClick = function() ns.PreviewKicks() end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Sound on Your Turn",
              getValue = function() return ks.sound end,
              setValue = function(v) ks.sound = v and true or false end },
            { type = "label", text = "" }
        );  y = y - h

        _, h = W:SectionHeader(parent, "VERSIONS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Check CludesUI Versions", buttonText = "Check", width = 90,
              tooltip = "Asks everyone in the group which CludesUI version they run. The answer prints in chat after a few seconds.",
              onClick = function() ns.VersionCheck() end },
            { type = "label", text = "" }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Tracking page: Immunities on You and Boss Pace
    ---------------------------------------------------------------------------
    local PAGE_TRACKING = "Tracking"
    local PAGE_NICKNAMES = "Nicknames"

    local function Refresh()
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
    end

    local function BuildTrackingPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        local im, pace = ns.ImmunitySettings(), ns.PaceSettings()

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "IMMUNITIES ON YOU", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Immunities on You",
              tooltip = "Icons for Divine Shield, Blessing of Protection, Blessing of Spellwarding, Ice Block, Aspect of the Turtle and Cloak of Shadows while they are on you. Works in combat. Move it in Layout Mode.",
              getValue = function() return im.enabled end,
              setValue = function(v) im.enabled = v and true or false; ns.RefreshImmunities() end },
            { type = "slider", text = "Icon Size", min = 20, max = 64, step = 1,
              getValue = function() return im.size end,
              setValue = function(v) im.size = math.floor(v + 0.5); ns.RefreshImmunities() end }
        );  y = y - h
        local extra = {}
        for _, id in ipairs(im.extra) do
            local n = C_Spell.GetSpellName(id)
            extra[#extra + 1] = (type(n) == "string" and n or "Spell") .. " (" .. id .. ")"
        end
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Add an Immunity", inputStyle = "popup", placeholder = "Spell ID", inputWidth = 110,
              tooltip = "The spell ID of another immunity buff to show.",
              getValue = function() return "" end,
              setValue = function(text)
                  local id = tonumber(text)
                  if id and id > 0 then table.insert(im.extra, math.floor(id)); ns.RefreshImmunities(); Refresh() end
              end },
            #extra > 0 and { type = "labeledButton", text = "Added: " .. table.concat(extra, ", "), buttonText = "Clear", width = 90,
              onClick = function() wipe(im.extra); ns.RefreshImmunities(); Refresh() end }
              or { type = "label", text = "" }
        );  y = y - h

        _, h = W:SectionHeader(parent, "AURA GLOWS", y);  y = y - h
        local ag = ns.AuraGlowSettings()
        local glowNames = {}
        for _, id in ipairs(ag.spells) do
            local n = C_Spell.GetSpellName(id)
            glowNames[#glowNames + 1] = (type(n) == "string" and n or "Spell") .. " (" .. id .. ")"
        end
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Aura Glows",
              tooltip = "While an aura you add here is on you, its icon shows with a glowing border and its time. Works in boss fights. Changes apply out of combat. Move it in Layout Mode.",
              getValue = function() return ag.enabled end,
              setValue = function(v) ag.enabled = v and true or false; ns.RebuildAuraGlows() end },
            { type = "slider", text = "Icon Size", min = 20, max = 80, step = 1,
              getValue = function() return ag.size end,
              setValue = function(v) ag.size = math.floor(v + 0.5); ns.RebuildAuraGlows() end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Add an Aura", inputStyle = "popup", placeholder = "Spell IDs", inputWidth = 110,
              tooltip = "The spell ID of a buff or debuff to glow for. Several, separated by commas or spaces, work too.",
              getValue = function() return "" end,
              setValue = function(text)
                  for _, id in ipairs(ns.ParseSpellIDs(text)) do table.insert(ag.spells, id) end
                  ns.RebuildAuraGlows(); Refresh()
              end },
            #glowNames > 0 and { type = "labeledButton", text = "Added: " .. table.concat(glowNames, ", "), buttonText = "Clear", width = 90,
              onClick = function() wipe(ag.spells); ns.RebuildAuraGlows(); Refresh() end }
              or { type = "label", text = "" }
        );  y = y - h

        _, h = W:SectionHeader(parent, "GROUP HELPERS", y);  y = y - h
        local hs = ns.HelperSettings()
        local function HSet(key, v) hs[key] = v and true or false; ns.RefreshHelpers() end
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Feast and Cauldron Alerts",
              tooltip = "A chat line naming who dropped a feast, cauldron, Soulwell or repair bot. Only drops by CludesUI users are seen: the game shows addons no one else's casts.",
              getValue = function() return hs.drops end,
              setValue = function(v) HSet("drops", v) end },
            { type = "toggle", text = "Alert Sound",
              getValue = function() return hs.dropSound end,
              setValue = function(v) HSet("dropSound", v) end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Gateway Usable",
              tooltip = "Gateway usable shows while you are close enough to a warlock's Demonic Gateway to click it. Move it in Layout Mode.",
              getValue = function() return hs.gateway end,
              setValue = function(v) HSet("gateway", v) end },
            { type = "toggle", text = "Stats Panel",
              tooltip = "Your crit, haste, mastery and versatility on screen, kept up to date through procs. Move it in Layout Mode.",
              getValue = function() return hs.stats end,
              setValue = function(v) HSet("stats", v) end }
        );  y = y - h

        _, h = W:SectionHeader(parent, "BOSS PACE", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Boss Pace",
              tooltip = "A bar with the boss's health and a marker for where it should be to kill it in your target time: green while ahead, red while behind. The pace is a straight line, so phases and intermissions throw it off. Move it in Layout Mode.",
              getValue = function() return pace.enabled end,
              setValue = function(v) pace.enabled = v and true or false end },
            { type = "input", text = "Add a Boss", inputStyle = "popup", placeholder = "Boss name", inputWidth = 160,
              tooltip = "The boss's name as the game shows it at the pull. Set its target kill time below.",
              getValue = function() return "" end,
              setValue = function(text)
                  text = text and text:match("^%s*(.-)%s*$") or ""
                  if text ~= "" then table.insert(pace.targets, { boss = text, seconds = 300 }); Refresh() end
              end }
        );  y = y - h
        for i, t in ipairs(pace.targets) do
            _, h = W:DualRow(parent, y,
                { type = "input", text = t.boss .. ": Target Kill Time", inputWidth = 80, placeholder = "5:00",
                  tooltip = "Minutes and seconds, like 5:30. Press Enter to save.",
                  getValue = function() return ns.FormatDuration(t.seconds) end,
                  setValue = function(text) local s = ns.ParseDuration(text); if s and s > 0 then t.seconds = s end end },
                { type = "labeledButton", text = "Try It Now", buttonText = "Test", width = 70,
                  tooltip = "Shows the bar for this boss now, with your target as the clock. With no boss targeted the bar stays empty.",
                  onClick = function() ns.StartPace(t.boss, t.seconds) end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = "Remove " .. t.boss, buttonText = "Remove", width = 90,
                  onClick = function() table.remove(pace.targets, i); Refresh() end },
                { type = "label", text = "" }
            );  y = y - h
        end

        if ns.TimelineSettings then
            local tl = ns.TimelineSettings()
            _, h = W:SectionHeader(parent, "BOSS TIMELINES", y);  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Upcoming Ability Bars",
                  tooltip = "During a Midnight raid boss, the next abilities as countdown bars, coloured by kind of mechanic. Each phase runs from when it really began, read from the boss's timeline; phases still to come are estimates, shown faded. Move them in Layout Mode.",
                  getValue = function() return tl.bars end,
                  setValue = function(v) tl.bars = v and true or false end },
                { type = "toggle", text = "Encounter Alerts",
                  tooltip = "Timed calls on the reminder display a few seconds before each mechanic (Soak, Spread, Defensives), only the ones for your role, restarted at each phase change.",
                  getValue = function() return tl.alerts end,
                  setValue = function(v) tl.alerts = v and true or false end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Only My Role",
                  tooltip = "Bars and the timeline window show only the mechanics for your role: raid damage and soaks for healers, tankbusters and frontals for tanks.",
                  getValue = function() return tl.mine end,
                  setValue = function(v) tl.mine = v and true or false end },
                { type = "toggle", text = "Speak Alerts",
                  tooltip = "Text to speech says each alert as it shows.",
                  getValue = function() return tl.tts end,
                  setValue = function(v) tl.tts = v and true or false end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "slider", text = "Bars Shown", min = 3, max = 12, step = 1, isPercent = false,
                  getValue = function() return tl.count end,
                  setValue = function(v) tl.count = math.floor(v + 0.5) end },
                { type = "slider", text = "Look Ahead (seconds)", min = 10, max = 60, step = 5, isPercent = false,
                  getValue = function() return tl.ahead end,
                  setValue = function(v) tl.ahead = math.floor(v + 0.5) end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = "Boss Timeline Window", buttonText = "Open", width = 90,
                  tooltip = "Each boss's abilities and when they come, Heroic or Mythic, with Test to run one as if pulled. Also /cbt.",
                  onClick = function() ns.OpenTimeline() end },
                { type = "toggle", text = "Say Phase Changes",
                  tooltip = "A chat line when a phase change is read, to check the timings against the fight.",
                  getValue = function() return tl.phaseChat end,
                  setValue = function(v) tl.phaseChat = v and true or false end }
            );  y = y - h
        end

        return math.abs(y)
    end

    local function BuildNicknamesPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "NICKNAMES", y);  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "input", text = "Your Nickname", inputWidth = 160, placeholder = "Nickname",
              tooltip = "Sent to your guild when you log in and to your group when it changes. Other CludesUI users see it on their raid and unit frames. Press Enter to save.",
              getValue = function() return ns.MyNickname() end,
              setValue = function(text) ns.SetMyNickname(text); Refresh() end },
            { type = "toggle", text = "Show CludesUI Nicknames",
              tooltip = "Raid frames show nicknames in place of character names. Unit frames also need their own Show Nicknames setting on.",
              getValue = function() return not CludesUIDB.cuiNicknamesOff end,
              setValue = function(v) CludesUIDB.cuiNicknamesOff = not v or nil end }
        );  y = y - h
        _, h = W:DualRow(parent, y,
            { type = "labeledButton", text = "Paste Nicknames", buttonText = "Paste", width = 90,
              tooltip = "One \"Character=Nickname\" per line.",
              onClick = function()
                  CludesUI:ShowImportPopup(function(str)
                      local n = ns.ImportNicknames(str)
                      CludesUI.Print(("|cff4cc9f0Raid Lead:|r added %d nickname%s."):format(n, n == 1 and "" or "s"))
                      Refresh()
                  end, "Nicknames", "One Character=Nickname per line")
              end },
            { type = "label", text = "Known nicknames: " .. ns.NicknameCount() }
        );  y = y - h

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Reminders page
    ---------------------------------------------------------------------------
    local PAGE_REMINDERS = "Reminders"

    local function Redraw()
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
    end
    ns.OnSharedChanged = function()
        if CludesUI._mainFrame and CludesUI._mainFrame:IsShown() then Redraw() end
    end

    local function Summary(text)
        local list, skipped = ns.NoteParser.Parse(text or "", function(id)
            local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            return type(n) == "string" and n or nil
        end)
        local s = #list .. " reminder" .. (#list == 1 and "" or "s")
        if skipped > 0 then s = s .. ", " .. skipped .. " phase line" .. (skipped == 1 and "" or "s") .. " skipped" end
        return s
    end

    local function BuildRemindersPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        local r = ns.ReminderSettings()

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "REMINDERS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Show Encounter Reminders",
              tooltip = "When a boss is pulled, its note's lines for you appear before their time with a countdown. Move them in Layout Mode.",
              getValue = function() return r.enabled end,
              setValue = function(v) r.enabled = v and true or false end },
            { type = "toggle", text = "Accept Reminders From the Raid Leader",
              tooltip = "Notes the leader or an assistant sends replace your own for that boss, for this session.",
              getValue = function() return r.acceptShared end,
              setValue = function(v) r.acceptShared = v and true or false end }
        );  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Show Seconds Before", min = 1, max = 10, step = 1,
              getValue = function() return r.lead end,
              setValue = function(v) r.lead = math.floor(v + 0.5) end },
            { type = "slider", text = "Text Size", min = 14, max = 48, step = 1,
              getValue = function() return r.fontSize end,
              setValue = function(v) r.fontSize = math.floor(v + 0.5); ns.ApplyReminderLook() end }
        );  y = y - h

        local soundValues, soundOrder = { [""] = "None" }, { "" }
        for _, f in ipairs(ns.SOUND_FILES) do
            soundValues[f] = f:gsub("%.%a+$", ""):gsub("(%l)(%u)", "%1 %2")
            soundOrder[#soundOrder + 1] = f
        end
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Speak Reminders",
              tooltip = "Reads each reminder aloud with the game's text to speech voice.",
              getValue = function() return r.tts end,
              setValue = function(v) r.tts = v and true or false end },
            { type = "dropdown", text = "Reminder Sound", values = soundValues, order = soundOrder,
              getValue = function() return r.sound or "" end,
              setValue = function(v) r.sound = v; if v ~= "" then ns.PreviewSound(v) end end }
        );  y = y - h

        _, h = W:SectionHeader(parent, "BOSS NOTES", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "input", text = "Add a Boss", inputStyle = "popup", placeholder = "Boss name", inputWidth = 160,
              tooltip = "The boss's name as the game shows it at the pull. Use \"any\" for a note that runs on every boss.",
              getValue = function() return "" end,
              setValue = function(text)
                  text = text and text:match("^%s*(.-)%s*$") or ""
                  if text == "" then return end
                  table.insert(r.notes, { boss = text, text = "" })
                  Redraw()
              end },
            { type = "label", text = "Lines are {time:1:30} then the text. Names on a line make it theirs; {tank}, {healer}, {dps} and {everyone} work too." }
        );  y = y - h

        for i, note in ipairs(r.notes) do
            _, h = W:SectionHeader(parent, note.boss:upper() .. "  -  " .. Summary(note.text), y);  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = "Paste or Replace the Note", buttonText = "Paste", width = 90,
                  tooltip = "Paste a note from wowutils, wowaudit or a Method Raid Tools note.",
                  onClick = function()
                      CludesUI:ShowImportPopup(function(str)
                          note.text = str or ""
                          Redraw()
                      end, "Reminders for " .. note.boss, "Paste the note, then press Save")
                  end },
                { type = "labeledButton", text = "Try It Now", buttonText = "Test", width = 90,
                  tooltip = "Runs the note as if the boss was pulled now. Lines for you appear on screen.",
                  onClick = function()
                      local n, skipped = ns.RunNote(note.text)
                      CludesUI.Print(("|cff4cc9f0Raid Lead:|r testing %s: %d reminder%s for you%s."):format(
                          note.boss, n, n == 1 and "" or "s", skipped > 0 and (", " .. skipped .. " phase lines skipped") or ""))
                  end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "labeledButton", text = "Send to the Group", buttonText = "Send", width = 90,
                  tooltip = "Sends this note to everyone in the group who runs CludesUI. Leader or assistant only.",
                  onClick = function() ns.ShareNote(note.boss, note.text) end },
                { type = "labeledButton", text = "Remove This Note", buttonText = "Remove", width = 90,
                  onClick = function() table.remove(r.notes, i); Redraw() end }
            );  y = y - h
        end

        local sharedAny = next(ns.sharedNotes)
        if sharedAny then
            _, h = W:SectionHeader(parent, "SENT BY THE RAID LEADER (THIS SESSION)", y);  y = y - h
            for boss, s in pairs(ns.sharedNotes) do
                _, h = W:DualRow(parent, y,
                    { type = "label", text = boss .. ", from " .. s.from .. ": " .. Summary(s.text) },
                    { type = "labeledButton", text = "Forget It", buttonText = "Forget", width = 90,
                      onClick = function() ns.sharedNotes[boss] = nil; Redraw() end }
                );  y = y - h
            end
        end

        return math.abs(y)
    end

    ---------------------------------------------------------------------------
    --  Aura Sounds page
    ---------------------------------------------------------------------------
    local PAGE_SOUNDS = "Aura Sounds"

    local function Rebuild()
        ns.RebuildAuraSounds()
        CludesUI:InvalidatePageCache()
        CludesUI:RefreshPage(true)
    end

    local soundValues, soundOrder = {}, {}
    for _, f in ipairs(ns.SOUND_FILES) do
        soundValues[f] = f:gsub("%.%a+$", ""):gsub("(%l)(%u)", "%1 %2")
        soundOrder[#soundOrder + 1] = f
    end
    local whenValues, whenOrder = {}, {}
    for _, w in ipairs(ns.SOUND_WHEN) do
        whenValues[w.id] = w.label
        whenOrder[#whenOrder + 1] = w.id
    end

    local function SpellName(id)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if type(name) == "string" and name ~= "" then return name end
        return "Spell " .. id
    end

    local function BuildSoundsPage(_, parent, yOffset)
        local W = CludesUI.Widgets
        local y = yOffset
        local _, h
        local list = ns.RaidLeadDB().sounds

        CludesUI:ClearContentHeader()

        _, h = W:SectionHeader(parent, "AURA SOUNDS", y);  y = y - h

        _, h = W:DualRow(parent, y,
            { type = "input", text = "Add a Spell ID", inputStyle = "popup", placeholder = "Spell ID", inputWidth = 110,
              tooltip = "The spell ID of a buff or debuff that lands on you. It plays a siren when applied; change that below. The game plays these itself, so they work in boss fights.",
              getValue = function() return "" end,
              setValue = function(text)
                  local id = tonumber(text)
                  if not id or id <= 0 then return end
                  list[#list + 1] = { id = math.floor(id), when = "added", sound = "WarningSiren.ogg", on = true }
                  Rebuild()
              end },
            { type = "label", text = "" }
        );  y = y - h

        for i, e in ipairs(list) do
            local name = SpellName(e.id)
            _, h = W:SectionHeader(parent, name:upper(), y);  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "toggle", text = "Play a Sound for " .. name, tooltip = "Spell ID " .. e.id,
                  getValue = function() return e.on ~= false end,
                  setValue = function(v) e.on = v and true or false; ns.RebuildAuraSounds() end },
                { type = "dropdown", text = "Play When", values = whenValues, order = whenOrder,
                  getValue = function() return e.when or "added" end,
                  setValue = function(v) e.when = v; ns.RebuildAuraSounds() end }
            );  y = y - h
            _, h = W:DualRow(parent, y,
                { type = "dropdown", text = "Sound", values = soundValues, order = soundOrder,
                  getValue = function() return e.sound or "WarningSiren.ogg" end,
                  setValue = function(v) e.sound = v; ns.PreviewSound(v); ns.RebuildAuraSounds() end },
                { type = "labeledButton", text = "Remove This Sound", buttonText = "Remove", width = 90,
                  onClick = function() table.remove(list, i); Rebuild() end }
            );  y = y - h
        end

        return math.abs(y)
    end

    CludesUI:RegisterModule(ADDON_NAME, {
        title       = "Raid Lead",
        description = "Tools for raid leaders: sort or split the raid, and sounds for auras on you.",
        pages       = { PAGE, PAGE_REMINDERS, PAGE_TRACKING, PAGE_SOUNDS, PAGE_NICKNAMES },
        buildPage   = function(pageName, parent, yOffset)
            if pageName == PAGE then return BuildPage(pageName, parent, yOffset) end
            if pageName == PAGE_REMINDERS then return BuildRemindersPage(pageName, parent, yOffset) end
            if pageName == PAGE_TRACKING then return BuildTrackingPage(pageName, parent, yOffset) end
            if pageName == PAGE_NICKNAMES then return BuildNicknamesPage(pageName, parent, yOffset) end
            if pageName == PAGE_SOUNDS then return BuildSoundsPage(pageName, parent, yOffset) end
        end,
    })
end)
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
