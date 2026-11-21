local addonName, mod = ...
if mod.standalone then return end
-- Core.lua is loaded before this file (see TOC), so ns.K is available.
local K = mod.K

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
function mod.AurasAreSecret()
    return C_Secrets ~= nil
        and type(C_Secrets.ShouldAurasBeSecret) == "function"
        and C_Secrets.ShouldAurasBeSecret()
end

-- True when a value came back from the engine as a secret. Tainted code may
-- store and pass secrets, but comparing or doing arithmetic on one errors.
function mod.IsSecret(value) return type(issecretvalue) == "function" and issecretvalue(value) end

-- A table can be flagged inaccessible to tainted code, in which case even
-- indexing it is an immediate Lua error. AuraData structs are fully secret
-- under restrictions, so check before reading fields off one.
function mod.CanRead(tbl)
    if type(tbl) ~= "table" then return false end
    if type(canaccesstable) == "function" then return canaccesstable(tbl) end
    return true
end

-- AuraContainer/AuraButton and their sort enum arrived together in 12.1, and
-- they live in Blizzard_AuraContainer, which is load-on-demand. Without this
-- the CreateFrame call below fails and the whole display silently never
-- appears, so load it before deciding whether the API is available.
function mod.HasAuraContainers()
    if
        C_AddOns
        and C_AddOns.LoadAddOn
        and C_AddOns.IsAddOnLoaded
        and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer")
    then
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
local buttonRegions = setmetatable({}, { __mode = "k" })

local function StackPosition(posId)
    for _, p in ipairs(K.STACK_COUNT_POSITIONS) do
        if p.id == posId then return p end
    end
    return K.STACK_COUNT_POSITIONS[1]
end

