if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Reminders.lua -- Raid Lead: encounter reminders.
--
--  You keep one reminder note per boss (pasted from wowutils, wowaudit or a
--  Method Raid Tools note, or written by hand; NoteParser.lua reads them).
--  When a boss is pulled, every line meant for you is shown a few seconds
--  before its time with a countdown, and can be spoken and play a sound.
--
--  A note's boss is matched to the encounter name the game reports at the
--  pull, ignoring case; a note for "any" runs on every boss (useful to test).
--  Notes the raid leader sends (Comms.lua) are kept for the session and run
--  in place of your own for that boss.
-------------------------------------------------------------------------------
local _, ns = ...
local Parser = ns.NoteParser

local SOUND_DIR = "Interface\\AddOns\\CludesUI\\media\\sounds\\"
local MAX_LINES = 4
local HOLD = 1.5          -- seconds a reminder stays up after its time

local function Settings()
    local p = ns.RaidLeadDB()
    p.reminders = p.reminders or {}
    local r = p.reminders
    r.notes = r.notes or {}
    if r.lead == nil then r.lead = 5 end
    if r.tts == nil then r.tts = true end
    if r.sound == nil then r.sound = "RobotBlip.ogg" end
    if r.acceptShared == nil then r.acceptShared = true end
    if r.enabled == nil then r.enabled = true end
    if r.fontSize == nil then r.fontSize = 26 end
    return r
end
ns.ReminderSettings = Settings

local shared = {}          -- boss (lowercase) -> { from, text }, this session only
ns.sharedNotes = shared

local function SpellName(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return (type(n) == "string" and n ~= "") and n or nil
end

local function Clean(s) return (s or ""):lower():gsub("^%s+", ""):gsub("%s+$", "") end

--- The note that would run for a boss name: a shared one first, then yours.
function ns.NoteFor(bossName)
    local key = Clean(bossName)
    if shared[key] then return shared[key].text, shared[key].from end
    if shared.any then return shared.any.text, shared.any.from end
    for _, n in ipairs(Settings().notes) do
        local b = Clean(n.boss)
        if b == key or b == "any" then return n.text, nil end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local anchor, lines = nil, {}
local active = {}          -- { text, at (GetTime when due) }

local function Font()
    return (CludesUI.GetFontPath and CludesUI.GetFontPath()) or STANDARD_TEXT_FONT
end

local function BuildDisplay()
    if anchor then return end
    anchor = CreateFrame("Frame", "CludesUIRaidLeadReminders", UIParent)
    anchor:SetSize(420, 40 * MAX_LINES)
    anchor:SetFrameStrata("HIGH")
    for i = 1, MAX_LINES do
        local fs = anchor:CreateFontString(nil, "OVERLAY")
        fs:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * 40)
        fs:SetJustifyH("CENTER")
        lines[i] = fs
    end
    ns.ApplyReminderLook()
end

function ns.ApplyReminderLook()
    if not anchor then return end
    local r = Settings()
    local p = r.pos
    if not InCombatLockdown() then
        anchor:ClearAllPoints()
        if p then
            anchor:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
        else
            anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
        end
    end
    for i = 1, MAX_LINES do
        CludesUI.Kit.Font(lines[i], r.fontSize, nil)
        lines[i]:SetPoint("TOP", anchor, "TOP", 0, -(i - 1) * (r.fontSize + 12))
    end
end

local function Repaint()
    local now = GetTime()
    for i = #active, 1, -1 do
        if now > active[i].at + HOLD then table.remove(active, i) end
    end
    for i = 1, MAX_LINES do
        local a = active[i]
        if a then
            local left = a.at - now
            local tail = left > 0.05 and ("  " .. CludesUI.Kit.AccentHex() .. math.ceil(left) .. "|r") or "  |cffff6040NOW|r"
            lines[i]:SetText(a.text .. tail)
            lines[i]:Show()
        else
            lines[i]:Hide()
        end
    end
    if #active == 0 then anchor:SetScript("OnUpdate", nil) end
end

local function Speak(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return end
    local voice
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
        local ok, v = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Standard)
        if ok then voice = v end
    end
    if not voice and C_VoiceChat.GetTtsVoices then
        local list = C_VoiceChat.GetTtsVoices()
        voice = list and list[1] and list[1].voiceID
    end
    if not voice then return end
    local rate, volume = 0, 100
    if C_TTSSettings then
        local ok1, r = pcall(C_TTSSettings.GetSpeechRate); if ok1 and type(r) == "number" then rate = r end
        local ok2, v = pcall(C_TTSSettings.GetSpeechVolume); if ok2 and type(v) == "number" then volume = v end
    end
    pcall(C_VoiceChat.SpeakText, voice, (text:gsub("{rt%d}", ""):gsub("|T.-|t", "")), rate, volume, true)
