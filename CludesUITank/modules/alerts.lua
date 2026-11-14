local addonName, ns = ...
if ns.standalone then
    return
end

ns.Alert = {}

local REPEAT_COOLDOWN = 4
local DISPLAY_TIME = 3.0
local lastAlerted = {}
local fadeTimer = nil
local flashFrame = nil
local alertFrame = nil

-- Engine-side aura sounds (see RegisterAuraSounds below).
local DEFAULT_ALERT_SOUND = "Sound\\Interface\\RaidWarning.ogg"
local auraSoundIDs = {}
local soundWarned = false

-- Set when a rebuild was requested while auras were secret; Core.lua flushes
-- these on PLAYER_REGEN_ENABLED.
local pendingRegister = false
local pendingUnit = nil

-- Spell display names, keyed by ID, taken from the preset data. Aura names
-- coming back from the engine are secret during encounters, so the alert text
-- is built from this table instead of from the aura.
local spellNames = nil
local function SpellName(spellID)
    if not spellNames then
        spellNames = {}
        for _, raid in ipairs(ns.SpellData and ns.SpellData.raids or {}) do
            for _, boss in ipairs(raid.bosses) do
                for _, spell in ipairs(boss.spells) do
                    spellNames[spell.id] = spell.name
                end
            end
        end
    end
    -- Custom alerts are not in the preset data, so ask the game for those.
    return spellNames[spellID] or (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID))
end
ns.Alert.SpellName = SpellName

-- ── Flash frame (fullscreen red tint) ─────────────────────────────────────
local function CreateFlashFrame()
    flashFrame = CreateFrame("Frame", "CoTankAurasFlash", UIParent)
    flashFrame:SetAllPoints(UIParent)
    flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    flashFrame:SetAlpha(0)

    local tex = flashFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 0.1, 0.1, 0.35)

    local ag = flashFrame:CreateAnimationGroup()
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.6)
    fade:SetSmoothing("OUT")
    ag:SetScript("OnFinished", function()
        flashFrame:SetAlpha(0)
    end)
    flashFrame.fadeGroup = ag
    flashFrame:Hide()
end

-- ── Alert text frame (on-screen warning) ──────────────────────────────────
local function CreateAlertFrame()
    alertFrame = CreateFrame("Frame", "CoTankAurasAlertText", UIParent)
    alertFrame:SetSize(400, 50)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame:SetClampedToScreen(true)

    local text = alertFrame:CreateFontString(nil, "OVERLAY")
    local sz = (ns.DB and ns.DB().alertTextSize) or 22
    text:SetFont(ns.FontPath(), sz, ns.FontFlags())
    text:SetPoint("CENTER")
    text:SetTextColor(1, 0.3, 0.3)
    text:SetShadowOffset(2, -2)
    text:SetShadowColor(0, 0, 0, 0.8)
    alertFrame.text = text
    alertFrame:Hide()

    local db = ns.DB and ns.DB() or {}
    alertFrame:SetPoint(
        db.alertPoint or "CENTER",
        UIParent,
        db.alertRelPoint or "CENTER",
        db.alertX or 0,
        db.alertY or 200
    )
end

-- ── Internal fire ─────────────────────────────────────────────────────────
local function FireAlert(spellName, stacks)
    local db = ns.DB and ns.DB() or {}
    local alertText = db.alertText or "TAUNT"
    local msg = alertText .. " - " .. (spellName or "Debuff") .. " (" .. stacks .. " stacks)"

    if flashFrame then
        flashFrame:Show()
        flashFrame:SetAlpha(1)
        flashFrame.fadeGroup:Stop()
        flashFrame.fadeGroup:Play()
    end

    PlaySound(8959, "Master")

    if alertFrame then
        alertFrame.text:SetText(msg)
        alertFrame.text:SetTextColor(1, 0.3, 0.3)
        alertFrame:SetAlpha(1)
        alertFrame:Show()
        if fadeTimer then
            fadeTimer:Cancel()
        end
        fadeTimer = C_Timer.NewTimer(DISPLAY_TIME, function()
            fadeTimer = nil
            if alertFrame then
                alertFrame:Hide()
                alertFrame.text:SetText("")
            end
        end)
    end

    ns.Print("|cffff4040" .. msg .. "|r")
end

-- ── Public API ────────────────────────────────────────────────────────────
function ns.Alert:Initialize()
    if not flashFrame then
        CreateFlashFrame()
    end
    if not alertFrame then
        CreateAlertFrame()
    end
end

-- The frame the on-screen alert sits on. The aura buttons anchor their own
-- alert text to it, and they are built before Initialize runs.
function ns.Alert:Anchor()
    if not alertFrame then
        CreateAlertFrame()
    end
    return alertFrame
