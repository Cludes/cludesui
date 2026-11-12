local addonName, ns = ...
if ns.standalone then return end
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
local K = ns.K

local EXT_DEFAULT_COUNT = 4
local EXT_MAX_COUNT     = 8
local EXT_DEFAULT_SIZE  = 36
local EXT_MIN_SIZE      = 16
local EXT_MAX_SIZE      = 64
local EXT_FILTER        = "HELPFUL|EXTERNAL_DEFENSIVE"
ns.EXT = { DEFAULT_COUNT = EXT_DEFAULT_COUNT, MAX_COUNT = EXT_MAX_COUNT,
           DEFAULT_SIZE = EXT_DEFAULT_SIZE, MIN_SIZE = EXT_MIN_SIZE, MAX_SIZE = EXT_MAX_SIZE }

local anchor            -- the row's frame; Layout Mode moves this
local container         -- the AuraContainer inside it
local rejected = false  -- the game refused the filter: do not retry

local function DB() return ns.DB() end

function ns.ExternalsEnabled()
    local v = DB().extEnabled
    return v == nil or v == true
end

local function Count() return ns.SettingNumber("extCount", EXT_DEFAULT_COUNT) end
local function Size()  return ns.SettingNumber("extSize",  EXT_DEFAULT_SIZE) end
local function Gap()   return ns.SettingNumber("extSpacing", K.DEBUFF_SPACING) end

--- True while the player's current spec is a tank spec.
function ns.PlayerIsTankSpec()
    local spec = GetSpecialization and GetSpecialization()
    if not spec then return false end
    return GetSpecializationRole(spec) == "TANK"
end

local function RowSize()
    local n = math.max(Count(), 1)
    return n * Size() + (n - 1) * Gap(), Size()
end

local function ApplyAnchorPosition()
    if not anchor or InCombatLockdown() then return end
    local p = DB().extPos
    anchor:ClearAllPoints()
    if p then
        anchor:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    else
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, -170)
    end
end

local function ApplyAnchorSize()
    if not anchor or InCombatLockdown() then return end
    anchor:SetSize(RowSize())
end

--- Builds the row. AuraContainers cannot be created in combat, so this runs
--- from the out-of-combat init and retries after combat.
function ns.CreateExternals()
    if anchor or rejected or InCombatLockdown() then return end
    if not ns.HasAuraContainers() then return end

    anchor = CreateFrame("Frame", "CludesUITankExternals", UIParent)
    anchor:SetFrameStrata("MEDIUM")
    ApplyAnchorSize()
    ApplyAnchorPosition()

    local ok, c = pcall(CreateFrame, "AuraContainer", nil, anchor,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    if not ok or not c then
        ok, c = pcall(CreateFrame, "AuraContainer", nil, anchor, "CustomAuraContainerTemplate")
    end
    if not ok or not c then return end
    c:SetSize(Size(), Size())
    c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    c:SetFlowLayoutAnchorPoint("TOPLEFT")
    c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    c:SetFlowLayoutPadding(0, 0, 0, 0)
    c:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)

    local addOk, err = pcall(c.AddAuraGroup, c, "externals", EXT_FILTER, {
        maxFrameCount   = math.max(Count(), 0),
        sortMethod      = AuraContainerSortMethod.Default,
        sortDirection   = AuraContainerSortDirection.Normal,
        initializeFrame = function(btn) ns.StyleAuraButton(btn, "external") end,
        layout = {
            elementSpacing = Gap(), lineSpacing = Gap(),
            elementWidth = Size(), elementHeight = Size(),
        },
    })
    if not addOk then
        c:Hide()
        rejected = true
        ns.Print("|cffff4040Externals on You could not be set up:|r " .. tostring(err))
        return
    end
    container = c
    ns.RefreshExternals()
end

--- Turns the row on or off and applies count, size and gap.
function ns.RefreshExternals()
    if not container then return end
    local live = ns.ExternalsEnabled() and Count() > 0 and ns.PlayerIsTankSpec()
        and not ns.IsInEditMode()
    pcall(container.SetAuraGroupMaxFrameCount, container, "externals", math.max(Count(), 0))
    pcall(container.SetAuraGroupLayout, container, "externals", {
        elementSpacing = Gap(), lineSpacing = Gap(),
        elementWidth = Size(), elementHeight = Size(),
    })
    if live then container:SetUnit("player") end
    container:SetEnabled(live)
    if not InCombatLockdown() then
        container:SetShown(live)
        ApplyAnchorSize()
    end
end

-------------------------------------------------------------------------------
--  Layout Mode
-------------------------------------------------------------------------------
local registered = false

local function RegisterLayoutMode()
    if registered or not (CludesUI and CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then return end
    local MK = CludesUI.MakeUnlockElement
    local frame = _G.CoTankAuras
    if not frame then return end
    registered = true

    local function Reposition(key)
        if CludesUI._unlockActive and CludesUI.RepositionBarToMover then CludesUI.RepositionBarToMover(key) end
    end

    CludesUI:RegisterUnlockElements({
        MK({
            key   = "TANK_CoTank",
            label = "Co-Tank",
            group = "Tank Kit",
            order = 650,
            getFrame = function() return frame end,
            getSize  = function()
                return ns.SettingNumber("frameWidth", K.DEFAULT_WIDTH), ns.SettingNumber("frameHeight", K.DEFAULT_HEIGHT)
            end,
            setWidth = function(_, w)
                w = math.max(K.MIN_WIDTH, math.min(K.MAX_WIDTH, math.floor(w + 0.5)))
                DB().frameWidth = w
                if not InCombatLockdown() then frame:SetWidth(w); frame:FitNameToWidth() end
                Reposition("TANK_CoTank")
            end,
            setHeight = function(_, h)
                h = math.max(K.MIN_HEIGHT, math.min(K.MAX_HEIGHT, math.floor(h + 0.5)))
                DB().frameHeight = h
                if not InCombatLockdown() then frame:SetHeight(h) end
                ns.RefreshAuraContainerLayout(frame)
                ns.RestyleAuraButtons()
                Reposition("TANK_CoTank")
            end,
            savePos = function(_, point, relPoint, x, y)
                local db = DB()
                db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
            end,
            loadPos = function()
                local db = DB()
                if db.point then return { point = db.point, relPoint = db.relPoint or db.point, x = db.x or 0, y = db.y or 0 } end
                return nil
            end,
            clearPos = function()
                local db = DB()
                db.point, db.relPoint, db.x, db.y = nil, nil, nil, nil
            end,
            applyPos = function() ns.ApplyPosition(frame) end,
        }),
        MK({
            key   = "TANK_Externals",
            label = "Externals on You",
            group = "Tank Kit",
            order = 651,
            noAnchorTarget = true,   -- its width follows the icon count
            isHidden = function() return not ns.ExternalsEnabled() or Count() == 0 end,
            getFrame = function()
                if not anchor then ns.CreateExternals() end
                return anchor
            end,
            getSize  = function() return RowSize() end,
            setWidth = function() end,
            setHeight = function(_, h)
                DB().extSize = math.max(EXT_MIN_SIZE, math.min(EXT_MAX_SIZE, math.floor(h + 0.5)))
                ns.RefreshExternals()
                Reposition("TANK_Externals")
            end,
            savePos = function(_, point, relPoint, x, y)
                DB().extPos = { point = point, relPoint = relPoint, x = x, y = y }
            end,
            loadPos = function() return DB().extPos end,
            clearPos = function() DB().extPos = nil end,
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
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
    if not InCombatLockdown() then
        ns.CreateExternals()
        RegisterLayoutMode()
    end
    ns.RefreshExternals()
end)
