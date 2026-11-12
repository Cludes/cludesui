local addonName, ns = ...
if ns.standalone then return end
-- Core.lua is loaded before this file (see TOC), so ns.K is available.
local K = ns.K

-- ══════════════════════════════════════════════════════════════════════════
--  Midnight 12.1 aura access
--
--  12.1 made unit aura data "secret" whenever combat, encounter, challenge
--  mode or PvP addon restrictions are in effect. Two things follow from that:
--
--    * Every enumeration API (GetAuraDataByIndex, GetUnitAuras,
--      GetUnitAuraInstanceIDs, GetAuraDataByAuraInstanceID, ...) carries the
--      RequiresUnitAuraAccess precondition, whose failure mode is a hard Lua
--      error - not a nil return. Calling one while tainted is what produced
--      "Auras cannot be accessed when secret while tainted by 'CoTankAuras'".
--
--    * The UNIT_AURA payload is fully secret, so info.isFullUpdate is a
--      secret boolean and testing it for truth is itself an error.
--
--  The sanctioned replacement is the AuraContainer/AuraButton frame types:
--  the addon supplies the regions, the engine fills and updates them, and the
--  addon never sees the aura data. That is what this module sets up.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Secret-value helpers ──────────────────────────────────────────────────
function ns.AurasAreSecret()
    return C_Secrets ~= nil
       and type(C_Secrets.ShouldAurasBeSecret) == "function"
       and C_Secrets.ShouldAurasBeSecret()
end

-- True when a value came back from the engine as a secret. Tainted code may
-- store and pass secrets, but comparing or doing arithmetic on one errors.
function ns.IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

-- A table can be flagged inaccessible to tainted code, in which case even
-- indexing it is an immediate Lua error. AuraData structs are fully secret
-- under restrictions, so check before reading fields off one.
function ns.CanRead(tbl)
    if type(tbl) ~= "table" then return false end
    if type(canaccesstable) == "function" then return canaccesstable(tbl) end
    return true
end

-- AuraContainer/AuraButton and their sort enum arrived together in 12.1, and
-- they live in Blizzard_AuraContainer, which is load-on-demand. Without this
-- the CreateFrame call below fails and the whole display silently never
-- appears, so load it before deciding whether the API is available.
function ns.HasAuraContainers()
    if C_AddOns and C_AddOns.LoadAddOn and C_AddOns.IsAddOnLoaded
       and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
    end
    return type(AuraContainerSortMethod) == "table"
       and type(AnchorUtil) == "table"
       and type(AnchorUtil.FlowDirection) == "table"
end

-- ── Shared button styling ─────────────────────────────────────────────────
-- Regions we created on each AuraButton, keyed by the button. Kept in the
-- addon's own table rather than on the Blizzard object, and populated from
-- initializeFrame so a later restyle can find every button without asking the
-- container for them.
local buttonRegions = setmetatable({}, {__mode = "k"})

local function StackPosition(posId)
    for _, p in ipairs(K.STACK_COUNT_POSITIONS) do
        if p.id == posId then return p end
    end
    return K.STACK_COUNT_POSITIONS[1]
end