-- Four edge textures around `parent`, used for the stack highlight on both the
-- live AuraButtons and the test-mode preview icons.
function mod.CreateEdges(hostFrame, thickness)
    local edges = {}
    local function edge(point1, point2, width, height)
        local tex = hostFrame:CreateTexture(nil, "OVERLAY")
        tex:SetPoint(point1)
        tex:SetPoint(point2)
        if width then tex:SetWidth(width) end
        if height then tex:SetHeight(height) end
        edges[#edges + 1] = tex
    end
    edge("TOPLEFT", "TOPRIGHT", nil, thickness)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, thickness)
    edge("TOPLEFT", "BOTTOMLEFT", thickness, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", thickness, nil)
    return edges
end

function mod.ColorEdges(edges, red, green, blue)
    for _, t in ipairs(edges) do
        t:SetColorTexture(red, green, blue, 1)
    end
end

-- Stack count at which a debuff icon is highlighted, 0 when switched off.
function mod.StackHighlightAt()
    return math.max(math.floor(mod.SettingNumber("stackHighlightAt", K.STACK_HIGHLIGHT_DEFAULT)), 0)
end

-- The candidateFilters for the debuff row. A fresh table each call: the
-- engine keeps what it is given.
function mod.DebuffCandidateFilters()
    local ident = mod.DB().debuffFilter
    local mode = K.DEBUFF_FILTER_MODES[1]
    for _, m in ipairs(K.DEBUFF_FILTER_MODES) do
        if m.id == ident then
            mode = m
            break
        end
    end
    local filters = {}
    for key, val in pairs(mode.filters) do
        filters[key] = val
    end
    return filters
end

-- Icon edge length for each group. Defensives sit inside the health bar, so
-- their size follows the configured frame height rather than the default one.
function mod.AuraIconSize(kind)
    if kind == "external" then return mod.SettingNumber("extSize", mod.EXT and mod.EXT.DEFAULT_SIZE or 36) end
    if kind == "defensive" then
        local height = mod.SettingNumber("frameHeight", K.DEFAULT_HEIGHT)
        return math.max(height - K.POWER_BAR_HEIGHT - 16, 8)
    end
    return K.DEBUFF_ICON_SIZE
end

-- Applies every icon-appearance setting to one AuraButton. Safe to call at
-- creation and again whenever the settings change, but ONLY while auras are
-- non-secret: once they are secret the engine marks these buttons forbidden
-- and any call against them errors. Callers must check.
local function ApplyButtonSettings(button)
    local regions = buttonRegions[button]
    if not regions then return end

    -- Size is re-applied here rather than only at creation, so a frame height
    -- change resizes the defensive icons that already exist.
    local size = mod.AuraIconSize(regions.kind)
    button:SetSize(size, size)

    local saved = mod.DB()
    local face = mod.FontPath()
    local flags = mod.FontFlags()
    local scale = mod.SettingNumber("cdFontScale", K.CD_FONT_SCALE_DEFAULT) / 10.0
    local stackSize = mod.SettingNumber("stackCountSize", K.STACK_COUNT_DEFAULT_SIZE)
    local timerSize = mod.SettingNumber("timerTextSize", K.TIMER_TEXT_DEFAULT_SIZE)
    local nudgeX = mod.SettingNumber("stackCountNudgeX", 0)
    local nudgeY = mod.SettingNumber("stackCountNudgeY", 0)
    local cdAbove = saved.cdAbove or false

    if regions.cd.SetFontScale then regions.cd:SetFontScale(math.max(scale, 0.05)) end
    regions.cd:SetHideCountdownNumbers(cdAbove or scale <= 0)

    -- Stack count (size 0 hides it). Attaching and detaching has to happen
    -- here too, not just resizing: the count may not have existed when the
    -- button was built, and may need removing now.
    if stackSize > 0 then
        if not regions.count then regions.count = button:CreateFontString(nil, "OVERLAY") end
        local place = StackPosition(saved.stackCountPos)
        regions.count:SetFont(face, stackSize, flags)
        regions.count:SetTextColor(mod.FontColor("stackCountColor"))
        regions.count:ClearAllPoints()
        regions.count:SetPoint(
            place.point,
            button,
            place.rel or place.point,
            place.px + nudgeX,
            place.py + nudgeY
        )
        regions.count:Show()
        button:SetApplicationCount(regions.count)
    elseif regions.count then
        button:ClearApplicationCount()
        regions.count:SetText("")
        regions.count:Hide()
    end

    -- Stack highlight. An addon cannot read a stack count while auras are
    -- secret, but the engine will show a status bar only once the aura has
    -- minApplications stacks. The bar carries no fill of its own, just the
    -- border textures, so they appear at the threshold - in encounters too.
    -- It has to be a descendant of the button for the engine to accept it.
    local highlightAt = mod.StackHighlightAt()
    if highlightAt > 0 and regions.kind == "debuff" then
        if not regions.stackBar then
            regions.stackBar = CreateFrame("StatusBar", nil, button)
            regions.stackBar:SetAllPoints(button)
            regions.stackBar:SetFrameLevel(regions.cd:GetFrameLevel() + 1)
            regions.stackEdges = mod.CreateEdges(regions.stackBar, K.STACK_HIGHLIGHT_EDGE)
        end
        mod.ColorEdges(regions.stackEdges, mod.FontColor("stackHighlightColor"))
        button:SetApplicationBar(
            regions.stackBar,
            { minApplications = highlightAt, maxApplications = highlightAt }
        )
        regions.stackOn = true
    elseif regions.stackOn then
        button:ClearApplicationBar()
        regions.stackBar:Hide()
        regions.stackOn = false
    end

    -- On-screen alert text, driven by the same engine test. The text is a
    -- region of the stack bar, so it is visible exactly while this debuff is
    -- at or over the threshold, but it is anchored to the alert frame in the
    -- middle of the screen rather than to the icon.
    if regions.stackOn and saved.stackBanner then
        if not regions.banner then
            regions.banner = regions.stackBar:CreateFontString(nil, "OVERLAY")
            regions.banner:SetPoint("CENTER", mod.Alert:Anchor(), "CENTER", 0, 0)
            regions.banner:SetTextColor(1, 0.3, 0.3)
        end
        regions.banner:SetFont(face, mod.SettingNumber("alertTextSize", 22), flags)
        regions.banner:SetText(mod.Alert:BannerText())
        regions.banner:Show()
    elseif regions.banner then
        regions.banner:Hide()
    end

    -- Border coloured by debuff type. The engine tints and shows the texture
    -- for magic, curse, disease, poison and bleed effects and hides it for
    -- anything else, which leaves the plain dark edge underneath.
    local styles = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
    if regions.kind == "debuff" and saved.debuffTypeBorders and styles then
        if not regions.typeBorder then
            regions.typeBorder = button:CreateTexture(nil, "BORDER")
            regions.typeBorder:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
            regions.typeBorder:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 1, -1)
            regions.typeBorder:SetColorTexture(1, 1, 1, 1)
        end
        if not regions.typeOn then
            button:AddDispelTypeTexture(regions.typeBorder, { style = styles.PreserveAsset })
            regions.typeOn = true
        end
    elseif regions.typeOn then
        button:RemoveDispelTypeTexture(regions.typeBorder)
        regions.typeBorder:Hide()
        regions.typeOn = false
    end

    button:SetHideTooltipInCombat(saved.hideTooltipsInCombat and true or false)

    -- Above-icon timer. The engine formats and colours this, which is what
    -- replaces the old per-frame OnUpdate that read expirationTime.
    if cdAbove then
        if not regions.timer then regions.timer = button:CreateFontString(nil, "OVERLAY") end
        regions.timer:SetFont(face, math.max(timerSize, 1), flags)
        regions.timer:SetTextColor(mod.FontColor("timerTextColor"))
        regions.timer:ClearAllPoints()
        regions.timer:SetPoint("BOTTOM", button, "TOP", 0, 2)
        regions.timer:Show()
        button:SetDurationText(regions.timer)
    elseif regions.timer then
        button:ClearDurationText()
        regions.timer:SetText("")
        regions.timer:Hide()
    end
