if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Immunities.lua -- Raid Lead: Immunities on You.
--
--  A row of icons for the immunities on you right now: your own (Divine
--  Shield, Ice Block, Aspect of the Turtle, Cloak of Shadows) and ones put on
--  you (Blessing of Protection, Blessing of Spellwarding). The game picks them
--  by spell ID inside an AuraContainer, so the row keeps working in combat,
--  boss fights and keys. More spell IDs can be added on the settings page.
-------------------------------------------------------------------------------
local _, ns = ...

-- Spell IDs as the suite's own defensive lists name them (CludesUI_BuffPresets.lua).
ns.IMMUNITY_DEFAULTS = {
    642, -- Divine Shield
    1022, -- Blessing of Protection
    204018, -- Blessing of Spellwarding
    45438, -- Ice Block
    186265, -- Aspect of the Turtle
    31224, -- Cloak of Shadows
}

function ns.ImmunitySettings()
    local p = ns.RaidLeadDB()
    p.immunities = p.immunities or {}
    local s = p.immunities
    if s.enabled == nil then
        s.enabled = true
    end
    s.size = s.size or 40
    s.extra = s.extra or {}
    return s
end

local function SpellSet()
    local set = {}
    for _, id in ipairs(ns.IMMUNITY_DEFAULTS) do
        set[id] = true
    end
    for _, id in ipairs(ns.ImmunitySettings().extra) do
        set[id] = true
    end
    return set
end

local anchor, container, rejected

local function ApplyPosition()
    if not anchor or InCombatLockdown() then
        return
    end
    local p = ns.ImmunitySettings().pos
    anchor:ClearAllPoints()
    if p then
        anchor:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
end

local function Build()
    if anchor or rejected or InCombatLockdown() then
        return
    end
    if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    if type(AuraContainerSortMethod) ~= "table" then
        return
    end
    local s = ns.ImmunitySettings()
    anchor = CreateFrame("Frame", "CludesUIRaidLeadImmunities", UIParent)
    anchor:SetSize(s.size * 3 + 8, s.size)
    ApplyPosition()
    local ok, c = pcall(CreateFrame, "AuraContainer", nil, anchor, "CustomAuraContainerTemplate")
    if not ok or not c then
        rejected = true
        return
    end
    c:SetSize(s.size, s.size)
    c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    c:SetFlowLayoutAnchorPoint("TOPLEFT")
    c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    c:SetFlowLayoutPadding(0, 0, 0, 0)
    c:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    local added, err = pcall(c.AddAuraGroup, c, "immunities", "HELPFUL", {
        maxFrameCount = 3,
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        candidateFilters = { includeSpellIDs = SpellSet() },
        initializeFrame = function(btn)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn:SetIcon(icon)
            local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
            cd:SetAllPoints(icon)
            cd:SetReverse(true)
            btn:SetDurationCooldown(cd)
        end,
        layout = { elementSpacing = 4, lineSpacing = 4, elementWidth = s.size, elementHeight = s.size },
    })
    if not added then
        rejected = true
        c:Hide()
        CludesUI.Print("|cff4cc9f0Raid Lead:|r Immunities on You could not be set up: " .. tostring(err))
        return
    end
    container = c
    ns.RefreshImmunities()
end

function ns.RefreshImmunities()
    if not container then
        return
    end
    local s = ns.ImmunitySettings()
    pcall(container.SetAuraGroupCandidateFilters, container, "immunities", { includeSpellIDs = SpellSet() })
    pcall(
        container.SetAuraGroupLayout,
        container,
        "immunities",
        { elementSpacing = 4, lineSpacing = 4, elementWidth = s.size, elementHeight = s.size }
    )
    if s.enabled then
        container:SetUnit("player")
    end
    container:SetEnabled(s.enabled)
    if not InCombatLockdown() then
        container:SetShown(s.enabled)
        anchor:SetSize(s.size * 3 + 8, s.size)
    end
end

local registered
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function()
    if InCombatLockdown() then
        return
    end
    Build()
    if registered or not anchor or not CludesUI.RegisterUnlockElements then
        return
    end
    registered = true
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "RLEAD_Immunities",
            label = "Immunities on You",
            group = "Raid Lead",
            order = 661,
            noAnchorTarget = true,
            noResize = true,
            isHidden = function()
                return not ns.ImmunitySettings().enabled
            end,
            getFrame = function()
                return anchor
            end,
            getSize = function()
                local s = ns.ImmunitySettings()
                return s.size * 3 + 8, s.size
            end,
            savePos = function(_, point, relPoint, x, y)
                ns.ImmunitySettings().pos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function()
                return ns.ImmunitySettings().pos
            end,
            clearPos = function()
                ns.ImmunitySettings().pos = nil
            end,
            applyPos = ApplyPosition,
        }),
    }, "CludesUIRaidLead")
end)
