if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  GroupHelpers.lua -- Raid Lead: feast alerts, Gateway Usable, Stats panel.
--
--  Feast and cauldron alerts: when a CludesUI user drops a feast, a
--  cauldron, a Soulwell or a repair bot, everyone in the group with CludesUI
--  gets a chat line naming them and a sound. The dropper's own client sees
--  its cast (the combat log is closed to addons), so only drops by CludesUI
--  users are announced. Spell IDs checked against the game's SpellName table
--  (wago.tools, build 12.1.5.70783).
--
--  Gateway Usable: "Gateway usable" while you are close enough to a
--  warlock's Demonic Gateway to click it. The game marks its Gateway Control
--  Shard (item 188152) usable exactly then.
--
--  Stats panel: your crit, haste, mastery and versatility, kept up to date
--  through buffs and procs.
-------------------------------------------------------------------------------
local _, mod = ...

local DROPS = {
    [1237104] = "FEAST",
    [1259658] = "FEAST",
    [1259659] = "FEAST",
    [1278909] = "HEARTY",
    [1278929] = "HEARTY",
    [1278895] = "HEARTY",
    [1240195] = "CAULDRON",
    [1240019] = "CAULDRON",
    [1240267] = "CAULDRON",
    [1240225] = "CAULDRON",
    [29893] = "SOULWELL",
    [199109] = "REPAIR",
    [67826] = "REPAIR",
}
local DROP_TEXT = {
    FEAST = "a Feast",
    HEARTY = "a |cff60d080Hearty|r Feast",
    CAULDRON = "a Cauldron",
    SOULWELL = "a Soulwell",
    REPAIR = "a Repair Bot",
}
local GATEWAY_SHARD = 188152

local function Font()
    return CludesUI.GetFontPath(nil)
end
local function Secret(val)
    return issecretvalue and issecretvalue(val)
end

function mod.HelperSettings()
    local p = mod.RaidLeadDB()
    p.helpers = p.helpers or {}
    local s = p.helpers
    if s.drops == nil then
        s.drops = true
    end
    if s.dropSound == nil then
        s.dropSound = true
    end
    if s.gateway == nil then
        s.gateway = true
    end
    if s.stats == nil then
        s.stats = false
    end
    return s
end

-------------------------------------------------------------------------------
--  Feast alerts
-------------------------------------------------------------------------------
--- Called by Comms.lua (and for our own drops) with who dropped what.
function mod.ReceiveDrop(who, kindOf)
    local s = mod.HelperSettings()
    if not s.drops or not DROP_TEXT[kindOf] then
        return
    end
    local name = (CludesUI.GetNickname and CludesUI.GetNickname(who)) or who
    CludesUI.Print(("|cff4cc9f0Raid Lead:|r %s dropped %s."):format(name, DROP_TEXT[kindOf]))
    if s.dropSound then
        PlaySound(SOUNDKIT.READY_CHECK, "Master")
    end
end

local dropEv = CreateFrame("Frame")
dropEv:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
dropEv:SetScript("OnEvent", function(_, _, _, _, spellId)
    if Secret(spellId) then
        return
    end
    local kindOf = DROPS[spellId]
    if not kindOf or not IsInGroup() then
        return
    end
    -- Our message comes back to us as well, which prints our own drop.
    if not (mod.SendDrop and mod.SendDrop(kindOf)) then
        mod.ReceiveDrop(UnitName("player"), kindOf)
    end
end)