-- Four edge textures around `parent`, used for the stack highlight on both the
-- live AuraButtons and the test-mode preview icons.
function ns.CreateEdges(parent, thickness)
    local edges = {}
    local function edge(point1, point2, width, height)
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetPoint(point1)
        t:SetPoint(point2)
        if width then t:SetWidth(width) end
        if height then t:SetHeight(height) end
        edges[#edges + 1] = t
    end
    edge("TOPLEFT",    "TOPRIGHT",    nil, thickness)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
    edge("TOPLEFT",    "BOTTOMLEFT",  thickness, nil)
    edge("TOPRIGHT",   "BOTTOMRIGHT", thickness, nil)
    return edges
end

function ns.ColorEdges(edges, r, g, b)
    for _, t in ipairs(edges) do t:SetColorTexture(r, g, b, 1) end
end

-- Stack count at which a debuff icon is highlighted, 0 when switched off.
function ns.StackHighlightAt()
    return math.max(math.floor(ns.SettingNumber("stackHighlightAt", K.STACK_HIGHLIGHT_DEFAULT)), 0)
end

-- The candidateFilters for the debuff row. A fresh table each call: the
-- engine keeps what it is given.
function ns.DebuffCandidateFilters()
    local id = ns.DB().debuffFilter
    local mode = K.DEBUFF_FILTER_MODES[1]
    for _, m in ipairs(K.DEBUFF_FILTER_MODES) do
        if m.id == id then mode = m; break end
    end
    local filters = {}
    for k, v in pairs(mode.filters) do filters[k] = v end
    return filters
end

-- Icon edge length for each group. Defensives sit inside the health bar, so
-- their size follows the configured frame height rather than the default one.
function ns.AuraIconSize(kind)
    if kind == "defensive" then
        local height = ns.SettingNumber("frameHeight", K.DEFAULT_HEIGHT)
        return math.max(height - K.POWER_BAR_HEIGHT - 16, 8)
    end
    return K.DEBUFF_ICON_SIZE
end

-- Applies every icon-appearance setting to one AuraButton. Safe to call at
-- creation and again whenever the settings change, but ONLY while auras are
-- non-secret: once they are secret the engine marks these buttons forbidden
-- and any call against them errors. Callers must check.
local function ApplyButtonSettings(btn)
    local regions = buttonRegions[btn]
    if not regions then return end

    -- Size is re-applied here rather than only at creation, so a frame height
    -- change resizes the defensive icons that already exist.
    local size = ns.AuraIconSize(regions.kind)
    btn:SetSize(size, size)

    local db        = ns.DB()
    local face      = ns.FontPath()
    local flags     = ns.FontFlags()
    local scale     = ns.SettingNumber("cdFontScale",    K.CD_FONT_SCALE_DEFAULT) / 10.0
    local stackSize = ns.SettingNumber("stackCountSize", K.STACK_COUNT_DEFAULT_SIZE)
    local timerSize = ns.SettingNumber("timerTextSize",  K.TIMER_TEXT_DEFAULT_SIZE)
    local nudgeX    = ns.SettingNumber("stackCountNudgeX", 0)
    local nudgeY    = ns.SettingNumber("stackCountNudgeY", 0)
    local cdAbove   = db.cdAbove or false

    if regions.cd.SetFontScale then regions.cd:SetFontScale(math.max(scale, 0.05)) end
    regions.cd:SetHideCountdownNumbers(cdAbove or scale <= 0)

    -- Stack count (size 0 hides it). Attaching and detaching has to happen
    -- here too, not just resizing: the count may not have existed when the
    -- button was built, and may need removing now.
    if stackSize > 0 then
        if not regions.count then
            regions.count = btn:CreateFontString(nil, "OVERLAY")
        end
        local pos = StackPosition(db.stackCountPos)
        regions.count:SetFont(face, stackSize, flags)
        regions.count:SetTextColor(ns.FontColor("stackCountColor"))
        regions.count:ClearAllPoints()
        regions.count:SetPoint(pos.point, btn, pos.rel or pos.point,
                               pos.px + nudgeX, pos.py + nudgeY)
        regions.count:Show()
        btn:SetApplicationCount(regions.count)
    elseif regions.count then
        btn:ClearApplicationCount()
        regions.count:SetText("")
        regions.count:Hide()
    end

    -- Stack highlight. An addon cannot read a stack count while auras are
    -- secret, but the engine will show a status bar only once the aura has
    -- minApplications stacks. The bar carries no fill of its own, just the
    -- border textures, so they appear at the threshold - in encounters too.
    -- It has to be a descendant of the button for the engine to accept it.
    local highlightAt = ns.StackHighlightAt()
    if highlightAt > 0 and regions.kind == "debuff" then
        if not regions.stackBar then
            regions.stackBar = CreateFrame("StatusBar", nil, btn)
            regions.stackBar:SetAllPoints(btn)
            regions.stackBar:SetFrameLevel(regions.cd:GetFrameLevel() + 1)
            regions.stackEdges = ns.CreateEdges(regions.stackBar, K.STACK_HIGHLIGHT_EDGE)
        end
        ns.ColorEdges(regions.stackEdges, ns.FontColor("stackHighlightColor"))
        btn:SetApplicationBar(regions.stackBar,
            {minApplications = highlightAt, maxApplications = highlightAt})
        regions.stackOn = true
    elseif regions.stackOn then
        btn:ClearApplicationBar()
        regions.stackBar:Hide()
        regions.stackOn = false
    end

    -- On-screen alert text, driven by the same engine test. The text is a
    -- region of the stack bar, so it is visible exactly while this debuff is
    -- at or over the threshold, but it is anchored to the alert frame in the
    -- middle of the screen rather than to the icon.
    if regions.stackOn and db.stackBanner then
        if not regions.banner then
            regions.banner = regions.stackBar:CreateFontString(nil, "OVERLAY")
            regions.banner:SetPoint("CENTER", ns.Alert:Anchor(), "CENTER", 0, 0)
            regions.banner:SetTextColor(1, 0.3, 0.3)
        end
        regions.banner:SetFont(face, ns.SettingNumber("alertTextSize", 22), flags)
        regions.banner:SetText(ns.Alert:BannerText())
        regions.banner:Show()
    elseif regions.banner then
        regions.banner:Hide()
    end

    -- Border coloured by debuff type. The engine tints and shows the texture
    -- for magic, curse, disease, poison and bleed effects and hides it for
    -- anything else, which leaves the plain dark edge underneath.
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if regions.kind == "debuff" and db.debuffTypeBorders and styles then
        if not regions.typeBorder then
            regions.typeBorder = btn:CreateTexture(nil, "BORDER")
            regions.typeBorder:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -1,  1)
            regions.typeBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  1, -1)
            regions.typeBorder:SetColorTexture(1, 1, 1, 1)
        end
        if not regions.typeOn then
            btn:AddDispelTypeTexture(regions.typeBorder, {style = styles.PreserveAsset})
            regions.typeOn = true
        end
    elseif regions.typeOn then
        btn:RemoveDispelTypeTexture(regions.typeBorder)
        regions.typeBorder:Hide()
        regions.typeOn = false
    end

    btn:SetHideTooltipInCombat(db.hideTooltipsInCombat and true or false)

    -- Above-icon timer. The engine formats and colours this, which is what
    -- replaces the old per-frame OnUpdate that read expirationTime.
    if cdAbove then
        if not regions.timer then
            regions.timer = btn:CreateFontString(nil, "OVERLAY")
        end
        regions.timer:SetFont(face, math.max(timerSize, 1), flags)
        regions.timer:SetTextColor(ns.FontColor("timerTextColor"))
        regions.timer:ClearAllPoints()
        regions.timer:SetPoint("BOTTOM", btn, "TOP", 0, 2)
        regions.timer:Show()
        btn:SetDurationText(regions.timer)
    elseif regions.timer then
        btn:ClearDurationText()
        regions.timer:SetText("")
        regions.timer:Hide()
    end
