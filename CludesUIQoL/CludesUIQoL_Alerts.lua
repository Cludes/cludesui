if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQoL_Alerts.lua
--  Center-screen text alerts that share ONE movable anchor (Unlock Mode: Alerts).
--  Each alert is a line stacked under the anchor, with its own text, size and
--  color. Short alerts fade out by themselves; a persistent one stays until its
--  condition ends or its alert dismisses it. The lines never take the mouse, so
--  nothing behind them is blocked.
--    Combat Alert     (CludesUIQoL.lua)   short
--    Potion Ready     (below)                short
--    Unspent Talents  (below)                persistent
--  Nothing is built or registered for an alert until it is enabled.
-------------------------------------------------------------------------------

local mod = select(2, ...)
local CUI = CludesUI
local DEFAULT_SIZE = 22
local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 169 }
local GAP = 4

local function SavedDB(key)
    return CludesUIDB and CludesUIDB[key]
end

-------------------------------------------------------------------------------
--  Core: anchor + stacked lines
-------------------------------------------------------------------------------
local Alerts = {}
CUI.Alerts = Alerts

-- Stack order, top first. sizeKey/enabledKey are the alert's own settings.
local DEFS = {
    { id = "talent", sizeKey = "talentAlertTextSize", enabledKey = "talentAlertEnabled", persistent = true },
    { id = "combat", sizeKey = "combatAlertTextSize", enabledKey = "combatAlertEnabled", hold = 1.2 },
    { id = "potion", sizeKey = "potionAlertTextSize", enabledKey = "potionAlertEnabled", hold = 3 },
}
local lines = {}
local anchorFrame

-- Defaults for the two new alerts; the options cogs read these too.
Alerts.DEFAULTS = {
    potionAlert = { text = "Potion Ready", color = { r = 0.1, g = 1, b = 0.1 } },
    talentAlert = { text = "Unspent talent points", color = { r = 1, g = 0.82, b = 0 } },
}

local function SizeOf(spec_def)
    return SavedDB(spec_def.sizeKey) or DEFAULT_SIZE
end

local function AnyEnabled()
    for _, spec_def in ipairs(DEFS) do
        if SavedDB(spec_def.enabledKey) then
            return true
        end
    end
    return false
end

local function MaxSize()
    local m = DEFAULT_SIZE
    for _, spec_def in ipairs(DEFS) do
        if SavedDB(spec_def.enabledKey) then
            m = math.max(m, SizeOf(spec_def))
        end
    end
    return m
end

-- The old Combat Alert position carries over until the anchor is moved.
local function AnchorPos()
    local p = SavedDB("alertsPos")
    if p and p.point then
        return p
    end
    p = SavedDB("combatAlertPos")
    if p and p.point then
        return p
    end
    return DEFAULT_POS
end

local function PlaceAnchor()
    if not anchorFrame then
        return
    end
    local dim = MaxSize()
    anchorFrame:SetSize(dim * 7, dim + 14)
    local place = AnchorPos()
    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x or 0, place.y or 0)
end

local function EnsureAnchor()
    if anchorFrame then
        return
    end
    anchorFrame = CreateFrame("Frame", nil, UIParent)
    anchorFrame:EnableMouse(false)
    anchorFrame:SetMouseClickEnabled(false)
    PlaceAnchor()
end

local function Layout()
    if not anchorFrame then
        return
    end
    local offset = 0
    for _, spec_def in ipairs(DEFS) do
        local lineTex = lines[spec_def.id]
        if lineTex and lineTex.frame:IsShown() then
            lineTex.frame:ClearAllPoints()
            lineTex.frame:SetPoint("TOP", anchorFrame, "TOP", 0, -offset)
            offset = offset + lineTex.frame:GetHeight() + GAP
        end
    end
end

local function Style(lineTex)
    local outline = (CUI.GetFontOutlineFlag("extras")) or ""
    if not outline:find("OUTLINE") then
        outline = (outline == "") and "OUTLINE" or (outline .. ", OUTLINE")
    end
    local dim = SizeOf(lineTex.def)
    CUI.ApplyModuleFont(lineTex.text, nil, dim, "extras", outline)
    lineTex.frame:SetSize(dim * 7, dim + 14)
