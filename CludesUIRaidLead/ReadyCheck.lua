if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ReadyCheck.lua -- Raid Lead: gear and cooldown checks on ready check.
--
--  When a ready check starts, every CludesUI user in the group reports their
--  own gear and cooldowns (the game shows an addon nothing of other players'
--  gear without an inspect, so the report comes from each player):
--    durability    lowest item durability, percent
--    ilvl          equipped item level
--    enchants      enchantable slots with no enchant (Midnight: head,
--                  shoulders, chest, feet, both rings, weapons)
--    cooldowns     their raid cooldowns that are not ready
--    consumables   flask, food, augment rune and healthstone they lack.
--                  Read from their own buffs (flask and rune by spell ID,
--                  food by the Well Fed icon) and bags; when the game hides
--                  their buffs from addons the report says so instead.
--  The leader and assistants get a window listing everyone, problems first,
--  and the names of anyone who did not answer (no CludesUI).
-------------------------------------------------------------------------------
local _, mod = ...

-- Inventory slots that take an enchant in Midnight, and their names.
local ENCHANT_SLOTS = {
    [1] = "Head",
    [3] = "Shoulders",
    [5] = "Chest",
    [8] = "Feet",
    [11] = "Ring",
    [12] = "Ring",
    [16] = "Main Hand",
    [17] = "Off Hand",
}

function mod.ReadyCheckSettings()
    local profile = mod.RaidLeadDB()
    profile.readyCheck = profile.readyCheck or {}
    local cfg = profile.readyCheck
    if cfg.enabled == nil then cfg.enabled = true end
    if cfg.minDurability == nil then cfg.minDurability = 30 end
    if cfg.consumables == nil then cfg.consumables = true end
    return cfg
end

local function LowestDurability()
    local low
    for slot = 1, 18 do
        local current, max = GetInventoryItemDurability(slot)
        if current and max and max > 0 then
            local pct = current / max * 100
            if not low or pct < low then low = pct end
        end
    end
    return math.floor((low or 100) + 0.5)
end