end

-- Runs inside the container's initializeFrame callback, once per button.
local function StyleAuraButton(button, kind)
    local regions = { kind = kind }
    buttonRegions[button] = regions

    -- 1px dark edge: a texture filling the button, with the icon inset on
    -- top of it. This used to come from BackdropTemplate, but an AuraButton's
    -- OnLoad is forbidden, so any template that sets one logged "Cannot
    -- assign script handler for 'onload'" for every button the engine built.
    regions.border = button:CreateTexture(nil, "BACKGROUND")
    regions.border:SetAllPoints(button)
    regions.border:SetColorTexture(0, 0, 0, 0.7)

    -- Icon, with the same 8% TexCoord trim the old icon frames used to drop
    -- Blizzard's built-in border padding.
    regions.icon = button:CreateTexture(nil, "ARTWORK")
    regions.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    regions.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    regions.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(regions.icon)

    -- Cooldown sweep. The engine drives this; SetDurationCooldown adds the
    -- Cooldown secret aspect so it can be fed secret expiration times.
    regions.cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    regions.cd:SetAllPoints(regions.icon)
    regions.cd:SetReverse(true)
    button:SetDurationCooldown(regions.cd)

    ApplyButtonSettings(button)
end

mod.StyleAuraButton = StyleAuraButton

-- ── Container construction ────────────────────────────────────────────────
-- AuraContainers cannot be created in combat, so this only runs from the
-- addon's out-of-combat init path.
local function CreateContainer(hostFrame, iconSize, growHorizontal)
    -- DisableUntrustedLayoutScriptsTemplate opts the container into the same
    -- forbidden layout aspect AddAuraGroup applies anyway, so its own resizing
    -- does not fight anything anchored around it.
    local success, boxHolder = pcall(
        CreateFrame,
        "AuraContainer",
        nil,
        hostFrame,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"
    )
    if not success or not boxHolder then
        -- Fall back to the bare template in case the layout template is absent.
        success, boxHolder =
            pcall(CreateFrame, "AuraContainer", nil, hostFrame, "CustomAuraContainerTemplate")
    end
    if not success or not boxHolder then return nil end

    boxHolder:SetSize(iconSize, iconSize)
    boxHolder:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
    boxHolder:SetFlowLayoutAnchorPoint("TOPRIGHT")
    boxHolder:SetFlowLayoutGrowthDirection(growHorizontal, AnchorUtil.FlowDirection.Down)
    boxHolder:SetFlowLayoutPadding(0, 0, 0, 0)
    return boxHolder
end

-- AddAuraGroup refusing its options is not something a retry can fix, and the
-- roster handler in Core.lua retries creation on every group event. Without
-- this each of those events built and abandoned another container.
local function GroupRejected(widget, key, err)
    widget[key] = true
    mod.Print("|cffff4040Could not set up the " .. key:gsub("Rejected", "") .. " icons:|r " .. tostring(err))
end

function mod.CreateDebuffAuraContainer(widget)
    if InCombatLockdown() or widget.debuffContainer or widget.debuffRejected then return end
    if not mod.HasAuraContainers() then return end

    local iconSize = mod.AuraIconSize("debuff")
    local spacing = mod.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)

    local boxHolder = CreateContainer(widget, iconSize, AnchorUtil.FlowDirection.Left)
    if not boxHolder then return end
    boxHolder:SetPoint("TOPRIGHT", widget, "BOTTOMRIGHT", 0, 0)

    -- With the default "all debuffs" setting no candidate filter is passed at
    -- all, which is exactly what earlier versions did.
    local filters = mod.DebuffCandidateFilters()
    local addOk, addErr = pcall(boxHolder.AddAuraGroup, boxHolder, "debuffs", K.DEBUFF_AURA_FILTER, {
        maxFrameCount = math.max(mod.SettingNumber("maxDebuffs", K.DEBUFF_DEFAULT_COUNT), 0),
        sortMethod = AuraContainerSortMethod.UnitFrameDebuff,
        sortDirection = AuraContainerSortDirection.Normal,
        candidateFilters = next(filters) and filters or nil,
        initializeFrame = function(button) StyleAuraButton(button, "debuff") end,
        layout = {
            elementSpacing = spacing,
            lineSpacing = spacing,
            elementWidth = iconSize,
            elementHeight = iconSize,
        },
    })
    if not addOk then
        boxHolder:Hide()
        GroupRejected(widget, "debuffRejected", addErr)
        return
    end

    widget.debuffContainer = boxHolder
    mod.RefreshDebuffContainer(widget)