end

local function NewLine(spec_def)
    local lineTex = { def = spec_def }
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(60)
    f:EnableMouse(false)
    f:Hide()
    local fontStr = f:CreateFontString(nil, "OVERLAY")
    fontStr:SetPoint("CENTER")
    lineTex.frame, lineTex.text = f, fontStr

    -- Short: fade in, hold, fade out, then hide. Also used for previews.
    local short = f:CreateAnimationGroup()
    local a1 = short:CreateAnimation("Alpha")
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetDuration(0.15)
    a1:SetOrder(1)
    local a2 = short:CreateAnimation("Alpha")
    a2:SetFromAlpha(1)
    a2:SetToAlpha(1)
    a2:SetDuration(spec_def.hold or 1.2)
    a2:SetOrder(2)
    local a3 = short:CreateAnimation("Alpha")
    a3:SetFromAlpha(1)
    a3:SetToAlpha(0)
    a3:SetDuration(0.5)
    a3:SetOrder(3)
    short:SetScript("OnFinished", function()
        f:Hide()
    end)

    -- Persistent: fade in and stay.
    local stay = f:CreateAnimationGroup()
    local s1 = stay:CreateAnimation("Alpha")
    s1:SetFromAlpha(0)
    s1:SetToAlpha(1)
    s1:SetDuration(0.15)
    s1:SetOrder(1)

    f:SetScript("OnShow", Layout)
    f:SetScript("OnHide", function()
        short:Stop()
        stay:Stop()
        lineTex.persistentShown = false
        Layout()
    end)

    -- preview: play the short animation even on a persistent line, and never
    -- disturb a real persistent alert that is already up.
    function lineTex.Show(textValue, r, g, b, preview)
        if CUI._unlockActive then
            return
        end
        local real = spec_def.persistent and not preview
        if preview and lineTex.persistentShown then
            return
        end
        EnsureAnchor()
        PlaceAnchor()
        Style(lineTex)
        fontStr:SetText(textValue)
        fontStr:SetTextColor(r or 1, g or 1, b or 1)
        if real and lineTex.persistentShown then
            return
        end -- already up: only the text changed
        short:Stop()
        stay:Stop()
        f:SetAlpha(1)
        f:Show()
        if real then
            lineTex.persistentShown = true
            stay:Play()
        else
            short:Play()
        end
    end

    function lineTex.Hide()
        f:Hide()
    end

    function lineTex.Dismiss()
        f:Hide()
        if lineTex.onDismiss then
            lineTex.onDismiss()
        end
    end

    return lineTex
end

-- The line for an alert, built on first use.
function Alerts.Line(ident)
    if not lines[ident] then
        for _, spec_def in ipairs(DEFS) do
            if spec_def.id == ident then
                lines[ident] = NewLine(spec_def)
            end
        end
    end
    return lines[ident]
end

function Alerts.Hide(ident)
    if lines[ident] then
        lines[ident].Hide()
    end
end

-- Re-apply size, position and stacking (Text Size sliders, Unlock Mode).
function Alerts.Refresh()
    if anchorFrame or AnyEnabled() then
        EnsureAnchor()
        PlaceAnchor()
    end
    for _, lineTex in pairs(lines) do
        Style(lineTex)
    end
    Layout()
end

-- Custom color, or the player's class color when that toggle is on.
function Alerts.Color(prefixText, dr, dg, saved)
    if SavedDB(prefixText .. "UseClassColor") then
        local _, token = UnitClass("player")
        if token then
            local c = CUI.GetClassColor(token)
            return c.r, c.g, c.b
        end
    end
    local c = SavedDB(prefixText .. "Color")
    if c then
        return c.r, c.g, c.b
    end
    return dr, dg, saved
end

