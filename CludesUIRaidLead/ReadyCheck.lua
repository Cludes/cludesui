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
local _, ns = ...

-- Inventory slots that take an enchant in Midnight, and their names.
local ENCHANT_SLOTS = { [1] = "Head", [3] = "Shoulders", [5] = "Chest", [8] = "Feet",
                        [11] = "Ring", [12] = "Ring", [16] = "Main Hand", [17] = "Off Hand" }

function ns.ReadyCheckSettings()
    local p = ns.RaidLeadDB()
    p.readyCheck = p.readyCheck or {}
    local s = p.readyCheck
    if s.enabled == nil then s.enabled = true end
    if s.minDurability == nil then s.minDurability = 30 end
    if s.consumables == nil then s.consumables = true end
    return s
end

local function LowestDurability()
    local low
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max * 100
            if not low or pct < low then low = pct end
        end
    end
    return math.floor((low or 100) + 0.5)
end

local function MissingEnchants()
    local missing = {}
    for slot, name in pairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local enchant = link:match("item:%d+:(%d*)")
            local isWeaponOffhand = true
            if slot == 17 then
                local classID = select(6, C_Item.GetItemInfoInstant(link))
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
    local out = {}
    local presets = CludesUI.BUFF_PRESETS and CludesUI.BUFF_PRESETS.spells and CludesUI.BUFF_PRESETS.spells.raidcds
    local _, class = UnitClass("player")
    for id, info in pairs(presets or {}) do
        if info.class == class and IsPlayerSpell(id) then
            local cd = C_Spell.GetSpellCooldown(id)
            if cd and not (issecretvalue and issecretvalue(cd.duration)) and cd.duration and cd.duration > 1.5 then
                local name = C_Spell.GetSpellName(id)
                if type(name) == "string" then out[#out + 1] = name end
            end
        end
    end
    table.sort(out)
    return out
end

local WELL_FED_ICON = 136000
local HEALTHSTONES = { 5512, 224464 }   -- Healthstone, Demonic Healthstone

local function HasAnyAura(ids)
    for _, id in ipairs(ids or {}) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and aura then return true end
    end
    return false
end

local function WellFed()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
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
    local out = {}
    if not HasAnyAura(prep.flask) then out[#out + 1] = "Flask" end
    local ok, fed = pcall(WellFed)
    if not (ok and fed) then out[#out + 1] = "Food" end
    if not HasAnyAura(prep.rune) then out[#out + 1] = "Rune" end
    local stone = false
    for _, id in ipairs(HEALTHSTONES) do
        if (C_Item.GetItemCount(id) or 0) > 0 then stone = true end
    end
    if not stone then out[#out + 1] = "Healthstone" end
    return table.concat(out, ",")
end
ns.MissingConsumables = MissingConsumables

--- The report this player sends: "dur|ilvl|enchants,..|cooldowns,..|consumables,..".
function ns.MyReadyReport()
    local _, equipped = GetAverageItemLevel()
    return ("%d|%d|%s|%s|%s"):format(LowestDurability(), math.floor((equipped or 0) + 0.5),
        table.concat(MissingEnchants(), ","), table.concat(CooldownsNotReady(), ","), MissingConsumables())
end

-------------------------------------------------------------------------------
--  The leader's window
-------------------------------------------------------------------------------
local reports = {}       -- name -> { dur, ilvl, enchants = {}, cds = {} }
local win, rows = nil, {}

local function Font() return CludesUI.GetFontPath(nil) end

local function BuildWindow()
    if win then return end
    win = CreateFrame("Frame", "CludesUIRaidLeadReadyCheck", UIParent)
    win:SetSize(520, 60)
    win:SetPoint("TOP", UIParent, "TOP", 0, -140)
    CludesUI.Kit.Panel(win, 0.92)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    local title = win:CreateFontString(nil, "OVERLAY")
    CludesUI.Kit.Font(title, 15, nil)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText("Ready Check")
    CludesUI.Kit.AccentText(title)
    win.title = title
    local close = CludesUI.Kit.Glyph(win, "x", function() win:Hide() end, nil, nil)
    close:SetPoint("TOPRIGHT", -5, -5)
    win:Hide()
    tinsert(UISpecialFrames, "CludesUIRaidLeadReadyCheck")
end

local function Row(i)
    local fs = rows[i]
    if not fs then
        fs = win:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(fs, 13, nil)
        fs:SetJustifyH("LEFT")
        fs:SetWidth(500)
        fs:SetWordWrap(false)
        rows[i] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -30 - (i - 1) * 17)
    fs:Show()
    return fs
end

local function Members()
    local out = {}
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
        local name = UnitName(unit)
        if type(name) == "string" and not (issecretvalue and issecretvalue(name)) then out[#out + 1] = name end
    end
    return out
end

function ns.RefreshReadyWindow()
    if not win then return end
    local s = ns.ReadyCheckSettings()
    local lines = {}
    local silent = {}
    for _, name in ipairs(Members()) do
        local r = reports[name]
        if not r then
            silent[#silent + 1] = name
        else
            local problems = {}
            if r.dur < s.minDurability then problems[#problems + 1] = "|cffff6040" .. r.dur .. "% durability|r" end
            if #r.enchants > 0 then problems[#problems + 1] = "|cffffb040no enchant: " .. table.concat(r.enchants, ", ") .. "|r" end
            if #r.cds > 0 then problems[#problems + 1] = "|cffffd060on cooldown: " .. table.concat(r.cds, ", ") .. "|r" end
            if s.consumables then
                if r.cons == "?" then
                    problems[#problems + 1] = "|cff9aa6b2buffs hidden by the game|r"
                elseif r.cons and r.cons ~= "" then
                    problems[#problems + 1] = "|cffff9050missing: " .. r.cons:gsub(",", ", ") .. "|r"
                end
            end
            lines[#lines + 1] = { bad = #problems > 0, text = ("%s  |cff9aa6b2%d ilvl|r  %s"):format(name, r.ilvl,
                #problems > 0 and table.concat(problems, "   ") or "|cff60d080all good|r") }
        end
    end
    table.sort(lines, function(a, b)
        if a.bad ~= b.bad then return a.bad end
        return a.text < b.text
    end)
    if #silent > 0 then
        table.sort(silent)
        lines[#lines + 1] = { text = "|cff9aa6b2No answer (no CludesUI): " .. table.concat(silent, ", ") .. "|r" }
    end
    for i, l in ipairs(lines) do Row(i):SetText(l.text) end
    for i = #lines + 1, #rows do rows[i]:Hide() end
    win:SetHeight(40 + #lines * 17)
end

--- Called by Comms.lua with a player's report.
function ns.ReceiveReadyReport(name, report)
    -- The consumables field is new; a report from an older CludesUI has four fields.
    local dur, ilvl, ench, cds, cons = report:match("^(%d+)|(%d+)|([^|]*)|([^|]*)|(.*)$")
    if not dur then
        dur, ilvl, ench, cds = report:match("^(%d+)|(%d+)|([^|]*)|(.*)$")
    end
    if not dur then return end
    local function List(s)
        local t = {}
        for v in s:gmatch("[^,]+") do t[#t + 1] = v end
        return t
    end
    reports[name] = { dur = tonumber(dur), ilvl = tonumber(ilvl), enchants = List(ench), cds = List(cds), cons = cons }
    ns.RefreshReadyWindow()
end

--- Shows the window as it is now (for testing outside a ready check).
function ns.ShowReadyWindow()
    BuildWindow()
    reports[UnitName("player")] = nil
    ns.ReceiveReadyReport(UnitName("player"), ns.MyReadyReport())
    win:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("READY_CHECK")
ev:SetScript("OnEvent", function()
    if not ns.ReadyCheckSettings().enabled then return end
    wipe(reports)
    if ns.SendReadyReport then ns.SendReadyReport(ns.MyReadyReport()) end
    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        BuildWindow()
        win:Show()
        ns.ReceiveReadyReport(UnitName("player"), ns.MyReadyReport())
        C_Timer.After(3, ns.RefreshReadyWindow)
    end
end)
