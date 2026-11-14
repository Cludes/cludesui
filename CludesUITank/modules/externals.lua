local addonName, mod = ...
if mod.standalone then
    return
end
-------------------------------------------------------------------------------
--  externals.lua -- Tank Kit: "Externals on You" and the Layout Mode movers.
--
--  Externals on You is a row of the big external defensives other players
--  have put on you (Pain Suppression, Ironbark, Blessing of Sacrifice ...).
--  The game's own EXTERNAL_DEFENSIVE aura filter picks them, inside an
--  AuraContainer, so the row keeps working while auras are secret in combat,
--  in encounters and in keys. It shows only while you are in a tank spec.
--
--  Both the co-tank frame and this row are placed with CludesUI Layout Mode.
-------------------------------------------------------------------------------
local Keys = mod.K

local EXT_DEFAULT_COUNT = 4
local EXT_MAX_COUNT = 8
local EXT_DEFAULT_SIZE = 36
local EXT_MIN_SIZE = 16
local EXT_MAX_SIZE = 64
local EXT_FILTER = "HELPFUL|EXTERNAL_DEFENSIVE"
mod.EXT = {
    DEFAULT_COUNT = EXT_DEFAULT_COUNT,
    MAX_COUNT = EXT_MAX_COUNT,
    DEFAULT_SIZE = EXT_DEFAULT_SIZE,
    MIN_SIZE = EXT_MIN_SIZE,
    MAX_SIZE = EXT_MAX_SIZE,
}

local anchorFrame -- the row's frame; Layout Mode moves this
local boxHolder -- the AuraContainer inside it
local rejected = false -- the game refused the filter: do not retry

local function SavedDB()
    return mod.DB()
end

function mod.ExternalsEnabled()
    local val = SavedDB().extEnabled
    return val == nil or val == true
end

local function Count()
    return mod.SettingNumber("extCount", EXT_DEFAULT_COUNT)
end
local function Size()
    return mod.SettingNumber("extSize", EXT_DEFAULT_SIZE)
end
local function Gap()
    return mod.SettingNumber("extSpacing", Keys.DEBUFF_SPACING)
end

--- True while the player's current spec is a tank spec.
function mod.PlayerIsTankSpec()
    local specInfo = GetSpecialization and GetSpecialization()
    if not specInfo then
        return false
    end
    return GetSpecializationRole(specInfo) == "TANK"
end

local function RowSize()
    local num = math.max(Count(), 1)
    return num * Size() + (num - 1) * Gap(), Size()
end

local function ApplyAnchorPosition()
    if not anchorFrame or InCombatLockdown() then
        return
    end
    local p = SavedDB().extPos
    anchorFrame:ClearAllPoints()
    if p then
        anchorFrame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    end
end

local function ApplyAnchorSize()
    if not anchorFrame or InCombatLockdown() then
        return
    end
    anchorFrame:SetSize(RowSize())
end

--- Builds the row. AuraContainers cannot be created in combat, so this runs
--- from the out-of-combat init and retries after combat.
function mod.CreateExternals()
    if anchorFrame or rejected or InCombatLockdown() then
        return
    end
    if not mod.HasAuraContainers() then
        return
    end

    anchorFrame = CreateFrame("Frame", "CludesUITankExternals", UIParent)
    anchorFrame:SetFrameStrata("MEDIUM")
    ApplyAnchorSize()
    ApplyAnchorPosition()

    local success, c = pcall(
        CreateFrame,
        "AuraContainer",
        nil,
        anchorFrame,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"
    )
    if not success or not c then
        success, c = pcall(CreateFrame, "AuraContainer", nil, anchorFrame, "CustomAuraContainerTemplate")
    end
    if not success or not c then
        return
    end
    c:SetSize(Size(), Size())
    c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    c:SetFlowLayoutAnchorPoint("TOPLEFT")
    c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    c:SetFlowLayoutPadding(0, 0, 0, 0)
    c:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)

    local addOk, err = pcall(c.AddAuraGroup, c, "externals", EXT_FILTER, {
        maxFrameCount = math.max(Count(), 0),
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = function(button)
            mod.StyleAuraButton(button, "external")
        end,
        layout = {
            elementSpacing = Gap(),
            lineSpacing = Gap(),
            elementWidth = Size(),
            elementHeight = Size(),
        },
    })
    if not addOk then
        c:Hide()
        rejected = true
        mod.Print("|cffff4040Externals on You could not be set up:|r " .. tostring(err))
        return
    end
    boxHolder = c
    mod.RefreshExternals()
end