local function RegisterUnlock()
    CUI:RegisterUnlockElements({
        CUI.MakeUnlockElement({
            key = "CUI_CombatAlert",
            label = "Alerts",
            group = "Utilities",
            order = 721,
            noResize = true,
            isHidden = function()
                return not AnyEnabled()
            end,
            getFrame = function()
                if not AnyEnabled() then
                    return nil
                end -- nothing is built while all are off
                EnsureAnchor()
                return anchorFrame
            end,
            getSize = function()
                local dim = MaxSize()
                return dim * 7, dim + 14
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if not anchorPoint then
                    return
                end
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                CludesUIDB.alertsPos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                if anchorFrame and not CUI._unlockActive then
                    PlaceAnchor()
                    Layout()
                end
            end,
            loadPos = function()
                local p = AnchorPos()
                return { point = p.point, relPoint = p.relPoint, x = p.x, y = p.y }
            end,
            clearPos = function()
                if CludesUIDB then
                    CludesUIDB.alertsPos = nil
                    CludesUIDB.combatAlertPos = nil
                end
                if anchorFrame then
                    PlaceAnchor()
                    Layout()
                end
            end,
            applyPos = function()
                if anchorFrame or AnyEnabled() then
                    EnsureAnchor()
                    PlaceAnchor()
                    Layout()
                end
            end,
        }),
    })
end

local coreBoot = CreateFrame("Frame")
coreBoot:RegisterEvent("PLAYER_LOGIN")
coreBoot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    RegisterUnlock()
end)

