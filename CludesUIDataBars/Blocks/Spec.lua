if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if CludesUI.IS_FOREVER then
    return
end -- one spec per class on WoW Forever, nothing to switch: no factory, no loadout hook (the main file drops the block from BLOCK_TYPES too)
-------------------------------------------------------------------------------
--  Blocks\Spec.lua - Info Bar block: specialisation, loadout and loot spec.
--
--  Shows the spec's icon and the loadout name (or the spec name), and the
--  loot spec in brackets when it differs. Hover opens the spec list (hover
--  the active spec for its loadouts, click another to switch); Ctrl+click
--  lists the loadouts, Shift+click opens talents, right-click picks the loot
--  spec (allowed in combat).
--
--  The loadout name comes from the "last selected loadout" pointer, which the
--  game writes AFTER the talent events fire (they would read the old name),
--  so the write itself is hooked. SPELLS_CHANGED fires often; the block
--  redraws only when what it shows changed.
--
--  Settings (blockCfg.settings): showLoadout (default on), useUppercase,
--  iconStyle = "wow", showIcon (default on).
-------------------------------------------------------------------------------
local _, mod = ...
local L = mod.L
local MEDIA = mod.MEDIA
local K = mod.BlockKit

local InCombatLockdown = InCombatLockdown
local floor, max, min = math.floor, math.max, math.min

local CONTENT_BASE = K.CONTENT_BASE
local VSlotW, HBudget = K.VSlotW, K.HBudget
local BlockColorOf, IconColorOf = K.BlockColorOf, K.IconColorOf

-- Every live spec block, as a set (a destroyed one leaves it, so bar
-- rebuilds do not pile them up).
local blocks = {}
local hooked = false
-- Talent frames and loadout addons all write the pointer through this.
-- Skipped in combat; PLAYER_REGEN_ENABLED catches up.
local function HookLoadoutPointer()
    if
        hooked or not (C_ClassTalents and C_ClassTalents.UpdateLastSelectedSavedConfigID and hooksecurefunc)
    then
        return
    end
    hooked = true
    hooksecurefunc(C_ClassTalents, "UpdateLastSelectedSavedConfigID", function()
        if InCombatLockdown() then
            return
        end
        for block in pairs(blocks) do
            block:Refresh()
        end
    end)
end