--- Turns the row on or off and applies count, size and gap.
function mod.RefreshExternals()
    if not boxHolder then
        return
    end
    local live = mod.ExternalsEnabled() and Count() > 0 and mod.PlayerIsTankSpec() and not mod.IsInEditMode()
    pcall(boxHolder.SetAuraGroupMaxFrameCount, boxHolder, "externals", math.max(Count(), 0))
    pcall(boxHolder.SetAuraGroupLayout, boxHolder, "externals", {
        elementSpacing = Gap(),
        lineSpacing = Gap(),
        elementWidth = Size(),
        elementHeight = Size(),
    })
    if live then
        boxHolder:SetUnit("player")
    end
    boxHolder:SetEnabled(live)
    if not InCombatLockdown() then
        boxHolder:SetShown(live)
        ApplyAnchorSize()
    end
end

-------------------------------------------------------------------------------
--  Layout Mode
-------------------------------------------------------------------------------
local registered = false

local function RegisterLayoutMode()
    if registered or not (CludesUI and CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then
        return
    end
    local MK = CludesUI.MakeUnlockElement
    local widget = _G.CoTankAuras
    if not widget then
        return
    end
    registered = true

    local function Reposition(key)
        if CludesUI._unlockActive and CludesUI.RepositionBarToMover then
            CludesUI.RepositionBarToMover(key)
        end
    end

    CludesUI:RegisterUnlockElements({
        MK({
            key = "TANK_CoTank",
            label = "Co-Tank",
            group = "Tank Kit",
            order = 650,
            getFrame = function()
                return widget
            end,
            getSize = function()
                return mod.SettingNumber("frameWidth", Keys.DEFAULT_WIDTH),
                    mod.SettingNumber("frameHeight", Keys.DEFAULT_HEIGHT)
            end,
            setWidth = function(_, wid)
                wid = math.max(Keys.MIN_WIDTH, math.min(Keys.MAX_WIDTH, math.floor(wid + 0.5)))
                SavedDB().frameWidth = wid
                if not InCombatLockdown() then
                    widget:SetWidth(wid)
                    widget:FitNameToWidth()
                end
                Reposition("TANK_CoTank")
            end,
            setHeight = function(_, hgt)
                hgt = math.max(Keys.MIN_HEIGHT, math.min(Keys.MAX_HEIGHT, math.floor(hgt + 0.5)))
                SavedDB().frameHeight = hgt
                if not InCombatLockdown() then
                    widget:SetHeight(hgt)
                end
                mod.RefreshAuraContainerLayout(widget)
                mod.RestyleAuraButtons()
                Reposition("TANK_CoTank")
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                local saved = SavedDB()
                saved.point, saved.relPoint, saved.x, saved.y = anchorPoint, relPoint, posX, posY
            end,
            loadPos = function()
                local saved = SavedDB()
                if saved.point then
                    return {
                        point = saved.point,
                        relPoint = saved.relPoint or saved.point,
                        x = saved.x or 0,
                        y = saved.y or 0,
                    }
                end
                return nil
            end,
            clearPos = function()
                local saved = SavedDB()
                saved.point, saved.relPoint, saved.x, saved.y = nil, nil, nil, nil
            end,
            applyPos = function()
                mod.ApplyPosition(widget)
            end,
        }),
        MK({
            key = "TANK_Externals",
            label = "Externals on You",
            group = "Tank Kit",
            order = 651,
            noAnchorTarget = true, -- its width follows the icon count
            isHidden = function()
                return not mod.ExternalsEnabled() or Count() == 0
            end,
            getFrame = function()
                if not anchorFrame then
                    mod.CreateExternals()
                end
                return anchorFrame
            end,
            getSize = function()
                return RowSize()
            end,
            setWidth = function() end,
            setHeight = function(_, hgt)
                SavedDB().extSize = math.max(EXT_MIN_SIZE, math.min(EXT_MAX_SIZE, math.floor(hgt + 0.5)))
                mod.RefreshExternals()
                Reposition("TANK_Externals")
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                SavedDB().extPos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
            end,
            loadPos = function()
                return SavedDB().extPos
            end,
            clearPos = function()
                SavedDB().extPos = nil
            end,
            applyPos = ApplyAnchorPosition,
        }),
    }, addonName)
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, evt, unitToken)
    if evt == "PLAYER_SPECIALIZATION_CHANGED" and unitToken and unitToken ~= "player" then
        return
    end
    if not InCombatLockdown() then
        mod.CreateExternals()
        RegisterLayoutMode()
    end
    mod.RefreshExternals()
end)