-------------------------------------------------------------------------------
--  Potion Ready
--  The potion you drank is found from its on-use spell (UNIT_SPELLCAST_SUCCEEDED),
--  its cooldown is read once from the item API, and one timer fires at the end.
--  The item cooldown API is not secret-restricted, so it is readable in combat.
--  BAG_UPDATE_COOLDOWN is only listened to while a potion is waiting to start or
--  finish, so presses of other abilities cost nothing in between.
-------------------------------------------------------------------------------
do
    local POTION_CLASS = Enum.ItemClass.Consumable
    local POTION_SUBCLASS = 1 -- Enum.ItemConsumableSubclass.Potion
    local MIN_CD = 1.5 -- anything longer is the potion's own cooldown, not the GCD
    local GetInstant = C_Item and C_Item.GetItemInfoInstant
    local GetUseSpell = C_Item and C_Item.GetItemSpell

    local watcher
    local installed = false
    local spellToItem = {} -- on-use spellID -> itemID, for potions seen in bags
    local seen = {} -- itemID -> true (mapped potion) / false (not a potion)
    local timer, pendingItem, usedItem

    local function ShowAlert(preview)
        local D = Alerts.DEFAULTS.potionAlert
        local r, g, b = Alerts.Color("potionAlert", D.color.r, D.color.g, D.color.b)
        Alerts.Line("potion").Show(SavedDB("potionAlertText") or D.text, r, g, b, preview)
    end

    -- start, duration; nil if the item has no cooldown data.
    local function ReadCD(itemId)
        local start, dur = C_Container.GetItemCooldown(itemId)
        if not start or issecretvalue(start) or issecretvalue(dur) then
            return nil
        end
        return start, dur
    end

    local function UpdateCooldownEvent()
        if not watcher then
            return
        end
        if installed and (pendingItem or usedItem) then
            watcher:RegisterEvent("BAG_UPDATE_COOLDOWN")
        else
            watcher:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        end
    end

    local function CancelTimer()
        if timer then
            timer:Cancel()
            timer = nil
        end
        pendingItem = nil
    end

    local ArmTimer

    local function OnReady()
        timer = nil
        local itemId = pendingItem
        pendingItem = nil
        if not itemId then
            UpdateCooldownEvent()
            return
        end
        -- Last one used up: nothing to be ready for.
        if (C_Item.GetItemCount(itemId) or 0) <= 0 then
            UpdateCooldownEvent()
            return
        end
        -- A cooldown extended since we armed is re-read here, so the alert is
        -- only for a potion that is really ready.
        local start, dur = ReadCD(itemId)
        if start and dur and dur > MIN_CD then
            local leftX = start + dur - GetTime()
            if leftX > 0.5 then
                ArmTimer(itemId, leftX)
                return
            end
        end
        UpdateCooldownEvent()
        ShowAlert()
    end

    ArmTimer = function(itemId, delay)
        CancelTimer()
        pendingItem = itemId
        timer = C_Timer.NewTimer(math.max(delay, 0), OnReady)
        UpdateCooldownEvent()
    end

    -- Try to start tracking the potion just used. Returns true once armed or given up.
    local function TrackUsed()
        local itemId = usedItem
        if not itemId then
            return true
        end
        local start, dur = ReadCD(itemId)
        if not start then
            usedItem = nil
            UpdateCooldownEvent()
            return true
        end
        if dur > MIN_CD then
            usedItem = nil
            ArmTimer(itemId, start + dur - GetTime())
            return true
        end
        return false -- cooldown not started yet; wait for BAG_UPDATE_COOLDOWN
    end

    -- Item IDs only (no per-slot tables); each item is classified once.
    local function ScanBag(bag)
        for slotIndex = 1, C_Container.GetContainerNumSlots(bag) do
            local ident = C_Container.GetContainerItemID(bag, slotIndex)
            if ident and seen[ident] == nil then
                local _, _, _, _, _, classID, subID = GetInstant(ident)
                if classID == POTION_CLASS and subID == POTION_SUBCLASS then
                    local _, spellId = GetUseSpell(ident)
                    if spellId then
                        spellToItem[spellId] = ident
                        seen[ident] = true
                    end
                else
                    seen[ident] = false
                end
            end
        end
    end

    -- Every bag when turned on; afterwards only the bags BAG_UPDATE flagged.
    local dirtyBags = {}
    local function ScanBags(onlyDirty)
        if not (GetInstant and GetUseSpell) then
            return
        end
        for bag = 0, NUM_BAG_SLOTS do
            if not onlyDirty or dirtyBags[bag] then
                dirtyBags[bag] = nil
                ScanBag(bag)
            end
        end
    end

    local function OnEvent(_, evt, ...)
        if evt == "UNIT_SPELLCAST_SUCCEEDED" then
            local _, _, spellId = ...
            if issecretvalue(spellId) then
                return
            end
            local itemId = spellToItem[spellId]
            if not itemId then
                return
            end
            usedItem = itemId
            if not TrackUsed() then
                UpdateCooldownEvent()
                -- No cooldown ever appeared (nothing to wait for): stop listening.
                C_Timer.After(2, function()
                    if usedItem == itemId then
                        usedItem = nil
                        UpdateCooldownEvent()
                    end
                end)
            end
        elseif evt == "BAG_UPDATE_COOLDOWN" then
            if usedItem and TrackUsed() then
                return
            end
            if pendingItem then
                -- A reset (encounter end, death) makes the potion ready early.
                local start, dur = ReadCD(pendingItem)
                if start and dur and dur <= MIN_CD then
                    if timer then
                        timer:Cancel()
                        timer = nil
                    end
                    OnReady()
                end
            end
        elseif evt == "BAG_UPDATE" then
            local bag = ...
            if bag then
                dirtyBags[bag] = true
            end
        elseif evt == "BAG_UPDATE_DELAYED" then
            ScanBags(true)
        end
    end

    local function Apply()
        local enabled = SavedDB("potionAlertEnabled")
        if enabled and not installed then
            watcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            watcher:RegisterEvent("BAG_UPDATE")
            watcher:RegisterEvent("BAG_UPDATE_DELAYED")
            installed = true
            ScanBags()
        elseif not enabled and installed then
            watcher:UnregisterAllEvents()
            installed = false
            CancelTimer()
            usedItem = nil
            Alerts.Hide("potion")
        end
        if installed then
            UpdateCooldownEvent()
        end
        Alerts.Refresh()
    end

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", OnEvent)

    CUI._applyPotionAlert = Apply
    CUI._potionAlertFrame = Alerts.Refresh
    CUI._potionAlertPreview = function()
        ShowAlert(true)
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Apply()
    end)
