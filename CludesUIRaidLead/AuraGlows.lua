if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  AuraGlows.lua -- Raid Lead: Aura Glows.
--
--  Pick auras by spell ID (a boss debuff that needs you to move, a buff to
--  spend): while one is on you, its icon shows with a glowing border and its
--  time, and pulses. Nothing shows while none is on you.
--
--  How, under 12.1: in boss fights the game hides your auras from addons,
--  so this code never reads them. Blizzard's aura container does: each
--  picked spell gets a slot (helpful and harmful both), matched on its spell
--  ID, and the game shows the slot while the aura is on you. The glow is
--  part of the slot's button, drawn once when the button is made, so it
--  shows and hides with it; the pulse is an animation the game plays itself
--  while the aura is up.
--
--  A container cannot drop a slot, so a change of picks builds a new one,
--  out of combat.
-------------------------------------------------------------------------------
local _, ns = ...

local GAP = 4
local STYLE = "cui:rlead:auraglows"

function ns.AuraGlowSettings()
    local p = ns.RaidLeadDB()
    p.auraGlows = p.auraGlows or {}
    local s = p.auraGlows
    if s.enabled == nil then
        s.enabled = true
    end
    if s.size == nil then
        s.size = 44
    end
    s.spells = s.spells or {} -- { spellID, ... }
    return s
end

--- "123, 456 789" to a list of spell IDs.
function ns.ParseSpellIDs(text)
    local out, seen = {}, {}
    for id in (text or ""):gmatch("%d+") do
        id = tonumber(id)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
    return out
end

local holder, container
local built, pending

local function Key(s)
    local t = { tostring(s.size) }
    for _, id in ipairs(s.spells) do
        t[#t + 1] = id
    end
    return table.concat(t, ",")
end

local function CanBuild()
    local AK = CludesUI.AuraKit
    return AK and AK.CreateContainerShell and not InCombatLockdown() and not AK.AurasRestricted()
end

local function Decorate(button)
    if button.SetMouseClickEnabled then
        button:SetMouseClickEnabled(false)
    end
    if button.SetMouseMotionEnabled then
        button:SetMouseMotionEnabled(false)
    end
    local glow = button:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetPoint("TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", 4, -4)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.25, 1)
    -- The pulse: played by the game while the aura is shown (12.1.5).
    if button.AddAuraShownAnimation then
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.5)
        pcall(button.AddAuraShownAnimation, button, ag)
    end
end

local function Rebuild()
    local s = ns.AuraGlowSettings()
    local list = s.enabled and s.spells or {}
    local key = Key(s) .. (s.enabled and "" or "off")
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
    holder:SetSize(math.max(1, #list) * (s.size + GAP) - GAP, s.size)
    if #list == 0 then
        return
    end
    AK.styles[STYLE] = { width = s.size, height = s.size }
    local ok, err = pcall(function()
        local cont = AK.CreateContainerShell(holder, { point = { "LEFT", holder, "LEFT" } })
        if cont.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
            cont:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        end
        for i, id in ipairs(list) do
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                AK.AddGroupToContainer(cont, {
                    key = filter .. id,
                    filter = { filter },
                    maxFrameCount = 1,
                    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default,
                    sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
                    candidateFilters = { includeSpellIDs = { [id] = true } },
                    style = STYLE,
                    extraInit = function(button)
                        Decorate(button)
                    end,
                    layout = {
                        elementWidth = s.size,
                        elementHeight = s.size,
                        elementSpacing = GAP,
                        lineSpacing = GAP,
                        layoutIndex = i,
                    },
                })
            end
        end
        AK.FinishContainer(cont, "player")
        container = cont
    end)
    if not ok then
        built = nil
        CludesUI.Print("|cffff4040Aura Glows could not be set up:|r " .. tostring(err))
    end
end
ns.RebuildAuraGlows = function()
    built = nil
    Rebuild()
end

local function ApplyPosition()
    if not holder or InCombatLockdown() then
        return
    end
    local p = ns.AuraGlowSettings().pos
    holder:ClearAllPoints()
    if p then
        holder:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        holder:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "ADDON_RESTRICTION_STATE_CHANGED")
local registered
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        if not holder then
            holder = CreateFrame("Frame", "CludesUIRaidLeadAuraGlows", UIParent)
            holder:SetSize(ns.AuraGlowSettings().size, ns.AuraGlowSettings().size)
            ApplyPosition()
        end
        if not registered and CludesUI.RegisterUnlockElements and not InCombatLockdown() then
            registered = true
            CludesUI:RegisterUnlockElements({
                CludesUI.MakeUnlockElement({
                    key = "RLEAD_AuraGlows",
                    label = "Aura Glows",
                    group = "Raid Lead",
                    order = 665,
                    noAnchorTarget = true,
                    noResize = true,
                    isHidden = function()
                        return not ns.AuraGlowSettings().enabled
                    end,
                    getFrame = function()
                        return holder
                    end,
                    getSize = function()
                        local s = ns.AuraGlowSettings()
                        local n = math.max(1, #s.spells)
                        return n * s.size + (n - 1) * GAP, s.size
                    end,
                    savePos = function(_, point, relPoint, x, y)
                        ns.AuraGlowSettings().pos = { point = point, relPoint = relPoint, x = x, y = y }
                    end,
                    loadPos = function()
                        return ns.AuraGlowSettings().pos
                    end,
                    clearPos = function()
                        ns.AuraGlowSettings().pos = nil
                    end,
                    applyPos = ApplyPosition,
                }),
            }, "CludesUIRaidLead")
        end
        Rebuild()
    elseif pending then
        Rebuild()
    end
end)