mod.BlockFactories.spec = function(blockCfg, slot, contentFrame, barCtx)
    local instance = { cfg = blockCfg, slot = slot, content = contentFrame, ctx = barCtx }
    instance.key = K.InstKey(barCtx, blockCfg)
    blocks[instance] = true
    HookLoadoutPointer()
    instance.events = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_LOOT_SPEC_UPDATED",
        -- TRAIT_CONFIG_UPDATED fires BEFORE the last-selected pointer moves, so
        -- its name read is stale; SPELLS_CHANGED fires once the swap applied
        -- (same signal CDM keys its talent-swap rebuilds off) and re-reads the settled name.
        "TRAIT_CONFIG_UPDATED",
        "SPELLS_CHANGED",
        -- Combat cancelling a loadout swap started from this block.
        "CONFIG_COMMIT_FAILED",
        "PLAYER_ENTERING_WORLD",
        -- Refresh runs in combat too (our frames only); regen is a cheap catch-up for anything a combat path missed.
        "PLAYER_REGEN_ENABLED",
    }

    local SPEC_MEDIA = MEDIA .. "spec\\"
    -- One PNG per spec in media\spec\, named <class>-<spec>.png, listed here in SPEC
    -- INDEX order per class (GetSpecializationInfo order is fixed) -- no spec-ID table; new specs just append.
    local SPEC_ICON_FILES = {
        WARRIOR = { "warrior-arms", "warrior-fury", "warrior-prot" },
        PALADIN = { "paladin-holy", "paladin-prot", "paladin-ret" },
        HUNTER = { "hunter-beastmaster", "hunter-marksman", "hunter-survival" },
        ROGUE = { "rogue-assasin", "rogue-outlaw", "rogue-sub" },
        PRIEST = { "priest-disc", "priest-holy", "priest-shadow" },
        DEATHKNIGHT = { "dk-blood", "dk-frost", "dk-unholy" },
        SHAMAN = { "shaman-ele", "shaman-enhance", "shaman-resto" },
        MAGE = { "mage-arcane", "mage-fire", "mage-frost" },
        WARLOCK = { "warlock-aff", "warlock-demo", "warlock-destro" },
        MONK = { "monk-brew", "monk-mw", "monk-ww" },
        DRUID = { "druid-balance", "druid-feral", "druid-bear", "druid-resto" },
        DEMONHUNTER = { "dh-havoc", "dh-vengeance", "dh-devourer" },
        EVOKER = { "evoker-dev", "evoker-pres", "evoker-aug" },
    }
    local POPUP_FONT_SIZE = 12
    local POPUP_PAD = 8

    local specCache, numSpecs = {}, 0
    local currentSpecIdx, currentLootSpecID = nil, 0
    local mouseOver = false

    -- Loadout swap, Blizzard's sequence: the last-selected pointer is written
    -- only once the swap is real -- immediately when no commit is needed,
    -- else on the TRAIT_CONFIG_UPDATED that lands the commit. Nothing is
    -- written up front, so a commit cancelled by combat leaves the pointer
    -- on the loadout still applied.
    local pendingSwapSpecId, pendingSwapConfigID
    local function BeginLoadoutSwap(specId, configID)
        local result = C_ClassTalents.LoadConfig(configID, true)
        local R = Enum.LoadConfigResult
        if result == R.NoChangesNecessary then
            C_ClassTalents.UpdateLastSelectedSavedConfigID(specId, configID)
        elseif result ~= R.Error then
            pendingSwapSpecId, pendingSwapConfigID = specId, configID
        end
        instance:Refresh()
    end

    -- Per-instance popup pools (lazy). Two spec blocks never fight over the same popup frames.
    local specPool, lootPool, loadoutPool

    local function D()
        return blockCfg.settings or {}
    end
    local function BC()
        return barCtx.cfg
    end

    -- Spec reads go through C_SpecializationInfo: the legacy globals are not
    -- registered on WoW Forever (same native functions on retail). The loot
    -- spec pair and GetNumSpecializations are plain globals on both clients.
    local function BuildSpecCache()
        specCache = {}
        numSpecs = GetNumSpecializations() or 0
        for index = 1, numSpecs do
            local ident, name, _, iconTex, role = C_SpecializationInfo.GetSpecializationInfo(index)
            if ident then
                specCache[index] = { id = ident, name = name, icon = iconTex, role = role }
            end
        end
    end

    local function UpdateCurrentSpec()
        currentSpecIdx = C_SpecializationInfo.GetSpecialization()
        currentLootSpecID = GetLootSpecialization() or 0
    end

    local function GetCurrentLoadoutName()
        if not (C_ClassTalents and C_ClassTalents.GetLastSelectedSavedConfigID) then
            return nil
        end
        local specId = PlayerUtil and PlayerUtil.GetCurrentSpecID and PlayerUtil.GetCurrentSpecID()
        if not specId then
            return nil
        end
        local configID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        if not configID then
            return nil
        end
        local details = C_Traits and C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(configID)
        if details then
            return details.name
        end
        return nil
    end

    local function GetLootSpecName()
        if currentLootSpecID == 0 then
            if currentSpecIdx and specCache[currentSpecIdx] then
                return specCache[currentSpecIdx].name
            end
            return nil
        end
        local _, name
        if GetSpecializationInfoByID then
            _, name = GetSpecializationInfoByID(currentLootSpecID)
        end
        return name
    end

    local function GetBarDisplayText()
        local skinData = D()
        local textValue
        if skinData.showLoadout ~= false then
            textValue = GetCurrentLoadoutName()
        end
        if not textValue then
            if currentSpecIdx and specCache[currentSpecIdx] then
                textValue = specCache[currentSpecIdx].name
            end
        end
        if not textValue then
            textValue = ""
        end
        -- Opt-in only (default off): never force-capitalize.
        if skinData.useUppercase == true then
            return textValue:upper()
        end
        return textValue
    end

    local specButton = CreateFrame("Button", nil, contentFrame)
    specButton:SetAllPoints()
    specButton:EnableMouse(true)
    specButton:RegisterForClicks("AnyUp")

    local specIcon = contentFrame:CreateTexture(nil, "OVERLAY")
    specIcon:SetSize(16, 16)
    local specText = contentFrame:CreateFontString(nil, "OVERLAY")
    local infoText = contentFrame:CreateFontString(nil, "OVERLAY")
    infoText:Hide()
    K.AttachTextOffset(instance, specText) -- infoText chains to specText

    -- Generic popup builder (shared across the three popups of THIS instance)
    local function BuildPopup(
        pool,
        hostFrame,
        title,
        entries,
        onClickEntry,
        noCatcher,
        footerLines,
        combatClicks
    )
        if not pool then
            return nil
        end
        pool:ReleaseAll()
        local dialog = pool._popup
        if not dialog then
            dialog = mod.CreatePopupFrame(hostFrame)
            pool._popup = dialog
        end
        dialog._wbNoCatcher = noCatcher and true or nil
        dialog._wbOnHide = function()
            pool:ReleaseAll()
            if pool._onHide then
                pool._onHide()
            end
        end
        dialog:Show()

        local ar, ag, ab = mod.GetAccent()
        local fontSize = POPUP_FONT_SIZE
        local iconSz = fontSize + 2
        local PAD, LINE = POPUP_PAD, 18

        -- Title is optional: a nil/empty title (the loadout subnav) renders a plain list with even PAD margins on all four sides.
        if not dialog._title then
            dialog._title = dialog:CreateFontString(nil, "OVERLAY")
        end
        dialog._title:ClearAllPoints()
        dialog._title:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -PAD)
        local maxW, yOff
        if title and title ~= "" then
            mod.SetFont(dialog._title, fontSize)
            -- Localize here: these popups SetText directly instead of the Tip_* helpers that normally route fixed strings through the locale.
            dialog._title:SetText(CludesUI.L(title))
            dialog._title:SetTextColor(1, 1, 1, 1)
            dialog._title:Show()
            maxW = dialog._title:GetStringWidth()
            yOff = PAD + LINE + PAD
        else
            dialog._title:Hide()
            maxW = 0
            yOff = PAD
        end

        local rowBtns = {}
        for _, record in ipairs(entries) do
            local button = pool:Acquire()
            button:SetParent(dialog)
            -- 2px band above/below the content, matching the shared tip's clickable rows.
            button:SetHeight(iconSz + 4)
            button:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -yOff)
            button:EnableMouse(true)
            button:RegisterForClicks("AnyUp")
            -- Full-row white hover wash (house style 0.10), same as the shared tip's
            -- clickable rows; HIGHLIGHT layer needs no scripts. Color RE-ASSERTED every
            -- build: the pool resetter nils the highlight texture on every release.
            if not button._hl then
                button._hl = button:CreateTexture(nil, "HIGHLIGHT")
                button._hl:SetAllPoints()
            end
            button._hl:SetColorTexture(1, 1, 1, 0.10)

            if not button._icon then
                button._icon = button:CreateTexture(nil, "OVERLAY")
            end
            button._icon:SetSize(iconSz, iconSz)
            button._icon:ClearAllPoints()
            button._icon:SetPoint("LEFT")

            if not button._label then
                button._label = button:CreateFontString(nil, "OVERLAY")
            end
            button:Show()
            mod.SetFont(button._label, fontSize)
            button._label:SetText(record.name)
            button._label:Show()
            button._label:ClearAllPoints()
            if record.icon then
                button._icon:SetTexture(record.icon)
                button._icon:SetTexCoord(4 / 64, 60 / 64, 4 / 64, 60 / 64)
                button._icon:Show()
                button._label:SetPoint("LEFT", button._icon, "RIGHT", 4, 0)
            else
                -- Icon-less rows (loadouts): flush left -- anchoring to the hidden icon's stale rect left a phantom indent.
                button._icon:Hide()
                button._label:SetPoint("LEFT", button, "LEFT", 0, 0)
            end

            if record.isActive then
                button._label:SetTextColor(ar, ag, ab, 1)
            else
                button._label:SetTextColor(1, 1, 1, 1)
            end

            -- Right-edge arrow (entry.arrow): the active spec row uses it to signal its loadout subnav.
            if record.arrow then
                if not button._arrow then
                    button._arrow = button:CreateTexture(nil, "OVERLAY")
                end
                -- FULL re-assert every build: the pool resetter hides and strips regions on release, so creation-only setup does not survive.
                button._arrow:SetSize(10, 10)
                button._arrow:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-right.png")
                button._arrow:ClearAllPoints()
                button._arrow:SetPoint("RIGHT", button, "RIGHT", -2, 0)
                button._arrow:SetVertexColor(ar, ag, ab, 0.9)
                button._arrow:Show()
            elseif button._arrow then
                button._arrow:Hide()
            end

            button:SetScript("OnEnter", function()
                button._label:SetTextColor(ar, ag, ab, 1)
                -- Row hover callback (spec popup: open/close the loadout subnav depending on which row the cursor is on).
                if record.onHover then
                    record.onHover(button)
                end
            end)
            button:SetScript("OnLeave", function()
                if record.isActive then
                    button._label:SetTextColor(ar, ag, ab, 1)
                else
                    button._label:SetTextColor(1, 1, 1, 1)
                end
            end)
            button:SetScript("OnClick", function(_, mb)
                -- entry.noClick: informational row (the active spec opens a subnav instead of re-selecting itself).
                if record.noClick then
                    return
                end
                -- combatClicks: the loot-spec popup's action is combat-legal (unprotected preference call); everything else stays gated.
                if mb == "LeftButton" and (combatClicks or not InCombatLockdown()) then
                    onClickEntry(record)
                    dialog:Hide()
                end
            end)

            local iconExtra = 0
            if button._icon:IsShown() then
                iconExtra = iconSz + 4
            end
            local bw = iconExtra + button._label:GetStringWidth()
            if record.arrow then
                bw = bw + 16
            end
            if bw > maxW then
                maxW = bw
            end
            button:SetWidth(bw)
            rowBtns[#rowBtns + 1] = button
            yOff = yOff + (iconSz + 4) + 3
        end
        -- Trim the last row's trailing gap so the bottom padding stays PAD.
        if #entries > 0 then
            yOff = yOff - 3
        end

        -- Optional footer descriptor lines ({left, right} pairs): the same Left Click / Right Click hints the shared tip footers use.
        if not dialog._foot then
            dialog._foot = {}
        end
        local footCount = footerLines and #footerLines or 0
        if footCount > 0 then
            yOff = yOff + 8
            for index = 1, footCount do
                local fl = dialog._foot[index]
                if not fl then
                    fl = {
                        l = dialog:CreateFontString(nil, "OVERLAY"),
                        r = dialog:CreateFontString(nil, "OVERLAY"),
                    }
                    dialog._foot[index] = fl
                end
                mod.SetFont(fl.l, fontSize)
                mod.SetFont(fl.r, fontSize)
                fl.l:SetText(CludesUI.L(footerLines[index][1]))
                fl.l:SetTextColor(1, 1, 1, 1)
                fl.r:SetText(CludesUI.L(footerLines[index][2]))
                fl.r:SetTextColor(1, 1, 1, 1)
                fl.l:ClearAllPoints()
                fl.l:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -yOff)
                fl.r:ClearAllPoints()
                fl.r:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -PAD, -yOff)
                fl.l:Show()
                fl.r:Show()
                local fw = (fl.l:GetStringWidth() or 0) + 16 + (fl.r:GetStringWidth() or 0)
                if fw > maxW then
                    maxW = fw
                end
                yOff = yOff + fontSize + 4
            end
            yOff = yOff - 4
        end
        for index = footCount + 1, #dialog._foot do
            dialog._foot[index].l:Hide()
            dialog._foot[index].r:Hide()
        end

        dialog:SetSize(maxW + PAD * 2, yOff + PAD)
        -- Stretch every row to the popup's inner width: the wash and the click target span the full row, not just the text.
        for index = 1, #rowBtns do
            rowBtns[index]:SetWidth(maxW)
        end
        dialog:ClearAllPoints()
        if barCtx.IsVertical() then
            -- Bar on the right half of the screen: popup opens to the left.
            local cx = hostFrame:GetCenter()
            if cx and cx > UIParent:GetWidth() / 2 then
                dialog:SetPoint("RIGHT", hostFrame, "LEFT", -4, 0)
            else
                dialog:SetPoint("LEFT", hostFrame, "RIGHT", 4, 0)
            end
        else
            if barCtx.IsBarAtTop() then
                dialog:SetPoint("TOP", hostFrame, "BOTTOM", 0, -4)
            else
                dialog:SetPoint("BOTTOM", hostFrame, "TOP", 0, 4)
            end
        end
        dialog:SetClampedToScreen(true)
        if dialog._wbClickCatcher then
            dialog._wbClickCatcher:ClearAllPoints()
            dialog._wbClickCatcher:SetAllPoints(UIParent)
        end
        return dialog
    end

    -- Forward-declared: the loot toggle arms it for in-combat dismissal and it is built (as a frame) below the popups.
    local hoverWatch

    -- Loadout SUBNAV: flyout beside the spec popup, opened by hovering the ACTIVE spec row (not clickable), listing its loadouts click-to-swap.
    local subnavPool
    local function CloseLoadoutSubnav()
        if subnavPool and subnavPool._popup and subnavPool._popup:IsShown() then
            subnavPool._popup:Hide()
        end
    end
    local function OpenLoadoutSubnav(rowBtn)
        if subnavPool and subnavPool._popup and subnavPool._popup:IsShown() then
            return
        end
        if
            not (
                C_ClassTalents
                and C_ClassTalents.GetConfigIDsBySpecID
                and C_Traits
                and C_Traits.GetConfigInfo
            )
        then
            return
        end
        local specId = currentSpecIdx and specCache[currentSpecIdx] and specCache[currentSpecIdx].id
        if not specId then
            return
        end
        if not subnavPool then
            subnavPool = mod.CreateFramePool("Button", UIParent)
        end
        local activeConfigID
        if C_ClassTalents.GetLastSelectedSavedConfigID then
            activeConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        end
        local entries = {}
        for _, cid in ipairs(C_ClassTalents.GetConfigIDsBySpecID(specId) or {}) do
            local details = C_Traits.GetConfigInfo(cid)
            if details and details.name then
                entries[#entries + 1] =
                    { name = details.name, isActive = (cid == activeConfigID), configID = cid }
            end
        end
        if #entries == 0 then
            return
        end
        local pop = BuildPopup(subnavPool, specButton, nil, entries, function(e)
            BeginLoadoutSwap(specId, e.configID)
        end, true)
        -- Flyout anchoring: flush against the spec popup's edge, with its
        -- FIRST entry level with the row the cursor is on, so a straight
        -- rightward move lands inside the list. Anchoring to the popup with
        -- a row-derived offset, rather than to the row button itself, keeps
        -- the anchor between two long-lived frames: the rows are POOLED and
        -- ResetPooledFrame clears their points on release, which _wbOnHide
        -- does BEFORE it closes this flyout. Vertical overflow is left to
        -- SetClampedToScreen (already set), so the flyout only bumps when it
        -- would leave the screen.
        local main = specPool and specPool._popup
        if pop and main then
            local mainTop = main:GetTop()
            local rowTop = rowBtn and rowBtn.GetTop and rowBtn:GetTop()
            local dy = 0
            if mainTop and rowTop then
                dy = POPUP_PAD - (mainTop - rowTop)
            end
            pop:ClearAllPoints()
            local right = main:GetRight() or 0
            if right + (pop:GetWidth() or 0) > UIParent:GetWidth() then
                pop:SetPoint("TOPRIGHT", main, "TOPLEFT", 0, dy)
            else
                pop:SetPoint("TOPLEFT", main, "TOPRIGHT", 0, dy)
            end
        end
    end

    local function ToggleSpecPopup()
        if specPool and specPool._popup and specPool._popup:IsShown() then
            specPool._popup:Hide()
            return
        end
        if not specPool then
            specPool = mod.CreateFramePool("Button", UIParent)
        end
        -- Any path that hides the spec popup takes the loadout subnav with it.
        specPool._onHide = CloseLoadoutSubnav
        local entries = {}
        for index = 1, numSpecs do
            local details = specCache[index]
            if details then
                local isActive = (index == currentSpecIdx)
                entries[#entries + 1] = {
                    name = details.name,
                    icon = details.icon,
                    isActive = isActive,
                    specIndex = index,
                    -- Active spec: not clickable; hover opens the loadout subnav (arrow marks it), any other row closes it.
                    noClick = isActive,
                    arrow = isActive,
                    onHover = isActive and OpenLoadoutSubnav or CloseLoadoutSubnav,
                }
            end
        end
        BuildPopup(
            specPool,
            specButton,
            L["CHANGE_SPEC"],
            entries,
            function(e)
                C_SpecializationInfo.SetSpecialization(e.specIndex)
            end,
            true,
            {
                { L["LEFT_CLICK"], L["CHANGE_SPEC_SHORT"] },
                { L["CTRL_LEFT_CLICK"], L["CHANGE_LOADOUT"] },
                { L["SHIFT_LEFT_CLICK"], L["OPEN_TALENTS"] },
                { L["RIGHT_CLICK"], L["CHANGE_LOOT_SPEC"] },
            }
        )
    end

    local function ToggleLootSpecPopup()
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then
            lootPool._popup:Hide()
            return
        end
        if not lootPool then
            lootPool = mod.CreateFramePool("Button", UIParent)
        end
        local activeIcon = nil
        if currentSpecIdx and specCache[currentSpecIdx] then
            activeIcon = specCache[currentSpecIdx].icon
        end
        local entries = {
            {
                name = L["CURRENT_SPEC"],
                icon = activeIcon,
                isActive = currentLootSpecID == 0,
                specIndex = 0,
            },
        }
        for index = 1, numSpecs do
            local details = specCache[index]
            if details then
                entries[#entries + 1] = {
                    name = details.name,
                    icon = details.icon,
                    isActive = (details.id == currentLootSpecID),
                    specIndex = index,
                }
            end
        end
        -- Loot spec switching is combat-legal: SetLootSpecialization is an
        -- unprotected server-preference call. In lockdown the popup opens
        -- WITHOUT the fullscreen click-catcher (an invisible click-eater must
        -- never go live in combat) and dismisses via the hover watcher.
        local inCombat = InCombatLockdown()
        BuildPopup(lootPool, specButton, L["CHANGE_LOOT_SPEC"], entries, function(e)
            local ident = 0
            if e.specIndex > 0 then
                ident = select(1, C_SpecializationInfo.GetSpecializationInfo(e.specIndex)) or 0
            end
            SetLootSpecialization(ident)
        end, inCombat, nil, true)
        if inCombat and hoverWatch then
            hoverWatch._watchPool = lootPool
            hoverWatch:Show()
        end
    end

    local function ToggleLoadoutPopup()
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then
            loadoutPool._popup:Hide()
            return
        end
        if
            not (
                C_ClassTalents
                and C_ClassTalents.GetConfigIDsBySpecID
                and C_Traits
                and C_Traits.GetConfigInfo
            )
        then
            return
        end
        if not loadoutPool then
            loadoutPool = mod.CreateFramePool("Button", UIParent)
        end

        local specId = nil
        if currentSpecIdx and specCache[currentSpecIdx] then
            specId = specCache[currentSpecIdx].id
        end
        if not specId then
            return
        end
        local activeConfigID = nil
        if C_ClassTalents.GetLastSelectedSavedConfigID then
            activeConfigID = C_ClassTalents.GetLastSelectedSavedConfigID(specId)
        end
        local configIDs = C_ClassTalents.GetConfigIDsBySpecID(specId)
        local entries = {}
        for _, cid in ipairs(configIDs) do
            local details = C_Traits.GetConfigInfo(cid)
            if details and details.name then
                entries[#entries + 1] =
                    { name = details.name, isActive = (cid == activeConfigID), configID = cid }
            end
        end
        -- In lockdown: catcher-free + hover-watch dismissal like the loot popup.
        -- Row clicks stay gated (LoadConfig is blocked); the list is viewable.
        local inCombat = InCombatLockdown()
        BuildPopup(loadoutPool, specButton, L["CHANGE_LOADOUT"], entries, function(e)
            BeginLoadoutSwap(specId, e.configID)
        end, inCombat)
        if inCombat and hoverWatch then
            hoverWatch._watchPool = loadoutPool
            hoverWatch:Show()
        end
    end

    local function HideAllPopups()
        if specPool and specPool._popup and specPool._popup:IsShown() then
            specPool._popup:Hide()
        end
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then
            lootPool._popup:Hide()
        end
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then
            loadoutPool._popup:Hide()
        end
    end

    -- Everything the block shows, as one string: equal = nothing to redraw.
    local drawn
    local function Fingerprint()
        local skinData = D()
        local current = currentSpecIdx and specCache[currentSpecIdx]
        return table.concat({
            GetBarDisplayText(),
            tostring(GetLootSpecName()),
            tostring(currentSpecIdx),
            tostring(current and current.icon),
            tostring(skinData.showIcon),
            tostring(skinData.iconStyle),
            tostring(skinData.useUppercase),
        }, "|")
    end

    -- Text and icon colours (the accent on hover).
    local function Paint()
        if mouseOver then
            local region, g, b = mod.GetAccent()
            specText:SetTextColor(region, g, b, 1)
            specIcon:SetVertexColor(region, g, b, 1)
        else
            local region, g, b = BlockColorOf(blockCfg)
            local ir, ig, ib = IconColorOf(blockCfg)
            specText:SetTextColor(region, g, b, 1)
            specIcon:SetVertexColor(ir, ig, ib, 1)
        end
    end

    function instance:Refresh()
        -- No combat gate: only our own insecure frames (text, textures, sizes),
        -- and an in-combat loot spec change must repaint at once.
        UpdateCurrentSpec()
        local skinData = D()
        local barCfg = BC()
        local barH = barCtx.GetThickness()
        local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
        -- The loot spec is smaller than the main label (11px at the 30 base).
        local infoSz = max(8, floor(CONTENT_BASE * 0.36 + 0.5))
        local gap = 4 -- label to loot spec; the icon uses ICON_GAP
        local iconGap = K.ICON_GAP
        local isSide = barCtx.IsVertical()
        local specLabel = GetBarDisplayText()
        local iconSz = fontSize + 8

        mod.SetFont(specText, fontSize, barCfg)
        mod.SetFont(infoText, infoSz, barCfg)
        specText:SetText(specLabel)

        if currentSpecIdx then
            local _, classId = UnitClass("player")
            local files = classId and SPEC_ICON_FILES[classId]
            local file = files and files[currentSpecIdx]
            local specInfo = specCache[currentSpecIdx]
            -- Blizzard style: the game's own spec icon, cropped off its border.
            if (blockCfg.settings or {}).iconStyle == "wow" and specInfo and specInfo.icon then
                specIcon:SetTexture(specInfo.icon)
                K.CropStockIcon(specIcon)
            elseif file then
                specIcon:SetTexture(SPEC_MEDIA .. file .. ".png")
                specIcon:SetTexCoord(0, 1, 0, 1)
            end
        end

        Paint()

        local lootName = GetLootSpecName()
        local activeSpecName = nil
        if currentSpecIdx and specCache[currentSpecIdx] then
            activeSpecName = specCache[currentSpecIdx].name
        end
        if lootName and lootName ~= activeSpecName then
            if skinData.useUppercase ~= false then
                infoText:SetText("(" .. lootName:upper() .. ")")
            else
                infoText:SetText("(" .. lootName .. ")")
            end
            infoText:SetTextColor(1, 1, 1, 0.8)
            infoText:Show()
        else
            infoText:Hide()
        end

        -- Show Icon (default ON): hidden drops the icon width and gap entirely.
        local showIcon = skinData.showIcon ~= false
        if showIcon then
            specIcon:Show()
        else
            specIcon:Hide()
            iconSz = 0
        end

        if isSide then
            iconSz = min(iconSz, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            if not showIcon then
                iconSz = 0
            end
        end
        if showIcon then
            specIcon:SetSize(iconSz, iconSz)
        end

        if isSide then
            local slotW = VSlotW(instance)
            local innerW = max(30, slotW - 8)
            local totalH = 8 + iconSz + 2

            specIcon:ClearAllPoints()
            specIcon:SetPoint("TOP", contentFrame, "TOP", 0, -4)

            mod.SetWrappedText(specText, innerW, "CENTER")
            specText:ClearAllPoints()
            if showIcon then
                specText:SetPoint("TOP", specIcon, "BOTTOM", 0, -2)
            else
                specText:SetPoint("TOP", contentFrame, "TOP", 0, -4)
            end
            totalH = totalH + mod.SnapToPixelGrid(specText:GetStringHeight())

            if infoText:IsShown() then
                mod.SetWrappedText(infoText, innerW, "CENTER")
                infoText:ClearAllPoints()
                infoText:SetPoint("TOP", specText, "BOTTOM", 0, -2)
                totalH = totalH + 2 + mod.SnapToPixelGrid(infoText:GetStringHeight())
            end

            totalH = max(totalH, barH)
            contentFrame:SetSize(slotW, totalH)
        else
            local slotW = HBudget(instance, 120)
            mod.SetFont(specText, fontSize, barCfg)
            specText:SetText(specLabel)
            if infoText:IsShown() then
                mod.SetFont(infoText, infoSz, barCfg)
            end
            if showIcon then
                iconSz = min(fontSize + 8, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
                specIcon:SetSize(iconSz, iconSz)
            else
                iconSz = 0
            end
            mod.ResetInlineText(specText, "LEFT")
            mod.ResetInlineText(infoText, "LEFT")
            local tw = mod.SnapToPixelGrid(specText:GetStringWidth())
            -- Loot spec sits INLINE right of the spec/loadout label (below on
            -- vertical bars); content width includes it so Auto bars reserve it.
            local iw = 0
            if infoText:IsShown() then
                iw = mod.SnapToPixelGrid(infoText:GetStringWidth() or 0)
            end
            local infoPad = 0
            if iw > 0 then
                infoPad = gap + iw
            end
            local effIconGap = showIcon and iconGap or 0
            local totalW = min(slotW, iconSz + effIconGap + tw + infoPad + 4)
            specIcon:ClearAllPoints()
            specIcon:SetPoint("LEFT", contentFrame, "LEFT", 0, 0)
            specText:ClearAllPoints()
            specText:SetPoint("LEFT", contentFrame, "LEFT", iconSz + effIconGap, 0)
            infoText:ClearAllPoints()
            infoText:SetPoint("LEFT", specText, "RIGHT", gap, 0)
            contentFrame:SetSize(totalW, barH)
        end
        specButton:ClearAllPoints()
        specButton:SetAllPoints(contentFrame)
        drawn = Fingerprint()
        K.MaybeRelayout(instance)
    end

    -- The spec popup opens on hover, closes only once the cursor is over neither
    -- the block nor the popup; both rects padded 8px so the 4px anchor gap never counts as "outside" mid-travel.
    hoverWatch = CreateFrame("Frame")
    hoverWatch:Hide()
    hoverWatch:SetScript("OnUpdate", function(self)
        -- Watches whichever pool armed it (spec hover popup, or loot popup
        -- opened catcher-free in combat). The subnav counts as inside-bounds.
        local pool = self._watchPool or specPool
        local dialog = pool and pool._popup
        if not (dialog and dialog:IsShown()) then
            self:Hide()
            return
        end
        local sub = subnavPool and subnavPool._popup
        local subShown = sub and sub:IsShown()
        if
            specButton:IsMouseOver(8, -8, -8, 8)
            or dialog:IsMouseOver(8, -8, -8, 8)
            or (subShown and sub:IsMouseOver(8, -8, -8, 8))
        then
            return
        end
        dialog:Hide()
        if subShown then
            sub:Hide()
        end
        self:Hide()
    end)

    specButton:SetScript("OnEnter", function()
        mouseOver = true
        Paint() -- hover only recolours; nothing is laid out again
        -- No combat gate: the hover popup is our own insecure frames, opens
        -- catcher-free and dismisses via the hover watcher; only swap clicks
        -- are gated. Never stomp a click-opened popup (loot spec / loadout).
        if lootPool and lootPool._popup and lootPool._popup:IsShown() then
            return
        end
        if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then
            return
        end
        if not (specPool and specPool._popup and specPool._popup:IsShown()) then
            ToggleSpecPopup()
        end
        hoverWatch._watchPool = specPool
        hoverWatch:Show()
    end)
    specButton:SetScript("OnLeave", function()
        mouseOver = false
        Paint()
    end)
    specButton:SetScript("OnClick", function(_, btnFrame)
        -- No blanket combat gate: popups open catcher-free in lockdown and the talent
        -- frame is viewable in combat; only swapping ROW clicks are locked (loot spec is legal).
        if btnFrame == "LeftButton" then
            if IsControlKeyDown() then
                if loadoutPool and loadoutPool._popup and loadoutPool._popup:IsShown() then
                    loadoutPool._popup:Hide()
                    return
                end
                HideAllPopups()
                ToggleLoadoutPopup()
            elseif IsShiftKeyDown() then
                HideAllPopups()
                if PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then
                    PlayerSpellsUtil.ToggleClassTalentFrame()
                elseif ToggleTalentFrame then
                    ToggleTalentFrame()
                end
            end
        elseif btnFrame == "RightButton" then
            if lootPool and lootPool._popup and lootPool._popup:IsShown() then
                lootPool._popup:Hide()
                return
            end
            HideAllPopups()
            ToggleLootSpecPopup()
        end
    end)

    instance.eventFrame = K.MakeEventFrame(instance, function(self, evt, eventConfigID)
        if pendingSwapConfigID then
            if evt == "TRAIT_CONFIG_UPDATED" then
                -- The commit-landing event carries the ACTIVE combat config's id,
                -- never the loadout's. Updates for any other config (loadout
                -- saves/syncs, hero-talent data -- instance background churn) are
                -- not the commit; the pointer is written from the remembered
                -- loadout id once the active config reports the landing.
                local active = C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
                if active and eventConfigID == active then
                    local specId, configID = pendingSwapSpecId, pendingSwapConfigID
                    pendingSwapSpecId, pendingSwapConfigID = nil, nil
                    C_ClassTalents.UpdateLastSelectedSavedConfigID(specId, configID)
                end
            elseif evt == "CONFIG_COMMIT_FAILED" then
                -- Payload deliberately not consulted: a failed commit while we are
                -- pending is ours, whichever id it names.
                pendingSwapSpecId, pendingSwapConfigID = nil, nil
            end
        end
        -- Talent and spell events fire often: a redraw only if something shown changed.
        UpdateCurrentSpec()
        if Fingerprint() ~= drawn then
            self:Refresh()
        end
    end)

    function instance:Enable()
        contentFrame:Show()
        drawn = nil
        BuildSpecCache()
        UpdateCurrentSpec()
        K.RegisterInstEvents(self)
    end

    function instance:Disable()
        K.UnregisterInstEvents(self)
        HideAllPopups()
        contentFrame:Hide()
    end

    function instance:GetAutoLength()
        local barH = barCtx.GetThickness()
        if barCtx.IsVertical() then
            local fontSize = max(9, floor(CONTENT_BASE * 0.4333 + 0.5))
            local iconSz = min(fontSize + 8, max(14, floor(CONTENT_BASE * 0.72 + 0.5)))
            local textH = specText:GetStringHeight() or fontSize
            local infoH = 0
            if infoText:IsShown() then
                infoH = (infoText:GetStringHeight() or 0) + 2
            end
            return max(8 + iconSz + 2 + textH + infoH + 4, barH, 60)
        end
        return max(contentFrame:GetWidth() or 120, 40)
    end

    function instance:Destroy()
        self._dead = true
        blocks[self] = nil
        HideAllPopups()
        contentFrame:Hide()
    end

    return instance
end