-------------------------------------------------------------------------------
--  Movable text frames (Gateway Usable, Stats)
-------------------------------------------------------------------------------
local function Movable(name, key, labelText, sequence, wid, hgt, default, isHidden)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(wid, hgt)
    local function Place()
        if InCombatLockdown() then
            return
        end
        local p = mod.HelperSettings()[key]
        f:ClearAllPoints()
        if p then
            f:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
        else
            f:SetPoint(unpack(default))
        end
    end
    Place()
    f.register = function()
        CludesUI:RegisterUnlockElements({
            CludesUI.MakeUnlockElement({
                key = "RLEAD_" .. key,
                label = labelText,
                group = "Raid Lead",
                order = sequence,
                noAnchorTarget = true,
                noResize = true,
                isHidden = isHidden,
                getFrame = function()
                    return f
                end,
                getSize = function()
                    return f:GetWidth(), f:GetHeight()
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    mod.HelperSettings()[key] =
                        { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                end,
                loadPos = function()
                    return mod.HelperSettings()[key]
                end,
                clearPos = function()
                    mod.HelperSettings()[key] = nil
                end,
                applyPos = Place,
            }),
        }, "CludesUIRaidLead")
    end
    return f
end

-------------------------------------------------------------------------------
--  Gateway Usable
-------------------------------------------------------------------------------
local gate, gateText
local function GateUpdate()
    if not gate then
        return
    end
    local enabled = mod.HelperSettings().gateway and IsInGroup()
    if enabled then
        local usable = C_Item.IsUsableItem(GATEWAY_SHARD)
        enabled = not Secret(usable) and usable and true or false
    end
    gate:SetShown(enabled or (CludesUI._unlockActive and mod.HelperSettings().gateway) or false)
end

-------------------------------------------------------------------------------
--  Stats panel
-------------------------------------------------------------------------------
local stats, statsText
local function Pct(func, ...)
    local success, val = pcall(func, ...)
    if success and type(val) == "number" and not Secret(val) then
        return val
    end
end

local function StatsUpdate()
    if not stats then
        return
    end
    if not mod.HelperSettings().stats then
        stats:Hide()
        return
    end
    local crit = Pct(GetCritChance)
    local haste = Pct(GetHaste)
    local mastery = Pct(GetMasteryEffect)
    local vers
    if CR_VERSATILITY_DAMAGE_DONE then
        local a = Pct(GetCombatRatingBonus, CR_VERSATILITY_DAMAGE_DONE)
        local b = Pct(GetVersatilityBonus, CR_VERSATILITY_DAMAGE_DONE) or 0
        vers = a and (a + b)
    end
    local function F(val)
        return val and ("%.1f%%"):format(val) or "?"
    end
    statsText:SetText(
        ("|cff9aa6b2Crit|r %s\n|cff9aa6b2Haste|r %s\n|cff9aa6b2Mastery|r %s\n|cff9aa6b2Vers|r %s"):format(
            F(crit),
            F(haste),
            F(mastery),
            F(vers)
        )
    )
    stats:Show()
end

local statsQueued
local function QueueStats()
    if statsQueued then
        return
    end
    statsQueued = true
    C_Timer.After(0.5, function()
        statsQueued = nil
        StatsUpdate()
    end)
end

function mod.RefreshHelpers()
    GateUpdate()
    StatsUpdate()
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("COMBAT_RATING_UPDATE")
ev:RegisterEvent("MASTERY_UPDATE")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:RegisterUnitEvent("UNIT_SPELL_HASTE", "player")
local registered
ev:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" and not gate then
        gate = Movable(
            "CludesUIRaidLeadGateway",
            "gatewayPos",
            "Gateway Usable",
            666,
            160,
            24,
            { "CENTER", UIParent, "CENTER", 0, -60 },
            function()
                return not mod.HelperSettings().gateway
            end
        )
        gateText = gate:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(gateText, 18, nil)
        gateText:SetPoint("CENTER")
        gateText:SetText("|cffb070ffGateway usable|r")
        gate:Hide()
        stats = Movable(
            "CludesUIRaidLeadStats",
            "statsPos",
            "Stats",
            667,
            110,
            60,
            { "RIGHT", UIParent, "RIGHT", -260, 0 },
            function()
                return not mod.HelperSettings().stats
            end
        )
        statsText = stats:CreateFontString(nil, "OVERLAY")
        CludesUI.Kit.Font(statsText, 12, nil)
        statsText:SetPoint("TOPLEFT")
        statsText:SetJustifyH("LEFT")
        stats:Hide()
    end
    if
        evt == "PLAYER_ENTERING_WORLD"
        and not registered
        and not InCombatLockdown()
        and CludesUI.RegisterUnlockElements
    then
        registered = true
        gate.register()
        stats.register()
    end
    if evt == "ACTIONBAR_UPDATE_USABLE" or evt == "GROUP_ROSTER_UPDATE" or evt == "PLAYER_ENTERING_WORLD" then
        GateUpdate()
    end
    if evt ~= "ACTIONBAR_UPDATE_USABLE" and evt ~= "GROUP_ROSTER_UPDATE" then
        QueueStats()
    end
end)