end

-- Runs inside the container's initializeFrame callback, once per button.
local function StyleAuraButton(btn, kind)
    local regions = {kind = kind}
    buttonRegions[btn] = regions

    -- 1px dark edge: a texture filling the button, with the icon inset on
    -- top of it. This used to come from BackdropTemplate, but an AuraButton's
    -- OnLoad is forbidden, so any template that sets one logged "Cannot
    -- assign script handler for 'onload'" for every button the engine built.
    regions.border = btn:CreateTexture(nil, "BACKGROUND")
    regions.border:SetAllPoints(btn)
    regions.border:SetColorTexture(0, 0, 0, 0.7)

    -- Icon, with the same 8% TexCoord trim the old icon frames used to drop
    -- Blizzard's built-in border padding.
    regions.icon = btn:CreateTexture(nil, "ARTWORK")
    regions.icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",      1, -1)
    regions.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1,  1)
    regions.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn:SetIcon(regions.icon)

    -- Cooldown sweep. The engine drives this; SetDurationCooldown adds the
    -- Cooldown secret aspect so it can be fed secret expiration times.
    regions.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    regions.cd:SetAllPoints(regions.icon)
    regions.cd:SetReverse(true)
    btn:SetDurationCooldown(regions.cd)

    ApplyButtonSettings(btn)