end

function ns.Alert:BannerText()
    local text = (ns.DB and ns.DB() or {}).alertText
    if type(text) ~= "string" or text == "" then
        return "TAUNT"
    end
    return text
end

function ns.Alert:SetText(text)
    ns.DB().alertText = text
    ns.RestyleAuraButtons()
end

-- Test mode stand-in for the engine-driven alert text.
local previewing = false
function ns.Alert:PreviewBanner(on)
    if not alertFrame then
        return
    end
    if on then
        previewing = true
        alertFrame.text:SetText(self:BannerText())
        alertFrame.text:SetTextColor(1, 0.3, 0.3)
        alertFrame:SetAlpha(1)
        alertFrame:Show()
    elseif previewing then
        previewing = false
        alertFrame:Hide()
        alertFrame.text:SetText("")
    end
end

-- ── Engine-side aura sounds ───────────────────────────────────────────────
-- Since 12.1 an addon cannot see a debuff's stack count during an encounter,
-- so a threshold comparison is impossible there. C_UnitAuras.AddAuraSound is
-- the sanctioned substitute: the engine plays a sound of our choosing when a
-- watched spell is applied or gains a stack, without handing us any data.
-- Thresholds therefore collapse to "every application" while auras are secret;
-- the exact-threshold visual below still runs whenever they are readable.

-- ── Sound resolution via LibSharedMedia ───────────────────────────────────
-- LibSharedMedia is not bundled. When another addon provides it, every sound
-- any addon has registered becomes usable here by name, which is how a sound
-- shipped by Northern Sky, WeakAuras, BigWigs or DBM can be used without this
-- addon copying or redistributing anyone's audio: the file stays in its own
-- addon folder and we only reference the path LSM hands back.
local function GetLSM()
    if not LibStub then
        return nil
    end
    local ok, LSM = pcall(LibStub, "LibSharedMedia-3.0", true)
    if ok and LSM and LSM.Fetch then
        return LSM
    end
    return nil
end

-- Registered keys often carry UI escape codes (Northern Sky prefixes all of
-- its sounds with a colour), so "Interrupt" would never match the actual key
-- "|cFF4BAAC8Interrupt|r". Compare on the stripped, lowercased name instead.
local function StripEscapes(text)
    if type(text) ~= "string" then
        return ""
    end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns a lowercased-name -> registered-key lookup, plus the display names