end

function mod.CreateDefensiveAuraContainer(widget)
    if InCombatLockdown() or widget.defensiveContainer or widget.defensiveRejected then return end
    if not mod.HasAuraContainers() then return end

    local iconSize = mod.AuraIconSize("defensive")
    local spacing = K.DEBUFF_SPACING

    local boxHolder = CreateContainer(widget, iconSize, AnchorUtil.FlowDirection.Left)
    if not boxHolder then return end
    boxHolder:SetPoint("TOPRIGHT", widget.health, "RIGHT", -K.DEBUFF_SPACING, iconSize / 2 - 2)

    local addOk, addErr =
        pcall(boxHolder.AddAuraGroup, boxHolder, "defensives", K.BIG_DEFENSIVE_AURA_FILTER, {
            maxFrameCount = math.max(mod.SettingNumber("maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT), 0),
            sortMethod = AuraContainerSortMethod.BigDefensive,
            sortDirection = AuraContainerSortDirection.Normal,
            initializeFrame = function(button) StyleAuraButton(button, "defensive") end,
            layout = {
                elementSpacing = spacing,
                lineSpacing = spacing,
                elementWidth = iconSize,
                elementHeight = iconSize,
            },
        })
    if not addOk then
        boxHolder:Hide()
        GroupRejected(widget, "defensiveRejected", addErr)
        return
    end

    widget.defensiveContainer = boxHolder
    mod.RefreshDefensiveContainer(widget)
end

-- ── One-time migration off the legacy private-aura row ────────────────────
-- An AuraContainer draws private auras alongside public ones (its aura source
-- list is PublicAndPrivate), and in Midnight most encounter tank debuffs are
-- private auras. So once the debuff container is running, the separate
-- AddPrivateAuraAnchor row shows the same icons a second time.
--
-- Turn that row off once, explain why, and leave the setting in place so it
-- can be turned back on from the options panel by anyone who wants it.
function mod.MigratePrivateAuraRow()
    local saved = mod.DB()
    if saved.auraContainerMigrated then return end
    if not (CoTankAuras and CoTankAuras.debuffContainer) then return end

    saved.auraContainerMigrated = true
    local previous = mod.SettingNumber("maxPrivateAuras", K.PRIVATE_AURAS_DEFAULT_COUNT)
    if previous <= 0 then return end

    saved.maxPrivateAuras = 0
    if CoTankAuras.UpdateAndRefreshAuraLayout then CoTankAuras:UpdateAndRefreshAuraLayout(0) end
    mod.Print(
        "Private auras now appear in the tank debuff row, so the separate "
            .. "private aura row has been turned off to stop icons showing twice. "
            .. "Turn it back on under |cffffff00/ctank|r > Frame if you prefer the old layout."
    )
end

-- ── Tank debuff toggle ────────────────────────────────────────────────────
function mod.DebuffsEnabled()
    local saved = mod.DB()
    if saved.debuffsEnabled == nil then saved.debuffsEnabled = true end
    return saved.debuffsEnabled ~= false
end

-- ── Runtime updates ───────────────────────────────────────────────────────
-- A container is live only while it is both enabled and visible. Test mode
-- takes the display over with mock icons, so the container stands down then.
local function ApplyContainerState(boxHolder, groupKey, unitToken, maxCount, enabled)
    if not boxHolder then return end

    local live = enabled
        and maxCount > 0
        and unitToken ~= nil
        and not mod.isTestMode
        and not mod.IsInEditMode()

    if live then boxHolder:SetUnit(unitToken) end
    pcall(boxHolder.SetAuraGroupMaxFrameCount, boxHolder, groupKey, math.max(maxCount, 0))
    boxHolder:SetEnabled(live)
    if not InCombatLockdown() then boxHolder:SetShown(live) end
end

function mod.RefreshDebuffContainer(widget)
    widget = widget or CoTankAuras
    if not widget or not widget.debuffContainer then return end
    ApplyContainerState(
        widget.debuffContainer,
        "debuffs",
        widget:GetAttribute("unit"),
        mod.SettingNumber("maxDebuffs", K.DEBUFF_DEFAULT_COUNT),
        mod.DebuffsEnabled()
    )
end

function mod.RefreshDefensiveContainer(widget)
    widget = widget or CoTankAuras
    if not widget or not widget.defensiveContainer then return end
    ApplyContainerState(
        widget.defensiveContainer,
        "defensives",
        widget:GetAttribute("unit"),
        mod.SettingNumber("maxDefensives", K.BIG_DEFENSIVES_DEFAULT_COUNT),
        true
    )
end

-- Applies the debuff filter setting to the live container. This is a
-- container-level call, so it does not touch the (possibly forbidden) buttons.
function mod.RefreshDebuffFilter(widget)
    widget = widget or CoTankAuras
    if not widget or not widget.debuffContainer then return end
    pcall(
        widget.debuffContainer.SetAuraGroupCandidateFilters,
        widget.debuffContainer,
        "debuffs",
        mod.DebuffCandidateFilters()
    )
end

function mod.RefreshAuraContainers(widget)
    mod.RefreshDebuffContainer(widget)
    mod.RefreshDefensiveContainer(widget)
end

function mod.SetDebuffsEnabled(enabled)
    mod.DB().debuffsEnabled = enabled and true or false
    if CoTankAuras then
        mod.RefreshDebuffContainer(CoTankAuras)
        CoTankAuras:RefreshDebuffLayout()
        if mod.isTestMode then
            if enabled then
                CoTankAuras:ShowMockDebuffs()
            else
                CoTankAuras:ClearDebuffs()
            end
        end
    end
    if mod.Options and mod.Options.SyncTestButton then mod.Options:SyncTestButton() end
    return mod.DebuffsEnabled()
end

function mod.ToggleDebuffs() return mod.SetDebuffsEnabled(not mod.DebuffsEnabled()) end

-- ── Restyling after an options change ─────────────────────────────────────
-- Buttons the engine has already created keep the size and regions they were
-- given in initializeFrame. They can only be touched again while auras are
-- non-secret; in combat/encounters they are forbidden and any call errors.
local pendingRestyle = false

-- Replays a restyle that was blocked by secrecy. Called from the
-- PLAYER_REGEN_ENABLED handler in Core.lua.
function mod.FlushPendingRestyle()
    if not pendingRestyle then return end
    if mod.AurasAreSecret() then return end
    pendingRestyle = false
    mod.RestyleAuraButtons()
end

function mod.RestyleAuraButtons()
    -- Buttons are forbidden while auras are secret, so remember that a
    -- restyle is owed rather than dropping the settings change entirely.
    if InCombatLockdown() or mod.AurasAreSecret() then
        pendingRestyle = true
        return
    end

    -- Every button the engine has created for us passed through
    -- initializeFrame, so this covers them all without having to ask the
    -- container to hand them back.
    for button in pairs(buttonRegions) do
        pcall(ApplyButtonSettings, button)
    end
end

-- Layout is a container-level property, so it applies without touching the
-- individual (possibly forbidden) buttons.
function mod.RefreshAuraContainerLayout(widget)
    widget = widget or CoTankAuras
    if not widget then return end

    if widget.debuffContainer then
        local spacing = mod.SettingNumber("debuffSpacing", K.DEBUFF_SPACING)
        local iconSize = mod.AuraIconSize("debuff")
        pcall(widget.debuffContainer.SetAuraGroupLayout, widget.debuffContainer, "debuffs", {
            elementSpacing = spacing,
            lineSpacing = spacing,
            elementWidth = iconSize,
            elementHeight = iconSize,
        })
    end

    if widget.defensiveContainer then
        local iconSize = mod.AuraIconSize("defensive")
        pcall(widget.defensiveContainer.SetAuraGroupLayout, widget.defensiveContainer, "defensives", {
            elementSpacing = K.DEBUFF_SPACING,
            lineSpacing = K.DEBUFF_SPACING,
            elementWidth = iconSize,
            elementHeight = iconSize,
        })
        -- Re-centre the row on the health bar at the new icon size.
        if not InCombatLockdown() and widget.health then
            widget.defensiveContainer:ClearAllPoints()
            widget.defensiveContainer:SetPoint(
                "TOPRIGHT",
                widget.health,
                "RIGHT",
                -K.DEBUFF_SPACING,
                iconSize / 2 - 2
            )
        end
    end
end