end

-- ── Container construction ────────────────────────────────────────────────
-- AuraContainers cannot be created in combat, so this only runs from the
-- addon's out-of-combat init path.
local function CreateContainer(parent, iconSize, growHorizontal)
    -- DisableUntrustedLayoutScriptsTemplate opts the container into the same
    -- forbidden layout aspect AddAuraGroup applies anyway, so its own resizing
    -- does not fight anything anchored around it.
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, parent,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    if not ok or not container then
        -- Fall back to the bare template in case the layout template is absent.
        ok, container = pcall(CreateFrame, "AuraContainer", nil, parent,
            "CustomAuraContainerTemplate")
    end
    if not ok or not container then return nil end

    container:SetSize(iconSize, iconSize)
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    container:SetFlowLayoutAnchorPoint("TOPRIGHT")
    container:SetFlowLayoutGrowthDirection(growHorizontal, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutPadding(0, 0, 0, 0)
    return container
end

-- AddAuraGroup refusing its options is not something a retry can fix, and the
-- roster handler in Core.lua retries creation on every group event. Without
-- this each of those events built and abandoned another container.
local function GroupRejected(frame, key, err)
    frame[key] = true
    ns.Print("|cffff4040Could not set up the " .. key:gsub("Rejected", "") ..
             " icons:|r " .. tostring(err))
end

function ns.CreateDebuffAuraContainer(frame)
    if InCombatLockdown() or frame.debuffContainer or frame.debuffRejected then return end
    if not ns.HasAuraContainers() then return end

    local iconSize = ns.AuraIconSize("debuff")
    local spacing  = ns.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)

    local container = CreateContainer(frame, iconSize, AnchorUtil.FlowDirection.Left)
    if not container then return end
    container:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    -- With the default "all debuffs" setting no candidate filter is passed at
    -- all, which is exactly what earlier versions did.
    local filters = ns.DebuffCandidateFilters()
    local addOk, addErr = pcall(container.AddAuraGroup, container, "debuffs", K.DEBUFF_AURA_FILTER, {
        maxFrameCount   = math.max(ns.SettingNumber("maxDebuffs", K.DEBUFF_DEFAULT_COUNT), 0),
        sortMethod      = AuraContainerSortMethod.UnitFrameDebuff,
        sortDirection   = AuraContainerSortDirection.Normal,
        candidateFilters = next(filters) and filters or nil,
        initializeFrame = function(btn) StyleAuraButton(btn, "debuff") end,
        layout = {
            elementSpacing = spacing,
            lineSpacing    = spacing,
            elementWidth   = iconSize,
            elementHeight  = iconSize,
        },
    })
    if not addOk then
        container:Hide()
        GroupRejected(frame, "debuffRejected", addErr)
        return
    end

    frame.debuffContainer = container
    ns.RefreshDebuffContainer(frame)
end