end

-------------------------------------------------------------------------------
--  Unspent Talents (persistent)
--  Same check and trigger events as Blizzard's own talent micro button alert
--  (C_ClassTalents.HasUnspent*), evaluated once after a burst of events.
--  The line stays up while points are unspent, until the talent window opens
--  (Blizzard's PlayerSpellsFrame.TalentTab.Show, an EventRegistry callback); it
--  comes back when new points appear (a level-up), and waits for combat to end
--  before showing. One that came due while Unlock Mode was open shows once it
--  closes.
-------------------------------------------------------------------------------
do
    -- Blizzard's own trigger events for its talent alert.
    local EVENTS = {
        "PLAYER_ENTERING_WORLD",
        "PLAYER_TALENT_UPDATE",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_LEVEL_CHANGED",
    }

    local watcher
    local installed = false
    local lastHad = false
    local dismissed = false
    local dirty = false

    local function HasUnspent()
        if not C_SpecializationInfo.CanPlayerUseTalentUI() then
            return false
        end
        return (C_ClassTalents.HasUnspentTalentPoints() or C_ClassTalents.HasUnspentHeroTalentPoints())
                and true
            or false
    end

    local function Line()
        local lineTex = Alerts.Line("talent")
        lineTex.onDismiss = function()
            dismissed = true
        end
        return lineTex
    end

    local function ShowAlert(preview)
        local D = Alerts.DEFAULTS.talentAlert
        local r, g, b = Alerts.Color("talentAlert", D.color.r, D.color.g, D.color.b)
        Line().Show(SavedDB("talentAlertText") or D.text, r, g, b, preview)
    end

    local function Evaluate()
        dirty = false
        if not installed then
            return
        end
        if InCombatLockdown() then
            mod.CombatQueue.Defer("TalentAlert", Evaluate)
            return
        end
        local has = HasUnspent()
        if has then
            if not lastHad then
                dismissed = false
            end -- new points: show again
            if not dismissed then
                ShowAlert()
            end
        else
            dismissed = false
            Alerts.Hide("talent")
        end
        lastHad = has
    end

    local function MarkDirty()
        if dirty then
            return
        end
        dirty = true
        C_Timer.After(0, Evaluate) -- next frame: one pass per burst of events
    end

    local listening = false
    local function Apply()
        local enabled = SavedDB("talentAlertEnabled")
        if enabled and not installed then
            for _, e in ipairs(EVENTS) do
                watcher:RegisterEvent(e)
            end
            installed = true
            lastHad, dismissed = false, false
            if not listening then
                listening = true
                CUI:RegisterUnlockModeListener("CUI_TalentAlert", function(isActive)
                    if not isActive and installed then
                        MarkDirty()
                    end
                end)
                -- Opening the talents counts as seeing the alert.
                EventRegistry:RegisterCallback("PlayerSpellsFrame.TalentTab.Show", function()
                    if installed then
                        Line().Dismiss()
                    end
                end, "CUI_TalentAlert")
            end
            MarkDirty()
        elseif not enabled and installed then
            watcher:UnregisterAllEvents()
            installed = false
            Alerts.Hide("talent")
        end
        Alerts.Refresh()
    end

    watcher = CreateFrame("Frame")
    watcher:SetScript("OnEvent", function(_, evt)
        -- A level-up brings new points: a dismissed alert shows again.
        if evt == "PLAYER_LEVEL_CHANGED" then
            dismissed = false
        end
        MarkDirty()
    end)

    CUI._applyTalentAlert = Apply
    CUI._talentAlertFrame = Alerts.Refresh
    CUI._talentAlertPreview = function()
        -- A live alert gets its text/color refreshed; otherwise a short sample.
        ShowAlert(not Line().persistentShown)
    end

    local boot = CreateFrame("Frame")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Apply()
    end)
end