-- in their original casing.
local function BuildSoundIndex(LSM)
    local index, display = {}, {}
    if not LSM.List then
        return index, display
    end
    local ok, list = pcall(LSM.List, LSM, "sound")
    if not ok or type(list) ~= "table" then
        return index, display
    end
    for _, key in ipairs(list) do
        local plain = StripEscapes(key)
        if plain ~= "" and not index[plain:lower()] then
            index[plain:lower()] = key
            display[#display + 1] = plain
        end
    end
    return index, display
end

-- Sorted, escape-free list of every sound name that can be used.
function ns.Alert:ListSoundNames()
    local LSM = GetLSM()
    if not LSM then
        return nil
    end
    local _, names = BuildSoundIndex(LSM)
    table.sort(names, function(a, b)
        return a:lower() < b:lower()
    end)
    return names
end

-- True for a value that can actually be handed to the engine as a sound file.
-- LibSharedMedia stores the number 1 for its "None" entry, and a name that
-- matched nothing comes back as a bare name rather than a path.
local function IsUsableSoundPath(path)
    return type(path) == "string"
        and path ~= ""
        and (path:find("\\", 1, true) or path:find("/", 1, true)) ~= nil
end

-- Resolves the configured alert sound to a file path: an LSM sound name if it
-- matches one, otherwise the setting treated as a literal path.
function ns.Alert:ResolveSoundPath()
    local name = (ns.DB and ns.DB() or {}).alertSoundFile or DEFAULT_ALERT_SOUND
    local LSM = GetLSM()
    if not LSM then
        return name
    end

    local function fetch(key)
        local ok, path = pcall(LSM.Fetch, LSM, "sound", key, true)
        -- LSM stores the number 1 for its "None" entry; that is not a path.
        if ok and type(path) == "string" and path ~= "" then
            return path
        end
    end

    local direct = fetch(name)
    if direct then
        return direct
    end

    local key = BuildSoundIndex(LSM)[StripEscapes(name):lower()]
    if key then
        local path = fetch(key)
        if path then
            return path
        end
    end

    return name
end

-- Called when combat drops, to run any rebuild that was blocked by secrecy.
function ns.Alert:FlushPendingAuraSounds()
    if not pendingRegister then
        return
    end
    if ns.AurasAreSecret() then
        return
    end
    local unit = pendingUnit
    pendingRegister = false
    pendingUnit = nil
    self:RegisterAuraSounds(unit or (CoTankAuras and CoTankAuras:GetAttribute("unit")))
end

function ns.Alert:ClearAuraSounds()
    if C_UnitAuras and C_UnitAuras.RemoveAuraSound then
        for _, id in ipairs(auraSoundIDs) do
            pcall(C_UnitAuras.RemoveAuraSound, id)
        end
    end
    wipe(auraSoundIDs)
end

function ns.Alert:RegisterAuraSounds(unit)
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and Enum and Enum.UnitAuraSoundTrigger) then
        return 0, 0
    end

    -- AddAuraSound is rejected while auras are secret, which is exactly when a
    -- tank swap or roster change is most likely to fire this. Clearing the
    -- existing registrations and failing to replace them would silence alerts
    -- for the rest of the pull, so defer the whole rebuild to the next time
    -- combat drops (see the pending flush in Core.lua).
    if ns.AurasAreSecret() then
        pendingUnit = unit
        pendingRegister = true
        return 0, 0
    end

    pendingRegister = false
    pendingUnit = nil

    self:ClearAuraSounds()
    if not unit then
        return 0, 0
    end

    local db = ns.DB and ns.DB() or {}
    local soundPath = not db.alertSoundFileID and self:ResolveSoundPath() or nil
    local channel = db.alertSoundChannel or "Master"

    -- Registering a name that resolved to nothing just produces silent alerts,
    -- so refuse it up front and say which setting to fix.
    if not db.alertSoundFileID and not IsUsableSoundPath(soundPath) then
        if not soundWarned then
            soundWarned = true
            ns.Print(
                "|cffff4040Alert sound '"
                    .. tostring(soundPath)
                    .. "' is not a known sound.|r Pick one with "
                    .. "|cffffff00/ctank sounds|r then |cffffff00/ctank sound set <name>|r."
            )
        end
        return 0, 0
    end

    local triggers = {
        Enum.UnitAuraSoundTrigger.Added,
        Enum.UnitAuraSoundTrigger.ApplicationsIncreased,
    }

    local attempted = 0
    for spellID, sa in pairs(db.spellAlerts or {}) do
        local id = tonumber(spellID)
        if id and sa and sa.enabled then
            for _, trigger in ipairs(triggers) do
                -- A fresh table each call; the engine keeps what it is given.
                local sound = {
                    unitToken = unit,
                    spellID = id,
                    outputChannel = channel,
                    soundFileID = db.alertSoundFileID,
                    soundFileName = soundPath,
                }

                attempted = attempted + 1
                local ok, soundID = pcall(C_UnitAuras.AddAuraSound, trigger, sound)
                if ok and soundID then
                    table.insert(auraSoundIDs, soundID)
                end
            end
        end
    end

    -- AddAuraSound returns nil when it rejects the sound, which is the only
    -- signal we get that the configured file is not valid. Say so once rather
    -- than leaving the user with silent alerts.
    if attempted > 0 and #auraSoundIDs == 0 and not soundWarned then
        soundWarned = true
        ns.Print(
            "|cffff4040Alert sounds were rejected by the game.|r "
                .. "Pick another one with /ctank sounds and /ctank sound set <name>, "
                .. "or check the sound file still exists, "
                .. "then run |cffffff00/ctank sound|r again."
        )
    end

    return #auraSoundIDs, attempted
end

-- Reports whether the engine accepted the configured alert sound. The sound
-- file cannot be validated any other way: AddAuraSound returning a handle is
-- the only confirmation available.
function ns.Alert:ReportAuraSounds()
    local unit = CoTankAuras and CoTankAuras:GetAttribute("unit")
    if not unit then
        ns.Print("No co-tank assigned, so there is nothing to register sounds on.")
        return
    end

    soundWarned = false
    local registered, attempted = self:RegisterAuraSounds(unit)
    local db = ns.DB and ns.DB() or {}
    local using = db.alertSoundFileID and ("file ID " .. tostring(db.alertSoundFileID))
        or self:ResolveSoundPath()

    if ns.AurasAreSecret() then
        ns.Print(
            "Auras are secret right now (combat, encounter, M+ or PvP), "
                .. "so sounds cannot be registered. Retry out of combat - the "
                .. "addon also retries by itself when combat drops."
        )
        return
    end

    if attempted == 0 then
        ns.Print("No alert spells are enabled - turn some on under |cffffff00/ctank|r > Alerts.")
    elseif registered == 0 then
        ns.Print(
            "Alert sounds registered: |cffff66660/"
                .. attempted
                .. "|r - the game rejected "
                .. using
                .. ". Use |cffffff00/ctank sounds|r to list valid names."
        )
    elseif registered == attempted then
        ns.Print(
            "Alert sounds registered: |cff44ff88" .. registered .. "/" .. attempted .. "|r using " .. using
        )
    else
        ns.Print(
            "Alert sounds registered: |cffff6666" .. registered .. "/" .. attempted .. "|r using " .. using
        )
    end
