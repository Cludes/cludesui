if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
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
for _, d in ipairs(DEBUFFS) do
    DEFAULTS["pick_" .. d.key] = d.default
end
local F = module.Feature("raidDebuffs", DEFAULTS, { point = "CENTER", relPoint = "CENTER", x = 0, y = 140 })
local Get, Enabled = F.Get, F.Enabled

local GAP = 3
local STYLE = "cui:raiddebuffs"
local holder, container
local cells = {}
local built, pending = nil, false -- built = the picks key the current container was made for

local function Picked()
    local out = {}
    for _, d in ipairs(DEBUFFS) do
        if Get("pick_" .. d.key) then
            out[#out + 1] = d
        end
    end
    return out
end

local function PickKey(list)
    local keys = { tostring(Get("iconSize")) }
    for _, d in ipairs(list) do
        keys[#keys + 1] = d.key
    end
    return table.concat(keys, ",")
end

local function Cell(i)
    local c = cells[i]
    if c then
        return c
    end
    c = CreateFrame("Frame", nil, holder)
    c.missing = c:CreateTexture(nil, "BACKGROUND")
    c.missing:SetAllPoints()
    c.missing:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    c.missing:SetDesaturated(true)
    c.missing:SetAlpha(0.35)
    local border = c:CreateTexture(nil, "BACKGROUND", nil, -1)
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    cells[i] = c
    return c
end

local function CanBuild()
    local AK = CludesUI.AuraKit
    return AK and AK.CreateContainerShell and not InCombatLockdown() and not AK.AurasRestricted()
end

-- Builds (or rebuilds) the row for the current picks.
local function Rebuild()
    if not holder then
        return
    end
    local list = Enabled() and Picked() or {}
    local key = PickKey(list)
    if key == built then
        return
    end
    if not CanBuild() then
        pending = true
        return
    end
    pending = false
    local AK = CludesUI.AuraKit
    if container then
        container:SetEnabled(false)
        container:Hide()
        container = nil
    end
    built = key
    local size = Get("iconSize")
    for i, d in ipairs(list) do
        local c = Cell(i)
        c:SetSize(size, size)
        c:ClearAllPoints()
        c:SetPoint("LEFT", holder, "LEFT", (i - 1) * (size + GAP), 0)
        c.missing:SetTexture(C_Spell.GetSpellTexture(d.ids[1]))
        c:Show()
    end
    for i = #list + 1, #cells do
        cells[i]:Hide()
    end
    holder:SetSize(math.max(1, #list) * (size + GAP) - GAP, size)
    if #list == 0 then
        return
    end

    AK.styles[STYLE] = { width = size, height = size }
    local ok, err = pcall(function()
        local cont = AK.CreateContainerShell(holder, { point = { "TOPLEFT", holder, "TOPLEFT" } })
        for i, d in ipairs(list) do
            local set = {}
            for _, id in ipairs(d.ids) do
                set[id] = true
            end
            local cell = cells[i]
            AK.AddSlotToContainer(cont, {
                key = d.key,
                filter = { "HARMFUL" },
                candidateFilters = { includeSpellIDs = set },
                style = STYLE,
                extraInit = function(button)
                    button:SetAllPoints(cell)
                    -- Display only: an aura button takes the mouse by default.
                    if button.SetMouseClickEnabled then
                        button:SetMouseClickEnabled(false)
                    end
                    if button.SetMouseMotionEnabled then
                        button:SetMouseMotionEnabled(false)
                    end
                end,
            })
        end
        AK.FinishContainer(cont, "target")
        container = cont
    end)
    if not ok then
        built = nil
        CludesUI.Print("|cffff4040Raid Debuffs could not be set up:|r " .. tostring(err))
    end
end

-- Alpha only, which is safe in combat: shown with a living enemy targeted
-- (and in a group, unless Group Only is off).
local function UpdateShown()
    if not holder then
        return
    end
    local show = Enabled() and UnitExists("target")
    if show then
        local enemy = UnitCanAttack("player", "target")
        if not (issecretvalue and issecretvalue(enemy)) then
            show = enemy and not UnitIsDead("target")
        end
    end
    if show and Get("groupOnly") then
        show = IsInGroup()
    end
    if CludesUI._unlockActive then
        show = Enabled()
    end
    holder:SetAlpha(show and 1 or 0)
end

local function Build()
    if holder then
        return holder
    end
    holder = CreateFrame("Frame", "CludesUIRaidDebuffs", UIParent)
    holder:SetSize(Get("iconSize"), Get("iconSize"))
    return holder
end

local ev = CreateFrame("Frame")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" or event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if pending then
            Rebuild()
        end
    end
    UpdateShown()
end)

local function Apply()
    if Enabled() then
        Build()
        for _, e in ipairs({
            "PLAYER_TARGET_CHANGED",
            "GROUP_ROSTER_UPDATE",
            "PLAYER_REGEN_ENABLED",
            "PLAYER_ENTERING_WORLD",
        }) do
            ev:RegisterEvent(e)
        end
        pcall(ev.RegisterEvent, ev, "ADDON_RESTRICTION_STATE_CHANGED")
        ev:RegisterUnitEvent("UNIT_FACTION", "target")
        ev:RegisterUnitEvent("UNIT_FLAGS", "target")
        if not CludesUI._unlockActive and not InCombatLockdown() then
            F.Place(holder)
        end
    else
        ev:UnregisterAllEvents()
    end
    Rebuild()
    UpdateShown()
end

CludesUI._RaidDebuffs = { Get = Get, Read = F.Read, Cfg = F.Cfg, Apply = Apply, Debuffs = DEBUFFS }

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
        return holder
    end,
    size = function()
        local n = math.max(1, #Picked())
        local size = Get("iconSize")
        return n * size + (n - 1) * GAP, size
    end,
    noAnchorTarget = true,
    noSizeMatchTarget = true,
})
