if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
if not (CUI and CUI.IS_FOREVER) then return end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_RaidDebuffs.lua  (WoW Forever only)
--  Raid Debuffs: a row of the raid debuffs you pick (Sunder Armor, Faerie
--  Fire, the curses, Demoralizing Shout ...) on your target. A debuff that
--  is up shows bright with its time and stacks; one that is missing shows
--  dim, so a gap is easy to see.
--
--  How: WoW Forever gives addons no aura data in combat, so this code never
--  learns whether a debuff is up. Blizzard's aura container does. Each debuff
--  gets an aura slot matched on every spell ID with its name
--  (RaidDebuffsData.lua); the game shows the slot's icon while one of them
--  is on the target. Under each slot sits a dim icon of our own, the missing
--  look, which shows through while the slot is empty.
--
--  A container cannot drop a slot, so changing the picks builds a new
--  container. Building happens out of combat, while auras are readable.
-------------------------------------------------------------------------------
local _, module = ...

local DEBUFFS = module.RAID_DEBUFFS or {}
local DEFAULTS = { enabled = false, iconSize = 30, groupOnly = true }
for _, skinData in ipairs(DEBUFFS) do
    DEFAULTS["pick_" .. skinData.key] = skinData.default
end
local F = module.Feature("raidDebuffs", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = 140 })
local Get, Enabled = F.Get, F.Enabled

local GAP = 3
local STYLE = "cui:raiddebuffs"
local holderFrame, boxHolder
local cells = {}
local built, pending = nil, false -- built = the picks key the current container was made for

local function Picked()
    local result = {}
    for _, skinData in ipairs(DEBUFFS) do
        if Get("pick_" .. skinData.key) then result[#result + 1] = skinData end
    end
    return result
end

local function PickKey(entries)
    local keyList = { tostring(Get("iconSize")) }
    for _, skinData in ipairs(entries) do
        keyList[#keyList + 1] = skinData.key
    end
    return table.concat(keyList, ",")
end

local function Cell(index)
    local c = cells[index]
    if c then return c end
    c = CreateFrame("Frame", nil, holderFrame)
    c.missing = c:CreateTexture(nil, "BACKGROUND")
    c.missing:SetAllPoints()
    c.missing:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.missing:SetDesaturated(true)
    c.missing:SetAlpha(0.35)
    local border = c:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    cells[index] = c
    return c
end

local function CanBuild()
    local AK = CUI.AuraKit
    return AK and AK.CreateContainerShell and not InCombatLockdown() and not AK.AurasRestricted()
end

-- Builds (or rebuilds) the row for the current picks.
local function Rebuild()
    if not holderFrame then return end
    local entries = Enabled() and Picked() or {}
    local key = PickKey(entries)
    if key == built then return end
    if not CanBuild() then
        pending = true
        return
    end
    pending = false
    local AK = CUI.AuraKit
    if boxHolder then
        boxHolder:SetEnabled(false)
        boxHolder:Hide()
        boxHolder = nil
    end
    built = key
    local size = Get("iconSize")
    for index, skinData in ipairs(entries) do
        local c = Cell(index)
        c:SetSize(size, size)
        c:ClearAllPoints()
        c:SetPoint("LEFT", holderFrame, "LEFT", (index - 1) * (size + GAP), 0)
        c.missing:SetTexture(C_Spell.GetSpellTexture(skinData.ids[1]))
        c:Show()
    end
    for index = #entries + 1, #cells do
        cells[index]:Hide()
    end
    holderFrame:SetSize(math.max(1, #entries) * (size + GAP) - GAP, size)
    if #entries == 0 then return end

    AK.styles[STYLE] = { width = size, height = size }
    local success, err = pcall(function()
        local cont = AK.CreateContainerShell(holderFrame, { point = { "TOPLEFT", holderFrame, "TOPLEFT" } })
        for index, skinData in ipairs(entries) do
            local set = {}
            for _, ident in ipairs(skinData.ids) do
                set[ident] = true
            end
            local cell = cells[index]
            AK.AddSlotToContainer(cont, {
                key = skinData.key,
                filter = { "HARMFUL" },
                candidateFilters = { includeSpellIDs = set },
                style = STYLE,
                extraInit = function(btnFrame)
                    btnFrame:SetAllPoints(cell)
                    -- Display only: an aura button takes the mouse by default.
                    if btnFrame.SetMouseClickEnabled then btnFrame:SetMouseClickEnabled(false) end
                    if btnFrame.SetMouseMotionEnabled then btnFrame:SetMouseMotionEnabled(false) end
                end,
            })
        end
        AK.FinishContainer(cont, "target")
        boxHolder = cont
    end)
    if not success then
        built = nil
        CUI.Print("|cffff4040Raid Debuffs could not be set up:|r " .. tostring(err))
    end
end

-- Alpha only, which is safe in combat: shown with a living enemy targeted
-- (and in a group, unless Group Only is off).
local function UpdateShown()
    if not holderFrame then return end
    local show = Enabled() and UnitExists("target")
    if show then
        local enemy = UnitCanAttack("player", "target")
        if not (issecretvalue and issecretvalue(enemy)) then show = enemy and not UnitIsDead("target") end
    end
    if show and Get("groupOnly") then show = IsInGroup() end
    if CUI._unlockActive then show = Enabled() end
    holderFrame:SetAlpha(show and 1 or 0)
end

local function Build()
    if holderFrame then return holderFrame end
    holderFrame = CreateFrame("Frame", "CludesUIRaidDebuffs", UIParent)
    holderFrame:SetSize(Get("iconSize"), Get("iconSize"))
    return holderFrame
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_REGEN_ENABLED" or evt == "ADDON_RESTRICTION_STATE_CHANGED" then
        if pending then Rebuild() end
    end
    UpdateShown()
end)

local function Apply()
    if Enabled() then
        Build()
        for _, event in ipairs({
            "PLAYER_TARGET_CHANGED",
            "GROUP_ROSTER_UPDATE",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_ENTERING_WORLD",
        }) do
            eventFrame:RegisterEvent(event)
        end
        pcall(eventFrame.RegisterEvent, eventFrame, "ADDON_RESTRICTION_STATE_CHANGED")
        eventFrame:RegisterUnitEvent("UNIT_FACTION", "target")
        eventFrame:RegisterUnitEvent("UNIT_FLAGS", "target")
        if not CUI._unlockActive and not InCombatLockdown() then F.Place(holderFrame) end
    else
        eventFrame:UnregisterAllEvents()
    end
    Rebuild()
    UpdateShown()
end

CUI._RaidDebuffs = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply, Debuffs = DEBUFFS }

F.Start(Apply, {
    key = "CUI_RaidDebuffs",
    label = "Raid Debuffs",
    order = 739,
    frame = function(build)
        if build then
            Build()
            Rebuild()
            UpdateShown()
        end
        return holderFrame
    end,
    size = function()
        local num = math.max(1, #Picked())
        local size = Get("iconSize")
        return num * size + (num - 1) * GAP, size
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