end

-- ── Visual alert ──────────────────────────────────────────────────────────
-- Called from mixin:UpdateDebuffs on every aura refresh. GetUnitAuraBySpellID
-- is one of the few aura APIs still callable by tainted code; it returns
-- nothing (and does not error) for auras the client is keeping secret, so this
-- fires in the open world and on non-secret spells and stays quiet otherwise.
function ns.Alert:Check(unit)
    if not unit then
        return
    end
    local getBySpellID = C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not getBySpellID then
        return
    end

    local db = ns.DB and ns.DB() or {}
    local now = GetTime()

    for spellID, sa in pairs(db.spellAlerts or {}) do
        local id = tonumber(spellID)
        if id and sa and sa.enabled and sa.threshold then
            local ok, aura = pcall(getBySpellID, unit, id)
            -- A boolean test on a non-boolean secret is permitted, so this is
            -- safe even when the engine hands back a secret table.
            if ok and aura and ns.CanRead(aura) then
                local apps = aura.applications
                if not ns.IsSecret(apps) then
                    local stacks = tonumber(apps) or 1
                    if stacks >= sa.threshold then
                        local last = lastAlerted[id] or 0
                        if (now - last) >= REPEAT_COOLDOWN then
                            lastAlerted[id] = now
                            FireAlert(SpellName(id), stacks)
                            return
                        end
                    end
                end
            end
        end
    end
end

function ns.Alert:Test()
    FireAlert("Test Spell", 3)
end

-- Lists the sound names available through LibSharedMedia, optionally filtered.
function ns.Alert:PrintSoundNames(filter)
    local names = self:ListSoundNames()
    if not names then
        ns.Print(
            "LibSharedMedia is not loaded, so there are no shared sound "
                .. "names, so only the built-in alert sound is available."
        )
        return
    end

    filter = filter and filter ~= "" and filter:lower() or nil
    local shown, total = {}, 0
    for _, name in ipairs(names) do
        if not filter or name:lower():find(filter, 1, true) then
            total = total + 1
            if #shown < 40 then
                shown[#shown + 1] = name
            end
        end
    end

    if total == 0 then
        ns.Print("No sound names match |cffffff00" .. (filter or "") .. "|r.")
        return
    end

    ns.Print("Sound names (" .. total .. (filter and (" matching '" .. filter .. "'") or "") .. "):")
    DEFAULT_CHAT_FRAME:AddMessage("  " .. table.concat(shown, ", "))
    if total > #shown then
        DEFAULT_CHAT_FRAME:AddMessage(
            "  ...and " .. (total - #shown) .. " more. Narrow it with |cffffff00/ctank sounds <text>|r."
        )
    end
    DEFAULT_CHAT_FRAME:AddMessage("  Pick one with |cffffff00/ctank sound set <name>|r.")
end

-- Sets the alert sound by name (or literal path) and re-registers.
function ns.Alert:SetSound(name)
    name = name and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        return
    end

    local db = ns.DB()
    db.alertSoundFile = name
    db.alertSoundFileID = nil
    soundWarned = false

    local resolved = self:ResolveSoundPath()
    if resolved == name and not name:find("\\") then
        ns.Print(
            "|cffff4040No sound named '"
                .. name
                .. "' is registered.|r "
                .. "Use |cffffff00/ctank sounds|r to list them."
        )
        return
    end

    ns.Print("Alert sound set to |cff5ab4ff" .. name .. "|r")
    self:ReportAuraSounds()
end

-- Re-applies the global font choice to the alert banner.
function ns.Alert:RefreshFont()
    if not alertFrame then
        return
    end
    local db = ns.DB and ns.DB() or {}
    alertFrame.text:SetFont(ns.FontPath(), db.alertTextSize or 22, ns.FontFlags())
end

function ns.Alert:SetTextSize(size)
    local db = ns.DB and ns.DB() or {}
    db.alertTextSize = math.max(12, math.min(48, tonumber(size) or 22))
    if alertFrame then
        alertFrame.text:SetFont(ns.FontPath(), db.alertTextSize, ns.FontFlags())
    end
    ns.RestyleAuraButtons()
end

function ns.Alert:ApplyPosition()
    if not alertFrame then
        return
    end
    local db = ns.DB and ns.DB() or {}
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint(
        db.alertPoint or "CENTER",
        UIParent,
        db.alertRelPoint or "CENTER",
        db.alertX or 0,
        db.alertY or 200
    )
end
