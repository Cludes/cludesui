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
local _, mod = ...

local GAP = 4
local STYLE = "cui:rlead:auraglows"

function mod.AuraGlowSettings()
    local p = mod.RaidLeadDB()
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
function mod.ParseSpellIDs(textValue)
    local result, seen = {}, {}
    for ident in (textValue or ""):gmatch("%d+") do
        ident = tonumber(ident)
        if ident and ident > 0 and not seen[ident] then
            seen[ident] = true
            result[#result + 1] = ident
        end
    end
    return result
end

local holderFrame, boxHolder
local built, pending

local function Key(cfg)
    local t = { tostring(cfg.size) }
    for _, ident in ipairs(cfg.spells) do
        t[#t + 1] = ident
    end
    return table.concat(t, ",")
end

local function CanBuild()
    local AK = CludesUI.AuraKit
    return AK and AK.CreateContainerShell and not InCombatLockdown() and not AK.AurasRestricted()
end

local function Decorate(btnFrame)
    if btnFrame.SetMouseClickEnabled then
        btnFrame:SetMouseClickEnabled(false)
    end
    if btnFrame.SetMouseMotionEnabled then
        btnFrame:SetMouseMotionEnabled(false)
    end
    local glow = btnFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetPoint("TOPLEFT", -4, 4)
    glow:SetPoint("BOTTOMRIGHT", 4, -4)
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.85, 0.25, 1)
    -- The pulse: played by the game while the aura is shown (12.1.5).
    if btnFrame.AddAuraShownAnimation then
        local ag = glow:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.35)
        a:SetDuration(0.5)
        pcall(btnFrame.AddAuraShownAnimation, btnFrame, ag)
    end
end

local function Rebuild()
    local s = mod.AuraGlowSettings()
    local entries = s.enabled and s.spells or {}
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
    if boxHolder then
        boxHolder:SetEnabled(false)
        boxHolder:Hide()
        boxHolder = nil
    end
    built = key
    holderFrame:SetSize(math.max(1, #entries) * (s.size + GAP) - GAP, s.size)
    if #entries == 0 then
        return
    end
    AK.styles[STYLE] = { width = s.size, height = s.size }
    local success, err = pcall(function()
        local cont = AK.CreateContainerShell(holderFrame, { point = { "LEFT", holderFrame, "LEFT" } })
        if cont.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
            cont:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
        end
        for idx, ident in ipairs(entries) do
            for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
                AK.AddGroupToContainer(cont, {
                    key = filter .. ident,
                    filter = { filter },
                    maxFrameCount = 1,
                    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default,
                    sortDirection = AuraContainerSortDirection and AuraContainerSortDirection.Normal,
                    candidateFilters = { includeSpellIDs = { [ident] = true } },
                    style = STYLE,
                    extraInit = function(btnFrame)
                        Decorate(btnFrame)
                    end,
                    layout = {
                        elementWidth = s.size,
                        elementHeight = s.size,
                        elementSpacing = GAP,
                        lineSpacing = GAP,
                        layoutIndex = idx,
                    },
                })
            end
        end
        AK.FinishContainer(cont, "player")
        boxHolder = cont
    end)
    if not success then
        built = nil
        CludesUI.Print("|cffff4040Aura Glows could not be set up:|r " .. tostring(err))
    end
end
mod.RebuildAuraGlows = function()
    built = nil
    Rebuild()
end

local function ApplyPosition()
    if not holderFrame or InCombatLockdown() then
        return
    end
    local p = mod.AuraGlowSettings().pos
    holderFrame:ClearAllPoints()
    if p then
        holderFrame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        holderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(eventFrame.RegisterEvent, eventFrame, "ADDON_RESTRICTION_STATE_CHANGED")
local registered
eventFrame:SetScript("OnEvent", function(_, evt)
    if evt == "PLAYER_ENTERING_WORLD" then
        if not holderFrame then
            holderFrame = CreateFrame("Frame", "CludesUIRaidLeadAuraGlows", UIParent)
            holderFrame:SetSize(mod.AuraGlowSettings().size, mod.AuraGlowSettings().size)
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
                        return not mod.AuraGlowSettings().enabled
                    end,
                    getFrame = function()
                        return holderFrame
                    end,
                    getSize = function()
                        local s = mod.AuraGlowSettings()
                        local num = math.max(1, #s.spells)
                        return num * s.size + (num - 1) * GAP, s.size
                    end,
                    savePos = function(_, anchorPoint, relPoint, posX, posY)
                        mod.AuraGlowSettings().pos =
                            { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    end,
                    loadPos = function()
                        return mod.AuraGlowSettings().pos
                    end,
                    clearPos = function()
                        mod.AuraGlowSettings().pos = nil
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