function ns.CreateDefensiveAuraContainer(frame)
    if InCombatLockdown() or frame.defensiveContainer or frame.defensiveRejected then return end
    if not ns.HasAuraContainers() then return end

    local iconSize = ns.AuraIconSize("defensive")
    local spacing  = K.DEBUFF_SPACING

    local container = CreateContainer(frame, iconSize, AnchorUtil.FlowDirection.Left)
    if not container then return end
    container:SetPoint("TOPRIGHT", frame.health, "RIGHT", -K.DEBUFF_SPACING, iconSize / 2 - 2)

    local addOk, addErr = pcall(container.AddAuraGroup, container, "defensives", K.BIG_DEFENSIVE_AURA_FILTER, {
        maxFrameCount   = math.max(ns.SettingNumber("maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT), 0),
        sortMethod      = AuraContainerSortMethod.BigDefensive,
        sortDirection   = AuraContainerSortDirection.Normal,
        initializeFrame = function(btn) StyleAuraButton(btn, "defensive") end,
        layout = {
            elementSpacing = spacing,
            lineSpacing    = spacing,
            elementWidth   = iconSize,
            elementHeight  = iconSize,
        },
    })
    if not addOk then
        container:Hide()
        GroupRejected(frame, "defensiveRejected", addErr)
        return
    end

    frame.defensiveContainer = container
    ns.RefreshDefensiveContainer(frame)
end

-- ── One-time migration off the legacy private-aura row ────────────────────
-- An AuraContainer draws private auras alongside public ones (its aura source
-- list is PublicAndPrivate), and in Midnight most encounter tank debuffs are
-- private auras. So once the debuff container is running, the separate
-- AddPrivateAuraAnchor row shows the same icons a second time.
--
-- Turn that row off once, explain why, and leave the setting in place so it
-- can be turned back on from the options panel by anyone who wants it.
function ns.MigratePrivateAuraRow()
    local db = ns.DB()
    if db.auraContainerMigrated then return end
    if not (CoTankAuras and CoTankAuras.debuffContainer) then return end

    db.auraContainerMigrated = true
    local previous = ns.SettingNumber("maxPrivateAuras", K.PRIVATE_AURAS_DEFAULT_COUNT)
    if previous <= 0 then return end

    db.maxPrivateAuras = 0
    if CoTankAuras.UpdateAndRefreshAuraLayout then
        CoTankAuras:UpdateAndRefreshAuraLayout(0)
    end
    ns.Print("Private auras now appear in the tank debuff row, so the separate " ..
             "private aura row has been turned off to stop icons showing twice. " ..
             "Turn it back on under |cffffff00/ctank|r > Frame if you prefer the old layout.")
end

-- ── Tank debuff toggle ────────────────────────────────────────────────────
function ns.DebuffsEnabled()
    local db = ns.DB()
    if db.debuffsEnabled == nil then db.debuffsEnabled = true end
    return db.debuffsEnabled ~= false
end

-- ── Runtime updates ───────────────────────────────────────────────────────
-- A container is live only while it is both enabled and visible. Test mode
-- takes the display over with mock icons, so the container stands down then.
local function ApplyContainerState(container, groupKey, unit, maxCount, enabled)
    if not container then return end

    local live = enabled
             and maxCount > 0
             and unit ~= nil
             and not ns.isTestMode
             and not ns.IsInEditMode()

    if live then
        container:SetUnit(unit)
    end
    pcall(container.SetAuraGroupMaxFrameCount, container, groupKey, math.max(maxCount, 0))
    container:SetEnabled(live)
    if not InCombatLockdown() then
        container:SetShown(live)
    end
end

function ns.RefreshDebuffContainer(frame)
    frame = frame or CoTankAuras
    if not frame or not frame.debuffContainer then return end
    ApplyContainerState(frame.debuffContainer, "debuffs",
        frame:GetAttribute("unit"),
        ns.SettingNumber("maxDebuffs", K.DEBUFF_DEFAULT_COUNT),
        ns.DebuffsEnabled())
end

function ns.RefreshDefensiveContainer(frame)
    frame = frame or CoTankAuras
    if not frame or not frame.defensiveContainer then return end
    ApplyContainerState(frame.defensiveContainer, "defensives",
        frame:GetAttribute("unit"),
        ns.SettingNumber("maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT),
        true)
end

-- Applies the debuff filter setting to the live container. This is a
-- container-level call, so it does not touch the (possibly forbidden) buttons.
function ns.RefreshDebuffFilter(frame)
    frame = frame or CoTankAuras
    if not frame or not frame.debuffContainer then return end
    pcall(frame.debuffContainer.SetAuraGroupCandidateFilters, frame.debuffContainer,
          "debuffs", ns.DebuffCandidateFilters())
end

function ns.RefreshAuraContainers(frame)
    ns.RefreshDebuffContainer(frame)
    ns.RefreshDefensiveContainer(frame)
end

function ns.SetDebuffsEnabled(enabled)
    ns.DB().debuffsEnabled = enabled and true or false
    if CoTankAuras then
        ns.RefreshDebuffContainer(CoTankAuras)
        CoTankAuras:RefreshDebuffLayout()
        if ns.isTestMode then
            if enabled then CoTankAuras:ShowMockDebuffs() else CoTankAuras:ClearDebuffs() end
        end
    end
    if ns.Options and ns.Options.SyncTestButton then ns.Options:SyncTestButton() end
    return ns.DebuffsEnabled()
end

function ns.ToggleDebuffs()
    return ns.SetDebuffsEnabled(not ns.DebuffsEnabled())
end

-- ── Restyling after an options change ─────────────────────────────────────
-- Buttons the engine has already created keep the size and regions they were
-- given in initializeFrame. They can only be touched again while auras are
-- non-secret; in combat/encounters they are forbidden and any call errors.
local pendingRestyle = false

-- Replays a restyle that was blocked by secrecy. Called from the
-- PLAYER_REGEN_ENABLED handler in Core.lua.
function ns.FlushPendingRestyle()
    if not pendingRestyle then return end
    if ns.AurasAreSecret() then return end
    pendingRestyle = false
    ns.RestyleAuraButtons()
end

function ns.RestyleAuraButtons()
    -- Buttons are forbidden while auras are secret, so remember that a
    -- restyle is owed rather than dropping the settings change entirely.
    if InCombatLockdown() or ns.AurasAreSecret() then
        pendingRestyle = true
        return
    end

    -- Every button the engine has created for us passed through
    -- initializeFrame, so this covers them all without having to ask the
    -- container to hand them back.
    for btn in pairs(buttonRegions) do
        pcall(ApplyButtonSettings, btn)
    end
end

-- Layout is a container-level property, so it applies without touching the
-- individual (possibly forbidden) buttons.
function ns.RefreshAuraContainerLayout(frame)
    frame = frame or CoTankAuras
    if not frame then return end

    if frame.debuffContainer then
        local spacing  = ns.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)
        local iconSize = ns.AuraIconSize("debuff")
        pcall(frame.debuffContainer.SetAuraGroupLayout, frame.debuffContainer, "debuffs", {
            elementSpacing = spacing,
            lineSpacing    = spacing,
            elementWidth   = iconSize,
            elementHeight  = iconSize,
        })
    end

    if frame.defensiveContainer then
        local iconSize = ns.AuraIconSize("defensive")
        pcall(frame.defensiveContainer.SetAuraGroupLayout, frame.defensiveContainer, "defensives", {
            elementSpacing = K.DEBUFF_SPACING,
            lineSpacing    = K.DEBUFF_SPACING,
            elementWidth   = iconSize,
            elementHeight  = iconSize,
        })
        -- Re-centre the row on the health bar at the new icon size.
        if not InCombatLockdown() and frame.health then
            frame.defensiveContainer:ClearAllPoints()
            frame.defensiveContainer:SetPoint("TOPRIGHT", frame.health, "RIGHT",
                -K.DEBUFF_SPACING, iconSize / 2 - 2)
        end
    end
end