local function MissingEnchants()
    local missing = {}
    for slot, name in pairs(ENCHANT_SLOTS) do
        local itemLink = GetInventoryItemLink("player", slot)
        if itemLink then
            local enchant = itemLink:match("item:%d+:(%d*)")
            local isWeaponOffhand = true
            if slot == 17 then
                local classID = select(6, C_Item.GetItemInfoInstant(itemLink))
                isWeaponOffhand = classID == Enum.ItemClass.Weapon
            end
            if isWeaponOffhand and (enchant == nil or enchant == "" or enchant == "0") then
                missing[#missing + 1] = name
            end
        end
    end
    table.sort(missing)
    return missing
end

local function CooldownsNotReady()
    local result = {}
    local presets = CludesUI.BUFF_PRESETS
        and CludesUI.BUFF_PRESETS.spells
        and CludesUI.BUFF_PRESETS.spells.raidcds
    local _, class = UnitClass("player")
    for ident, details in pairs(presets or {}) do
        if details.class == class and IsPlayerSpell(ident) then
            local cd = C_Spell.GetSpellCooldown(ident)
            if
                cd
                and not (issecretvalue and issecretvalue(cd.duration))
                and cd.duration
                and cd.duration > 1.5
            then
                local name = C_Spell.GetSpellName(ident)
                if type(name) == "string" then result[#result + 1] = name end
            end
        end
    end
    table.sort(result)
    return result
end

local WELL_FED_ICON = 136000
local HEALTHSTONES = { 5512, 224464 } -- Healthstone, Demonic Healthstone

local function HasAnyAura(ids)
    for _, ident in ipairs(ids or {}) do
        local success, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, ident)
        if success and aura then return true end
    end
    return false
end

local function WellFed()
    for idx = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", idx, "HELPFUL")
        if not aura then return false end
        local icon = aura.icon
        if icon and not (issecretvalue and issecretvalue(icon)) and icon == WELL_FED_ICON then return true end
    end
    return false
end

--- Consumables this player lacks, or "?" when the game hides their buffs.
local function MissingConsumables()
    local restricted = InCombatLockdown()
        or (CludesUI.AuraKit and CludesUI.AuraKit.AurasRestricted and CludesUI.AuraKit.AurasRestricted())
    if restricted then return "?" end
    local prep = CludesUI.RAID_PREP_IDS or {}
    local result = {}
    if not HasAnyAura(prep.flask) then result[#result + 1] = "Flask" end
    local success, fed = pcall(WellFed)
    if not (success and fed) then result[#result + 1] = "Food" end
    if not HasAnyAura(prep.rune) then result[#result + 1] = "Rune" end
    local stone = false
    for _, ident in ipairs(HEALTHSTONES) do
        if (C_Item.GetItemCount(ident) or 0) > 0 then stone = true end
    end
    if not stone then result[#result + 1] = "Healthstone" end
    return table.concat(result, ",")
end
mod.MissingConsumables = MissingConsumables

--- The report this player sends: "dur|ilvl|enchants,..|cooldowns,..|consumables,..".
function mod.MyReadyReport()
    local _, equipped = GetAverageItemLevel()
    return ("%d|%d|%s|%s|%s"):format(
        LowestDurability(),
        math.floor((equipped or 0) + 0.5),
        table.concat(MissingEnchants(), ","),
        table.concat(CooldownsNotReady(), ","),
        MissingConsumables()
    )
end

-------------------------------------------------------------------------------
--  The leader's window
-------------------------------------------------------------------------------
local reports = {} -- name -> { dur, ilvl, enchants = {}, cds = {} }
local window, rowList = nil, {}

local function Font() return CludesUI.GetFontPath(nil) end

local function BuildWindow()
    if window then return end
    window = CreateFrame("Frame", "CludesUIRaidLeadReadyCheck", UIParent)
    window:SetSize(520, 60)
    window:SetPoint("TOP", UIParent, "TOP", 0, -140)
    CludesUI.Kit.Panel(window, 0.92)
    window:SetMovable(true)
    window:EnableMouse(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    local title = window:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(title, 15, nil)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Ready Check")
    CludesUI.Kit.AccentText(title)
    window.title = title
    local close = CludesUI.Kit.Glyph(window, "x", function() window:Hide() end, nil, nil)
    close:SetPoint("TOPRIGHT", -5, -5)
    window:Hide()
    tinsert(UISpecialFrames, "CludesUIRaidLeadReadyCheck")
end

local function Row(idx)
    local fontStr = rowList[idx]
    if not fontStr then
        fontStr = window:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(fontStr, 13, nil)
        fontStr:SetJustifyH("LEFT")
        fontStr:SetWidth(500)
        fontStr:SetWordWrap(false)
        rowList[idx] = fontStr
    end
    fontStr:ClearAllPoints()
    fontStr:SetPoint("TOPLEFT", window, "TOPLEFT", 10, -30 - (idx - 1) * 17)
    fontStr:Show()
    return fontStr
end

local function Members()
    local result = {}
    for idx = 1, GetNumGroupMembers() do
        local unitToken = IsInRaid() and ("raid" .. idx) or (idx == 1 and "player" or ("party" .. (idx - 1)))
        local name = UnitName(unitToken)
        if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
            result[#result + 1] = name
        end
    end
    return result
end

function mod.RefreshReadyWindow()
    if not window then return end
    local cfg = mod.ReadyCheckSettings()
    local lines = {}
    local silent = {}
    for _, name in ipairs(Members()) do
        local r = reports[name]
        if not r then
            silent[#silent + 1] = name
        else
            local problems = {}
            if r.dur < cfg.minDurability then
                problems[#problems + 1] = "|cffff6040" .. r.dur .. "% durability|r"
            end
            if #r.enchants > 0 then
                problems[#problems + 1] = "|cffffb040no enchant: " .. table.concat(r.enchants, ", ") .. "|r"
            end
            if #r.cds > 0 then
                problems[#problems + 1] = "|cffffd060on cooldown: " .. table.concat(r.cds, ", ") .. "|r"
            end
            if cfg.consumables then
                if r.cons == "?" then
                    problems[#problems + 1] = "|cff9aa6b2buffs hidden by the game|r"
                elseif r.cons and r.cons ~= "" then
                    problems[#problems + 1] = "|cffff9050missing: " .. r.cons:gsub(",", ", ") .. "|r"
                end
            end
            lines[#lines + 1] = {
                bad = #problems > 0,
                text = ("%s  |cff9aa6b2%d ilvl|r  %s"):format(
                    name,
                    r.ilvl,
                    #problems > 0 and table.concat(problems, "   ") or "|cff60d080all good|r"
                ),
            }
        end
    end
    table.sort(lines, function(lhs, rhs)
        if lhs.bad ~= rhs.bad then return lhs.bad end
        return lhs.text < rhs.text
    end)
    if #silent > 0 then
        table.sort(silent)
        lines[#lines + 1] =
            { text = "|cff9aa6b2No answer (no CludesUI): " .. table.concat(silent, ", ") .. "|r" }
    end
    for idx, l in ipairs(lines) do
        Row(idx):SetText(l.text)
    end
    for idx = #lines + 1, #rowList do
        rowList[idx]:Hide()
    end
    window:SetHeight(40 + #lines * 17)
end

--- Called by Comms.lua with a player's report.
function mod.ReceiveReadyReport(name, report)
    -- The consumables field is new; a report from an older CludesUI has four fields.
    local dur, ilvl, ench, cds, cons = report:match("^(%d+)|(%d+)|([^|]*)|([^|]*)|(.*)$")
    if not dur then
        dur, ilvl, ench, cds = report:match("^(%d+)|(%d+)|([^|]*)|(.*)$")
    end
    if not dur then return end
    local function List(text)
        local t = {}
        for val in text:gmatch("[^,]+") do
            t[#t + 1] = val
        end
        return t
    end
    reports[name] =
        { dur = tonumber(dur), ilvl = tonumber(ilvl), enchants = List(ench), cds = List(cds), cons = cons }
    mod.RefreshReadyWindow()
end

--- Shows the window as it is now (for testing outside a ready check).
function mod.ShowReadyWindow()
    BuildWindow()
    reports[UnitName("player")] = nil
    mod.ReceiveReadyReport(UnitName("player"), mod.MyReadyReport())
    window:Show()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("READY_CHECK")
eventFrame:SetScript("OnEvent", function()
    if not mod.ReadyCheckSettings().enabled then return end
    wipe(reports)
    if mod.SendReadyReport then mod.SendReadyReport(mod.MyReadyReport()) end
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        BuildWindow()
        window:Show()
        mod.ReceiveReadyReport(UnitName("player"), mod.MyReadyReport())
        C_Timer.After(3, mod.RefreshReadyWindow)
    end
end)