end

local function Show(entry)
    BuildDisplay()
    local r = Settings()
    table.insert(active, { text = entry.text:gsub("{rt(%d)}", "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_%1:0|t"),
                           at = GetTime() + math.min(r.lead, entry.at) })
    while #active > MAX_LINES do table.remove(active, 1) end
    if r.tts then Speak(entry.text) end
    if r.sound and r.sound ~= "" then PlaySoundFile(SOUND_DIR .. r.sound, "Master") end
    anchor:SetScript("OnUpdate", Repaint)
    Repaint()
end

--- One line on the reminder display, due in `at` seconds (Boss Timelines'
--- encounter alerts). speak: false for silence, true to say the text, or
--- other words to say; sound: whether to play the reminder sound.
function ns.ShowReminder(text, at, speak, sound)
    BuildDisplay()
    table.insert(active, { text = text, at = GetTime() + math.max(0, at) })
    while #active > MAX_LINES do table.remove(active, 1) end
    if speak then Speak(type(speak) == "string" and speak or text) end
    local r = Settings()
    if sound and r.sound and r.sound ~= "" then PlaySoundFile(SOUND_DIR .. r.sound, "Master") end
    anchor:SetScript("OnUpdate", Repaint)
    Repaint()
end

-------------------------------------------------------------------------------
--  Running a note
-------------------------------------------------------------------------------
local run = 0             -- bumped on every pull and wipe, so old timers stand down

local function Roster()
    local set = {}
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
        local name = UnitName(unit)
        if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then set[name:lower()] = true end
    end
    set[(UnitName("player") or ""):lower()] = true
    return set
end

local function MyRole()
    local spec = GetSpecialization and GetSpecialization()
    return spec and GetSpecializationRole(spec) or "DAMAGER"
end

--- Starts a note's reminders as if the boss had just been pulled.
--- Returns how many reminders are for you and how many phase lines were skipped.
function ns.RunNote(text)
    run = run + 1
    local mine = run
    wipe(active)
    local list, skipped = Parser.Parse(text, SpellName)
    local me, role, roster = UnitName("player"), MyRole(), Roster()
    local count = 0
    for _, e in ipairs(list) do
        if Parser.IsFor(e, me, role, roster) then
            count = count + 1
            local delay = math.max(0, e.at - Settings().lead)
            C_Timer.After(delay, function()
                if run == mine then Show(e) end
            end)
        end
    end
    return count, skipped
end

function ns.StopReminders()
    run = run + 1
    wipe(active)
    if anchor then Repaint() end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ENCOUNTER_START")
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, _, encounterName)
    if event == "ENCOUNTER_END" then return ns.StopReminders() end
    if not Settings().enabled then return end
    if type(encounterName) ~= "string" or (issecretvalue and issecretvalue(encounterName)) then return end
    local text = ns.NoteFor(encounterName)
    if text then ns.RunNote(text) end
end)

--- Called by Comms.lua when the leader sends a note.
function ns.ReceiveSharedNote(from, boss, text)
    if not Settings().acceptShared then return end
    shared[Clean(boss)] = { from = from, text = text }
    local list, skipped = Parser.Parse(text, SpellName)
    CludesUI.Print(("|cff4cc9f0Raid Lead:|r %s sent reminders for %s (%d line%s%s)."):format(
        from, boss, #list, #list == 1 and "" or "s",
        skipped > 0 and (", " .. skipped .. " phase line" .. (skipped == 1 and "" or "s") .. " skipped") or ""))
    if ns.OnSharedChanged then ns.OnSharedChanged() end
end

-------------------------------------------------------------------------------
--  Layout Mode
-------------------------------------------------------------------------------
local registered = false
local reg = CreateFrame("Frame")
reg:RegisterEvent("PLAYER_ENTERING_WORLD")
reg:SetScript("OnEvent", function()
    if registered or not (CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then return end
    registered = true
    BuildDisplay()
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "RLEAD_Reminders", label = "Encounter Reminders", group = "Raid Lead", order = 660,
            noAnchorTarget = true, noResize = true,
            isHidden = function() return not Settings().enabled end,
            getFrame = function() BuildDisplay(); return anchor end,
            getSize = function() return 420, (Settings().fontSize + 12) * 2 end,
            savePos = function(_, point, relPoint, x, y)
                Settings().pos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function() return Settings().pos end,
            clearPos = function() Settings().pos = nil end,
            applyPos = ns.ApplyReminderLook,
        }),
    }, "CludesUIRaidLead")
end)
