if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_QoL.lua
--  Runtime logic for all Quality-of-Life features toggled in the QoL Features
--  tab of Global Settings. No UI code here -- only gameplay behaviour.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
--  Per-profile storage for QoL "extras" (Secondary Stats + FPS counter): reads
--  fall back to the account-wide CludesUIDB root when a profile has no
--  value yet (new profile/sync gap); writes always go per-profile. Mirrors the
--  crosshair read/fallback pattern; CludesUI_Migration.lua seeds every
--  existing profile from the old account-wide values. CUIQoLDB is
--  shared with Cursor/BattleRes/Bloodlust: each NewDB merges its own defaults
--  into the SAME profile table, repointed by the profile system on swap.
-------------------------------------------------------------------------------
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewCombatQueue
        and CludesUI.SetFramePlacer
        and CludesUI.RAID_PREP_IDS
        and CludesUI.SetFontFamily
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the Shifter's loot windows use the parent's frame placer; Raid Buff Check reads the parent's buff lists; the group death alert, /keys and Raid Buff Check names take the parent's font families)
local mod = select(2, ...)
CludesUI._ModuleNS["CludesUIQoL"] = mod -- LOD options files read this module ns via the registry
mod.CombatQueue = CludesUI.NewCombatQueue(CreateFrame("Frame"))

-- Unlock-mode loadPos/clearPos for a QoL element whose slice (P()) stores pos as a
-- center offset (Battle Res, Bloodlust).
function mod.CenterPosFns(P)
    local function restorePos()
        local profile = P()
        if profile and profile.pos then
            return { point = "CENTER", relPoint = "CENTER", x = profile.pos.centerX, y = profile.pos.centerY }
        end
        return nil
    end
    local function resetPos()
        local profile = P()
        if profile then
            profile.pos = nil
        end
    end
    return restorePos, resetPos
end

local _qolExtrasDB
local function QoLExtrasProfile()
    if not _qolExtrasDB and CludesUI and CludesUI.Lite and CludesUI.Lite.NewDB then
        _qolExtrasDB = CludesUI.Lite.NewDB("CludesUIQoLDB", {
            profile = {
                -- WoW Forever: every stat of its catalog that is not shown
                -- by default (CludesUIQoL_ForeverStats.lua).
                secondaryStatsHidden = mod.FvStats and mod.FvStats.hidden or {
                    leech = true,
                    avoidance = true,
                    speed = true,
                },
            },
        })
    end
    return _qolExtrasDB and _qolExtrasDB.profile
end
function CludesUI.QoLExtrasGet(key)
    local p = QoLExtrasProfile()
    if p and p[key] ~= nil then
        return p[key]
    end
    return CludesUIDB and CludesUIDB[key]
end
function CludesUI.QoLExtrasSet(key, val)
    local p = QoLExtrasProfile()
    if p then
        p[key] = val
        return
    end
    if not CludesUIDB then
        CludesUIDB = {}
    end
    CludesUIDB[key] = val
end

local qolFrame = CreateFrame("Frame")
qolFrame:RegisterEvent("PLAYER_LOGIN")
qolFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    -- Environment Ping keybind (CludesUI._applyEnvPing, further down):
    -- nothing is built unless a key is saved.
    if CludesUIDB.envPingKey then
        CludesUI._applyEnvPing()
    end
    -- Transparent World Map Sidebars (CludesUI._applyMapSidebars, further down;
    -- not on WoW Forever): nothing is built while off.
    if CludesUIDB.mapSidebarsClear and CludesUI._applyMapSidebars then
        CludesUI._applyMapSidebars()
    end
    -- Self Combat Text (CludesUIQoL_SelfCombatText.lua): nothing is built while off.
    mod.SCT_Refresh()
    if CludesUI._applyUpgradeTooltips then
        CludesUI._applyUpgradeTooltips()
    end

    ---------------------------------------------------------------------------
    -- Bonus roll confirmation. Addon-owned overlays intercept Roll/Pass clicks;
    -- the journal link and other children retain their original behavior.
    -- (Not on WoW Forever: no bonus rolls there, so the block and its options
    -- row do not exist.)
    ---------------------------------------------------------------------------
    if not CludesUI.IS_FOREVER then
        local isActive, lifecycleHooked, eventWatcher
        local rollBtn, passBtn, rollCover, passCover
        local waiting

        local function Enabled()
            return CludesUIDB
                and CludesUIDB.bonusRollConfirmation == true
                and not C_AddOns.IsAddOnLoaded("BonusRollConfirm")
        end

        local function Invalidate()
            local old = waiting
            waiting = nil
            -- The house popup is shared: the handle closes it only while it
            -- still shows this request, never another feature's dialog.
            if old then
                CludesUI:CloseConfirmPopup(old.handle)
            end
        end

        local function LootSpec()
            local ident = GetLootSpecialization()
            if ident == 0 then
                local index = C_SpecializationInfo.GetSpecialization()
                if index then
                    ident = C_SpecializationInfo.GetSpecializationInfo(index)
                end
            end
            local label = ident and select(2, GetSpecializationInfoByID(ident))
            return ident, label or UNKNOWN
        end

        local function IsCurrent(pendingRequest)
            local widget = BonusRollFrame
            return isActive
                and Enabled()
                and widget
                and widget:IsShown()
                and widget.state == "prompt"
                and widget.spellID == pendingRequest.spellID
                and widget.endTime == pendingRequest.endTime
                and (widget.remaining or 0) > 0
                and pendingRequest.button:IsShown()
                and pendingRequest.button:IsEnabled()
                and not pendingRequest.button:IsProtected()
                and pendingRequest.button:GetScript("OnClick") == pendingRequest.handler
                and (not pendingRequest.isRoll or pendingRequest.specID == LootSpec())
        end

        local function Click(forRoll, btnFrame, mouseButton, down)
            if not isActive or not Enabled() then
                return
            end
            Invalidate()
            local widget = BonusRollFrame
            if not widget then
                return
            end
            local specID, specName = LootSpec()
            local pendingRequest = {
                spellID = widget.spellID,
                endTime = widget.endTime,
                specID = specID,
                isRoll = forRoll,
                button = btnFrame,
                handler = btnFrame:GetScript("OnClick"),
            }
            if not IsCurrent(pendingRequest) then
                return
            end
            pendingRequest.cancel = function()
                if waiting == pendingRequest then
                    waiting = nil
                end
            end
            waiting = pendingRequest
            pendingRequest.handle = CludesUI:ShowConfirmPopup({
                title = CludesUI.L("Bonus Roll Confirmation"),
                message = forRoll and CludesUI.L("Use a bonus roll?")
                    or CludesUI.L("Pass on this bonus roll?"),
                disclaimer = forRoll and CludesUI.Lf("Loot specialization: %s", specName) or nil,
                confirmText = forRoll and ROLL or PASS,
                cancelText = CANCEL,
                onCancel = pendingRequest.cancel,
                onConfirm = function()
                    if waiting ~= pendingRequest then
                        return
                    end
                    local valid = IsCurrent(pendingRequest)
                    Invalidate()
                    if valid then
                        btnFrame:Click(mouseButton, down)
                    end
                end,
            })
        end

        local function SyncOverlays()
            if not rollCover then
                return
            end
            local widget = BonusRollFrame
            local shouldShow = isActive and Enabled() and widget and widget:IsShown() and widget.state == "prompt"
            rollCover:SetShown(shouldShow and true or false)
            passCover:SetShown(shouldShow and CludesUIDB.bonusRollOnly == false or false)
        end

        local function MakeOverlay(btnFrame, forRoll)
            local overlayFrame = CreateFrame("Button", nil, btnFrame)
            overlayFrame:SetAllPoints(btnFrame)
            overlayFrame:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
            overlayFrame:RegisterForClicks("LeftButtonUp")
            overlayFrame:SetScript("OnClick", function(_, mouseButton, down)
                Click(forRoll, btnFrame, mouseButton, down)
            end)
            overlayFrame:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, forRoll and ROLL or PASS)
            end)
            overlayFrame:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            overlayFrame:Hide()
            return overlayFrame
        end

        local function Install()
            if rollBtn then
                SyncOverlays()
                return
            end
            local widget = BonusRollFrame
            local promptFrame = widget and widget.PromptFrame
            local roll, pass = promptFrame and promptFrame.RollButton, promptFrame and promptFrame.PassButton
            if not roll or not pass or roll:IsProtected() or pass:IsProtected() then
                return
            end
            if not roll:GetScript("OnClick") or not pass:GetScript("OnClick") then
                return
            end
            rollBtn, passBtn = roll, pass
            rollCover = MakeOverlay(roll, true)
            passCover = MakeOverlay(pass, false)
            if not lifecycleHooked then
                lifecycleHooked = true
                local function Changed()
                    if isActive then
                        Invalidate()
                        SyncOverlays()
                    end
                end
                -- Secure post-hooks only: every prompt opens and closes through
                -- these two (plus the events below). A script hook on the frame
                -- would leave the rest of Blizzard's loot-container layout, which
                -- hides it, running under our taint.
                hooksecurefunc("BonusRollFrame_StartBonusRoll", Changed)
                hooksecurefunc("BonusRollFrame_CloseBonusRoll", Changed)
            end
            SyncOverlays()
        end

        local function Apply()
            Invalidate()
            isActive = Enabled()
            if not isActive then
                SyncOverlays()
                if eventWatcher then
                    eventWatcher:UnregisterAllEvents()
                end
                return
            end
            if not eventWatcher then
                eventWatcher = CreateFrame("Frame")
                eventWatcher:SetScript("OnEvent", function(_, eventName, addonName)
                    if eventName == "ADDON_LOADED" then
                        if addonName == "BonusRollConfirm" or not rollBtn then
                            CludesUI._applyBonusRollConfirmation()
                        end
                    else
                        Invalidate()
                        SyncOverlays()
                    end
                end)
            end
            eventWatcher:RegisterEvent("ADDON_LOADED")
            eventWatcher:RegisterEvent("BONUS_ROLL_STARTED")
            eventWatcher:RegisterEvent("BONUS_ROLL_FAILED")
            eventWatcher:RegisterEvent("BONUS_ROLL_RESULT")
            eventWatcher:RegisterEvent("BONUS_ROLL_DEACTIVATE")
            eventWatcher:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
            eventWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            Install()
        end
        CludesUI._applyBonusRollConfirmation = Apply
        Apply()
    end

    ---------------------------------------------------------------------------
    --  Auto Unwrap Collections (Mounts / Pets / Toys)
    ---------------------------------------------------------------------------
    do
        local busy = false

        -- Walks all mount IDs so journal filters cannot hide a pending mount.
        local function AckMountAlerts()
            if not C_MountJournal then
                return false
            end
            local waiting = C_MountJournal.GetNumMountsNeedingFanfare
                and C_MountJournal.GetNumMountsNeedingFanfare()
            if not waiting or waiting <= 0 then
                return false
            end

            for _, ident in ipairs(C_MountJournal.GetMountIDs()) do
                if C_MountJournal.NeedsFanfare(ident) then
                    C_MountJournal.ClearFanfare(ident)
                    waiting = waiting - 1
                    if waiting == 0 then
                        break
                    end
                end
            end
            return true
        end

        local function AckPetAlerts()
            if not C_PetJournal or not C_PetJournal.GetNumPetsNeedingFanfare then
                return false
            end
            if (C_PetJournal.GetNumPetsNeedingFanfare() or 0) == 0 then
                return false
            end
            local anyFound = false
            for _, ident in ipairs(C_PetJournal.GetOwnedPetIDs and C_PetJournal.GetOwnedPetIDs() or {}) do
                if ident and C_PetJournal.PetNeedsFanfare and C_PetJournal.PetNeedsFanfare(ident) then
                    if C_PetJournal.ClearFanfare then
                        C_PetJournal.ClearFanfare(ident)
                    end
                    anyFound = true
                end
            end
            return anyFound
        end

        local function AckToyAlerts()
            if not C_ToyBoxInfo or not C_ToyBoxInfo.ClearFanfare then
                return false
            end
            local anyFound = false
            if ToyBox and ToyBox.fanfareToys then
                for ident, needs in pairs(ToyBox.fanfareToys) do
                    if needs and ident and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(ident) then
                        C_ToyBoxInfo.ClearFanfare(ident)
                        anyFound = true
                    end
                end
                if anyFound then
                    return true
                end
            end
            if C_ToyBox and C_ToyBox.GetNumToys and C_ToyBox.GetToyFromIndex then
                for i = 1, C_ToyBox.GetNumToys() do
                    local ident = C_ToyBox.GetToyFromIndex(i)
                    if ident and C_ToyBoxInfo.NeedsFanfare and C_ToyBoxInfo.NeedsFanfare(ident) then
                        C_ToyBoxInfo.ClearFanfare(ident)
                        anyFound = true
                    end
                end
            end
            return anyFound
        end

        local function DismissCollectionAlerts()
            if not (CludesUIDB and CludesUIDB.autoUnwrapCollections) then
                return
            end
            if busy then
                return
            end
            busy = true
            -- Fanfare only: calling the micro button alert functions from here
            -- taints them and blocks SetAvatarTexture in the Communities list.
            C_Timer.After(0.2, function()
                busy = false
                local mounts = AckMountAlerts()
                local pets = AckPetAlerts()
                if not (mounts or pets) then
                    AckToyAlerts()
                end
            end)
        end

        -- Runs during PLAYER_LOGIN, before Blizzard's PLAYER_ENTERING_WORLD
        -- check, so the Collections button does not raise the unopened alert.
        if CludesUIDB and CludesUIDB.autoUnwrapCollections then
            AckMountAlerts()
            AckPetAlerts()
        end

        hooksecurefunc("MainMenuMicroButton_ShowAlert", function(_, textValue)
            if not (CludesUIDB and CludesUIDB.autoUnwrapCollections) then
                return
            end
            if textValue == COLLECTION_UNOPENED_PLURAL or textValue == COLLECTION_UNOPENED_SINGULAR then
                DismissCollectionAlerts()
            end
        end)

        -- The collection events are registered only while the option is on.
        local frame = CreateFrame("Frame")
        local function SyncUnwrapEvents()
            local isEnabled = CludesUIDB and CludesUIDB.autoUnwrapCollections
            if isEnabled then
                frame:RegisterEvent("NEW_MOUNT_ADDED")
                frame:RegisterEvent("NEW_PET_ADDED")
                frame:RegisterEvent("NEW_TOY_ADDED")
            else
                frame:UnregisterEvent("NEW_MOUNT_ADDED")
                frame:UnregisterEvent("NEW_PET_ADDED")
                frame:UnregisterEvent("NEW_TOY_ADDED")
            end
            return isEnabled
        end
        -- The options toggle: switching on also unwraps what is already pending.
        CludesUI._applyAutoUnwrap = function()
            if SyncUnwrapEvents() then
                DismissCollectionAlerts()
            end
        end
        if SyncUnwrapEvents() then
            frame:RegisterEvent("PLAYER_LOGIN")
        end
        frame:SetScript("OnEvent", function(self, eventName)
            if eventName == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                -- Defer 3s so ToyBox.fanfareToys exists (avoids a 1000+ toy full scan at login)
                C_Timer.After(3, DismissCollectionAlerts)
                return
            end
            DismissCollectionAlerts()
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Open Containers (incremental cache -- no login spike)
    ---------------------------------------------------------------------------
    do
        local _openableCache = {} -- itemID -> true/false
        local _failedItems = {} -- itemID -> true (failed to open, skip forever)
        local _cacheBuilt = false
        -- In-flight opens keyed by bag/slot, set synchronously in the same tick as
        -- UseContainerItem (Lua is single-threaded, so no other pass can slip in) and
        -- cleared at the 0.5s recheck (Blizzard's isLocked isn't set until the round-trip completes) -- stops a double-use stranding a slot.
        local _openInProgress = {}
        -- Payout containers open a loot window and linger until looted; any open while up strands them. Gate on this; resume on LOOT_CLOSED.
        local _lootOpen = false
        -- Attribution for loot windows our opens spawn: _pendingOpen is stamped
        -- before UseContainerItem, cleared at the 0.5s recheck; LOOT_OPENED captures
        -- it into _lootSource. On close, still sitting with an un-decremented count
        -- means it couldn't be looted (bags full/unique cap), so it's skipped for the session (reload retries once space frees).
        local _pendingOpen, _lootSource
        -- Global single-flight: only one open cycle at a time. Per-slot _openInProgress
        -- isn't enough -- a payout container's lock latency outlasts its 0.5s window, so a second chain could reuse and strand it.
        local _openBusy = false
        local _scanScheduled = false
        -- Cycle generation: bumped on cycle start AND disable. Every deferred closure
        -- captures its own generation and self-aborts when stale -- IsEnabled() alone
        -- isn't enough since a disable->re-enable inside the recheck window would resurrect the old chain alongside the new one.
        local _cycleGen = 0
        -- A scan request arrived while busy; finish() honors it even with no progress.
        local _missedScan = false
        -- Pacing: mail's "Open All" lands many items within one second, exactly
        -- when our action can collide with another still resolving and strand a
        -- slot locked until relog -- the client optimistically locks on any action,
        -- clearing only once the server confirms. _lastBagChurn = GetTime() of the
        -- most recent raw BAG_UPDATE (real-time signal; coalesced BAG_UPDATE_DELAYED is too coarse).
        local _lastBagChurn = 0
        local CHURN_SETTLE_WINDOW = 0.35 -- "recent" churn cutoff, seconds
        local CHURN_SETTLE_DELAY = 0.4 -- extra wait when churn was recent
        local function AODbg(...)
            if CludesUI._AODEBUG then
                print("|cff33ff99[AutoOpen]|r", ...)
            end
        end
        -- Forward-declared: scanFrame's OnUpdate calls ScanAndOpen once cache is built, so both must be in-scope upvalues (assigned further down).
        local ScanAndOpen, RequestScan
        local function SlotKey(bagId, slotId)
            return bagId * 1000 + slotId
        end
        local function IsEnabled()
            return CludesUIDB and CludesUIDB.autoOpenContainers == true
        end
        -- This payout can award this capped currency; hold only the known pair.
        local ARTISAN_PAYOUT_ITEM_ID = 246585
        local SHARD_OF_DUNDUN_CURRENCY_ID = 3376
        local function ShouldHoldCappedArtisanPayout(itemId)
            if
                itemId ~= ARTISAN_PAYOUT_ITEM_ID
                or not (CludesUIDB and CludesUIDB.autoOpenContainersHoldCappedArtisanPayouts == true)
            then
                return false
            end
            return C_CurrencyInfo
                    and C_CurrencyInfo.PlayerHasMaxQuantity
                    and C_CurrencyInfo.PlayerHasMaxQuantity(SHARD_OF_DUNDUN_CURRENCY_ID)
                or false
        end
        -- An open merchant turns UseContainerItem into a SELL, so auto-open pauses
        -- while any merchant frame is shown, or bought containers get vendored /
        -- non-openables throw an error. Re-checked per open; re-runs on MERCHANT_CLOSED.
        local function MerchantOpen()
            return (MerchantFrame and MerchantFrame:IsShown()) and true or false
        end
        -- Same reasoning as MerchantOpen: opening while the mailbox is up compounds
        -- the strand-a-slot race with mail's own item delivery. Interaction state,
        -- not frame visibility: third-party mail/bank UIs hide the stock frames,
        -- but the server-tracked interaction is true at the mailbox/banker
        -- regardless of what draws the window.
        local function MailOpen()
            return (
                C_PlayerInteractionManager
                and C_PlayerInteractionManager.IsInteractingWithNpcOfType
                and C_PlayerInteractionManager.IsInteractingWithNpcOfType(Enum.PlayerInteractionType.MailInfo)
            )
                    and true
                or false
        end
        local function BankOpen()
            if not (C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType) then
                return false
            end
            -- Both bank types: character banker and the warband (account) bank.
            local PIT, IsAt =
                Enum.PlayerInteractionType, C_PlayerInteractionManager.IsInteractingWithNpcOfType
            -- some bankers open the character bank as CharacterBanker
            return (
                IsAt(PIT.Banker)
                or (PIT.CharacterBanker and IsAt(PIT.CharacterBanker))
                or IsAt(PIT.AccountBanker)
            )
                    and true
                or false
        end
        -- "Exclude Warbound Containers": checks the item's own bind type
        -- instead of asking the bank if it would accept a deposit right now --
        -- that answer needs a live bank session and defaults to "no" outdoors,
        -- which let warbound items open anyway. Bind type works anywhere.
        local WARBOUND_BIND_TYPES = {
            [Enum.ItemBind.ToWoWAccount] = true,
            [Enum.ItemBind.ToBnetAccount] = true,
            [Enum.ItemBind.ToBnetAccountUntilEquipped] = true,
        }
        local function IsWarboundExcluded(bagId, slotId)
            -- Default ON (unset behaves as enabled, matching the options UI's
            -- checked-by-default display); only explicit false disables it -- `not value` would wrongly let nil skip the exclusion.
            if not CludesUIDB or CludesUIDB.autoOpenContainersExcludeWarbound == false then
                return false
            end
            if not (C_Container and C_Container.GetContainerItemInfo and C_Item and C_Item.GetItemInfo) then
                return false
            end
            local details = C_Container.GetContainerItemInfo(bagId, slotId)
            if not (details and details.itemID) then
                return false
            end
            local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(details.itemID)
            -- Item data not cached yet: fail CLOSED (skip this pass; the scan
            -- re-checks once the data lands) so a warbound container is never
            -- opened just because its bind type was not known yet.
            if not bindType then
                return true
            end
            if WARBOUND_BIND_TYPES[bindType] == true then
                return true
            end
            -- Warbound Until Equipped containers report bindType == OnEquip, same as
            -- an ordinary BoE item (no dedicated GetItemInfo enum value -- see
            -- CUI_Bags.SetBindTypeText's "WuE items report bindType == OnEquip"), so
            -- ToBnetAccountUntilEquipped above never actually matches one. The item's
            -- own bound-until-equip flag is the only reliable signal.
            if bindType == Enum.ItemBind.OnEquip and ItemLocation and C_Item.IsBoundToAccountUntilEquip then
                local location = ItemLocation:CreateFromBagAndSlot(bagId, slotId)
                if location and C_Item.DoesItemExist(location) then
                    return C_Item.IsBoundToAccountUntilEquip(location) == true
                end
            end
            return false
        end
        local SLOTS_PER_FRAME = 3 -- check 3 slots per OnUpdate tick

        local function IsOpenableByID(itemId, bagId, slotId)
            local cached = _openableCache[itemId]
            if cached ~= nil then
                return cached
            end
            local tipText = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bagId, slotId)
            if tipText and tipText.lines then
                for _, lineText in ipairs(tipText.lines) do
                    if lineText and lineText.leftText and lineText.leftText == ITEM_OPENABLE then
                        _openableCache[itemId] = true
                        return true
                    end
                end
            end
            -- A brand-new item's data can still be loading server-side when
            -- this first check runs, so an empty tooltip here doesn't mean
            -- "not openable" -- it can just mean "not loaded yet". Only cache
            -- the negative once the item's data is actually in, so a real
            -- negative sticks but an early miss gets rechecked on the next scan.
            if C_Item and C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemId) then
                return false
            end
            _openableCache[itemId] = false
            return false
        end

        -- Incremental scanner: SLOTS_PER_FRAME slots per tick; hides itself once
        -- all bags are scanned (zero CPU when idle).
        local _scanBag = BACKPACK_CONTAINER
        local _scanSlot = 1

        local scanHost = CreateFrame("Frame")
        scanHost:Hide()
        scanHost:SetScript("OnUpdate", function(self)
            if not IsEnabled() then
                self:Hide()
                return
            end
            local checkedCount = 0
            while checkedCount < SLOTS_PER_FRAME do
                local numSlots = C_Container.GetContainerNumSlots(_scanBag)
                if _scanSlot > numSlots then
                    _scanBag = _scanBag + 1
                    _scanSlot = 1
                    if _scanBag > NUM_BAG_SLOTS then
                        -- Cache warm: hand off to the open cycle, which re-scans itself.
                        _cacheBuilt = true
                        self:Hide()
                        if ScanAndOpen then
                            ScanAndOpen(false)
                        end
                        return
                    end
                else
                    local details = C_Container.GetContainerItemInfo(_scanBag, _scanSlot)
                    if details and details.itemID then
                        -- Warm here so the open cycle never tooltip-scans on its hot path.
                        IsOpenableByID(details.itemID, _scanBag, _scanSlot)
                    end
                    _scanSlot = _scanSlot + 1
                    checkedCount = checkedCount + 1
                end
            end
        end)

        -- After cache is built, BAG_UPDATE_DELAYED only checks changed slots
        local holder = CreateFrame("Frame")

        -- Live apply: registers bag listeners and (until cache exists) runs the
        -- incremental scan; disable stops it. Called at login and from the toggle.
        CludesUI._applyAutoOpenContainers = function()
            if IsEnabled() then
                holder:RegisterEvent("BAG_UPDATE_DELAYED")
                -- Raw per-slot event, far more frequent than the coalesced DELAYED one; used ONLY to timestamp _lastBagChurn, no scan work here.
                holder:RegisterEvent("BAG_UPDATE")
                -- Re-run on vendor close: a purchase's BAG_UPDATE_DELAYED fires
                -- while opens are suppressed, so bought containers would never open.
                holder:RegisterEvent("MERCHANT_CLOSED")
                -- MailOpen() is read at every entry point so the pause needs no event;
                -- MAIL_CLOSED no longer fires on retail (kept for older clients) -- interaction-manager HIDE drives resume.
                holder:RegisterEvent("MAIL_CLOSED")
                holder:RegisterEvent("BANKFRAME_CLOSED")
                if C_PlayerInteractionManager then
                    holder:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
                end
                -- Loot window tracking (see _lootOpen).
                holder:RegisterEvent("LOOT_OPENED")
                holder:RegisterEvent("LOOT_CLOSED")
                if
                    CludesUIDB.autoOpenContainersHoldCappedArtisanPayouts == true
                    and C_CurrencyInfo
                    and C_CurrencyInfo.PlayerHasMaxQuantity
                then
                    holder:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
                else
                    holder:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
                end
                -- Resume opens deferred while casting, else the deferral stalls until the next bag update.
                holder:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
                holder:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
                holder:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
                if not _cacheBuilt then
                    _scanBag = BACKPACK_CONTAINER
                    _scanSlot = 1
                    scanHost:Show()
                elseif RequestScan then
                    RequestScan()
                end
            else
                holder:UnregisterEvent("BAG_UPDATE_DELAYED")
                holder:UnregisterEvent("BAG_UPDATE")
                holder:UnregisterEvent("MERCHANT_CLOSED")
                holder:UnregisterEvent("MAIL_CLOSED")
                holder:UnregisterEvent("BANKFRAME_CLOSED")
                if C_PlayerInteractionManager then
                    holder:UnregisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
                end
                holder:UnregisterEvent("LOOT_OPENED")
                holder:UnregisterEvent("LOOT_CLOSED")
                holder:UnregisterEvent("CURRENCY_DISPLAY_UPDATE")
                holder:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
                holder:UnregisterEvent("UNIT_SPELLCAST_STOP")
                holder:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
                _lootOpen = false
                _pendingOpen = nil
                _lootSource = nil
                -- Clears single-flight state so a mid-cycle disable can't strand
                -- _openBusy; the generation bump kills in-flight timers so a quick re-enable can't resurrect the old chain.
                _openBusy = false
                _scanScheduled = false
                _missedScan = false
                _cycleGen = _cycleGen + 1
                scanHost:Hide()
            end
        end

        -- Initial kick 2s after login (bags need a moment to settle)
        C_Timer.After(2, function()
            if IsEnabled() then
                CludesUI._applyAutoOpenContainers()
            end
        end)
        -- skipMerchantGate: MERCHANT_CLOSED's re-run fires before MerchantFrame
        -- finishes hiding, so its entry check would misread "merchant open" and bail;
        -- that run skips only THIS gate -- safety comes from the 0.15s pre-open delay plus the per-step MerchantOpen() re-check.
        --
        -- Single-flight open cycle: build the candidate list, open one container at a
        -- time, re-scan once IF anything progressed when exhausted (subsumes nested
        -- containers and lingering payout containers, no second concurrent chain).
        -- _openBusy guards the whole cycle. UseContainerItem silently CANCELS the
        -- player's cast (engine treats it as interrupting), eating mounts/ports/hardcasts
        -- with no error -- a cast is transient, so defer rather than blacklist: the spellcast events above resume the cycle.
        local function PlayerIsCasting()
            return (UnitCastingInfo and UnitCastingInfo("player") ~= nil)
                or (UnitChannelInfo and UnitChannelInfo("player") ~= nil)
        end

        -- skipMailGate: MAIL_CLOSED/interaction-manager hide already settle 0.5s
        -- below, so MailOpen() is reliably false by then -- belt and suspenders, not load-bearing like skipMerchantGate.
        ScanAndOpen = function(skipMerchantGate, skipMailGate, skipBankGate)
            if not _cacheBuilt then
                return
            end
            if not IsEnabled() then
                return
            end
            if InCombatLockdown() then
                return
            end
            if not skipMerchantGate and MerchantOpen() then
                return
            end
            if not skipMailGate and MailOpen() then
                return
            end
            if not skipBankGate and BankOpen() then
                return
            end
            if PlayerIsCasting() then
                _missedScan = true
                return
            end
            -- Loot window up: LOOT_CLOSED restarts once the payout container leaves the bag.
            if _lootOpen then
                return
            end
            -- A running cycle's finish() re-scan picks up this trigger.
            if _openBusy then
                return
            end

            local toOpen = {}
            for bagId = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                for slotId = 1, C_Container.GetContainerNumSlots(bagId) do
                    local details = C_Container.GetContainerItemInfo(bagId, slotId)
                    if details and details.itemID then
                        -- Only tooltip-check uncached items (new loot)
                        if _openableCache[details.itemID] == nil then
                            IsOpenableByID(details.itemID, bagId, slotId)
                        end
                        if _openableCache[details.itemID] and not _failedItems[details.itemID] then
                            toOpen[#toOpen + 1] = { bag = bagId, slot = slotId }
                        end
                    end
                end
            end
            if #toOpen == 0 then
                return
            end

            _openBusy = true
            _cycleGen = _cycleGen + 1
            local myGen = _cycleGen
            local madeProgress = false
            AODbg(("cycle start: %d candidate(s)"):format(#toOpen))

            -- Only place _openBusy is cleared; every step() exit routes here so it
            -- can't leak (freezes auto-open until reload). A stale generation must NOT clear it -- belongs to the new cycle.
            local function finish()
                if myGen ~= _cycleGen then
                    return
                end
                _openBusy = false
                if
                    (madeProgress or _missedScan)
                    and IsEnabled()
                    and not InCombatLockdown()
                    and not MerchantOpen()
                    and not MailOpen()
                    and not BankOpen()
                    and not _lootOpen
                then
                    _missedScan = false
                    C_Timer.After(0.3, function()
                        ScanAndOpen(false, false, false)
                    end)
                end
            end

            local PaceNext -- forward-declared: assigned after step, below
            local function step(position)
                if myGen ~= _cycleGen then
                    return
                end
                if position > #toOpen then
                    return finish()
                end
                if not IsEnabled() or InCombatLockdown() or MerchantOpen() or MailOpen() or BankOpen() then
                    return finish()
                end
                -- Re-checked per step: the cycle paces itself across seconds of timers, so a cast can start long after the entry gate passed.
                if PlayerIsCasting() then
                    _missedScan = true
                    return finish()
                end
                -- Loot window opened mid-cycle: stop; LOOT_CLOSED restarts cleanly.
                if _lootOpen then
                    return finish()
                end
                local entry = toOpen[position]
                local settingKey = SlotKey(entry.bag, entry.slot)
                local details = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
                -- Never act on a slot mid-action (_openInProgress, or Blizzard's isLocked): reusing a still-resolving container strands it.
                if details and details.itemID and not details.isLocked and not _openInProgress[settingKey] then
                    if
                        IsWarboundExcluded(entry.bag, entry.slot)
                        or ShouldHoldCappedArtisanPayout(details.itemID)
                    then
                        return step(position + 1)
                    end
                    if _openableCache[details.itemID] and not _failedItems[details.itemID] then
                        local prevID = details.itemID
                        local prevCount = details.stackCount or 1
                        _openInProgress[settingKey] = true
                        _pendingOpen = {
                            bag = entry.bag,
                            slot = entry.slot,
                            itemID = prevID,
                            count = prevCount,
                        }
                        AODbg(("open bag=%d slot=%d item=%d"):format(entry.bag, entry.slot, prevID))
                        C_Container.UseContainerItem(entry.bag, entry.slot)
                        C_Timer.After(0.5, function()
                            -- Always release the slot flag; a stale-generation chain
                            -- stops here since its verdict would race the cycle that replaced it.
                            _openInProgress[settingKey] = nil
                            -- No loot window claimed this open by now: drop the attribution so an unrelated later window can't inherit it.
                            if
                                _pendingOpen
                                and _pendingOpen.bag == entry.bag
                                and _pendingOpen.slot == entry.slot
                            then
                                _pendingOpen = nil
                            end
                            if myGen ~= _cycleGen then
                                return
                            end
                            local after = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
                            local progressed = not after
                                or after.itemID ~= prevID
                                or (after.stackCount or 1) < prevCount
                            if progressed then
                                madeProgress = true
                            elseif
                                after
                                and after.itemID == prevID
                                and not after.isLocked
                                and not _lootOpen
                            then
                                -- Unchanged, unlocked, no loot window => genuine failure.
                                -- A still-locked slot is just slow, so it's left uncached for a later retry.
                                _failedItems[prevID] = true
                                AODbg("genuine fail, item=" .. prevID)
                            end
                            -- A real open resolved: pace before advancing. Non-actionable skips above advance unpaced.
                            PaceNext(position + 1)
                        end)
                        return
                    end
                end
                C_Timer.After(0.1, function()
                    step(position + 1)
                end)
            end

            -- Paces the step AFTER a real open resolves: if something else just touched
            -- the bags (e.g. Blizzard's item delivery), let it settle first. Mailbox is covered separately (pause while open, settle after close).
            PaceNext = function(position)
                if myGen ~= _cycleGen then
                    return
                end
                local extra, why = 0, nil
                if GetTime() - _lastBagChurn < CHURN_SETTLE_WINDOW then
                    extra, why = CHURN_SETTLE_DELAY, "churn"
                end
                if extra > 0 then
                    AODbg(("pacing +%.1fs (%s)"):format(extra, why))
                    C_Timer.After(extra, function()
                        step(position)
                    end)
                else
                    step(position)
                end
            end

            C_Timer.After(0.15, function()
                step(1)
            end)
        end

        -- Coalesce a burst of BAG_UPDATE_DELAYED (a single open fires several) into one next-frame scan; skips while a cycle is in flight.
        RequestScan = function()
            -- Dropped mid-cycle: remembered so finish() re-scans even with no progress.
            if _openBusy then
                _missedScan = true
                return
            end
            if _scanScheduled then
                return
            end
            _scanScheduled = true
            C_Timer.After(0, function()
                _scanScheduled = false
                ScanAndOpen(false)
            end)
        end

        holder:SetScript("OnEvent", function(_, eventName, interactionType)
            if eventName == "BAG_UPDATE" then
                _lastBagChurn = GetTime()
                return
            end
            if eventName == "LOOT_OPENED" then
                _lootOpen = true
                -- Claim the window for the container just used, so LOOT_CLOSED knows which slot to re-examine.
                _lootSource = _pendingOpen
                _pendingOpen = nil
                return
            end
            if eventName == "LOOT_CLOSED" then
                _lootOpen = false
                -- Delay lets the looted container leave the bag before the re-scan.
                C_Timer.After(0.5, function()
                    -- Verdict on the container that spawned this window: still there with
                    -- an un-decremented count means it couldn't be looted (bags full/unique
                    -- cap) -- skip it BEFORE re-scan or it loops forever; a locked slot (in-flight) gets no verdict.
                    local src = _lootSource
                    _lootSource = nil
                    if src then
                        local nowTime = C_Container.GetContainerItemInfo(src.bag, src.slot)
                        if
                            nowTime
                            and nowTime.itemID == src.itemID
                            and not nowTime.isLocked
                            and (nowTime.stackCount or 1) >= src.count
                        then
                            _failedItems[src.itemID] = true
                        end
                    end
                    ScanAndOpen(false)
                end)
                return
            end
            if eventName == "BAG_UPDATE_DELAYED" then
                RequestScan()
                return
            end
            if eventName == "CURRENCY_DISPLAY_UPDATE" then
                if not ShouldHoldCappedArtisanPayout(ARTISAN_PAYOUT_ITEM_ID) then
                    RequestScan()
                end
                return
            end
            if
                eventName == "UNIT_SPELLCAST_SUCCEEDED"
                or eventName == "UNIT_SPELLCAST_STOP"
                or eventName == "UNIT_SPELLCAST_CHANNEL_STOP"
            then
                -- Resume only when the casting gate actually deferred work -- these fire on every instant cast too, and walking bags each time would be constant overhead.
                if _missedScan and not _openBusy then
                    _missedScan = false
                    C_Timer.After(0.1, function()
                        ScanAndOpen(false, false)
                    end)
                end
                return
            end
            if eventName == "BANKFRAME_CLOSED" then
                -- Legacy path like MAIL_CLOSED below; the interaction-manager
                -- HIDE below is the live driver on retail.
                C_Timer.After(0.5, function()
                    ScanAndOpen(false, false, true)
                end)
                return
            end
            if eventName == "MAIL_CLOSED" then
                -- Legacy, doesn't fire on retail (kept for older clients).
                C_Timer.After(0.5, function()
                    ScanAndOpen(false, true, false)
                end)
                return
            end
            if eventName == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
                if interactionType == Enum.PlayerInteractionType.MailInfo then
                    -- The event that actually fires on retail; mail's own delivery can still unlock slots just after close, so settle first like LOOT_CLOSED.
                    C_Timer.After(0.5, function()
                        ScanAndOpen(false, true, false)
                    end)
                elseif
                    interactionType == Enum.PlayerInteractionType.Banker
                    or interactionType == Enum.PlayerInteractionType.CharacterBanker
                    or interactionType == Enum.PlayerInteractionType.AccountBanker
                then
                    -- AccountBanker: the warband bank signals its own type, and
                    -- BankOpen() gates both (same BankFrame).
                    C_Timer.After(0.5, function()
                        ScanAndOpen(false, false, true)
                    end)
                end
                return
            end
            -- MERCHANT_CLOSED: interaction's over but the frame may not have hidden yet, so skip the entry gate instead of a timer.
            ScanAndOpen(eventName == "MERCHANT_CLOSED")
        end)
    end

    ---------------------------------------------------------------------------
    --  Hide Screenshot Status
    ---------------------------------------------------------------------------
    do
        local isHooked = false

        local function HideActionStatus()
            local actionStatus = _G.ActionStatus
            if actionStatus then
                actionStatus:Hide()
            end
        end

        local function ApplyScreenshotStatus()
            -- ActionStatus is lazy-created by Blizzard on the first screenshot
            -- event; ssFrame below hides it right after Blizzard shows it.
        end

        CludesUI._applyScreenshotStatus = ApplyScreenshotStatus

        local screenshotHost = CreateFrame("Frame")
        screenshotHost:RegisterEvent("SCREENSHOT_SUCCEEDED")
        screenshotHost:RegisterEvent("SCREENSHOT_FAILED")
        screenshotHost:SetScript("OnEvent", function()
            if not CludesUIDB or CludesUIDB.hideScreenshotStatus ~= false then
                -- Hide on next frame so Blizzard's handler runs first
                C_Timer.After(0, HideActionStatus)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Train All Button
    ---------------------------------------------------------------------------
    do
        local trainButton = nil
        local isHooked = false

        local function FreeProfessionSlots()
            if not GetProfessions then
                return 2
            end
            local a, b = GetProfessions()
            return 2 - (a and 1 or 0) - (b and 1 or 0)
        end

        -- Purchasable given current funds/slots? Returns ok, cost, takesProfSlot.
        local function SkillIsAffordable(i, wallet, freeSlots)
            if not GetTrainerServiceInfo or not GetTrainerServiceCost then
                return false, 0, false
            end
            local _, kind = GetTrainerServiceInfo(i)
            if kind ~= "available" then
                return false, 0, false
            end
            local repairCost, takesProfSlot = GetTrainerServiceCost(i)
            repairCost = repairCost or 0
            if repairCost > wallet then
                return false, 0, false
            end
            if takesProfSlot and freeSlots <= 0 then
                return false, 0, false
            end
            return true, repairCost, takesProfSlot
        end

        local function TrainableSummary()
            if not GetNumTrainerServices then
                return 0, 0
            end
            local num, gold = 0, 0
            local wallet = GetMoney and GetMoney() or 0
            local slots = FreeProfessionSlots()
            for i = 1, GetNumTrainerServices() do
                local ok, repairCost = SkillIsAffordable(i, wallet, slots)
                if ok then
                    num = num + 1
                    gold = gold + repairCost
                end
            end
            return num, gold
        end

        local function RefreshButton()
            if not trainButton then
                return
            end
            if not (CludesUIDB and CludesUIDB.trainAllButton) then
                trainButton:Hide()
                return
            end
            local num = TrainableSummary()
            trainButton:SetEnabled(num > 0)
            trainButton:Show()
        end

        local function SpawnButton()
            if not (CludesUIDB and CludesUIDB.trainAllButton) then
                return
            end
            if not ClassTrainerFrame or not ClassTrainerTrainButton then
                return
            end
            if trainButton then
                trainButton:Show()
                RefreshButton()
                return
            end

            trainButton = CreateFrame("Button", "CUI_TrainAllButton", ClassTrainerFrame, "MagicButtonTemplate")
            trainButton:SetText("Train All")
            trainButton:SetHeight(ClassTrainerTrainButton:GetHeight() or 22)
            trainButton:SetWidth(80)
            trainButton:SetPoint("RIGHT", ClassTrainerTrainButton, "LEFT", -2, 0)

            trainButton:SetScript("OnClick", function()
                local wallet = GetMoney and GetMoney() or 0
                local slots = FreeProfessionSlots()
                -- Descending: a purchase reindexes the list, so only already-
                -- visited (higher) indices shift and no skill is skipped.
                for i = GetNumTrainerServices(), 1, -1 do
                    local ok, repairCost, takesProfSlot = SkillIsAffordable(i, wallet, slots)
                    if ok then
                        BuyTrainerService(i)
                        wallet = wallet - repairCost
                        if takesProfSlot then
                            slots = slots - 1
                        end
                    end
                end
            end)

            trainButton:SetScript("OnEnter", function(self)
                local num, gold = TrainableSummary()
                if num <= 0 then
                    return
                end
                local goldStr = C_CurrencyInfo.GetCoinTextureString(gold)
                local message = (num == 1) and CludesUI.Lf("Learn %1$d skill for %2$s", num, goldStr)
                    or CludesUI.Lf("Learn %1$d skills for %2$s", num, goldStr)
                CludesUI.ShowWidgetTooltip(self, message)
            end)
            trainButton:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            if not isHooked then
                hooksecurefunc("ClassTrainerFrame_Update", RefreshButton)
                isHooked = true
            end
            RefreshButton()
        end

        local function ApplyTrainAllButton()
            if CludesUIDB and CludesUIDB.trainAllButton then
                EventUtil.ContinueOnAddOnLoaded("Blizzard_TrainerUI", SpawnButton)
            elseif trainButton then
                trainButton:Hide()
            end
        end

        CludesUI._applyTrainAllButton = ApplyTrainAllButton

        local frame = CreateFrame("Frame")
        frame:RegisterEvent("PLAYER_LOGIN")
        frame:RegisterEvent("ADDON_LOADED")
        frame:SetScript("OnEvent", function(self, eventName, addonName)
            if eventName == "PLAYER_LOGIN" then
                self:UnregisterEvent("PLAYER_LOGIN")
                ApplyTrainAllButton()
            elseif eventName == "ADDON_LOADED" and addonName == "Blizzard_TrainerUI" then
                self:UnregisterEvent("ADDON_LOADED")
                ApplyTrainAllButton()
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  AH Current Expansion Only (not on WoW Forever: the block, its event and
    --  its options row do not exist there)
    ---------------------------------------------------------------------------
    if not CludesUI.IS_FOREVER then
        local ahFrame = CreateFrame("Frame")
        ahFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
        ahFrame:SetScript("OnEvent", function()
            if not (CludesUIDB and CludesUIDB.ahCurrentExpansion) then
                return
            end
            if not AuctionHouseFrame or not AuctionHouseFrame.SearchBar then
                return
            end
            C_Timer.After(0, function()
                local fallback = AuctionHouseFrame.SearchBar.FilterButton
                if not fallback or not fallback.GetFilters or not fallback.ToggleFilter then
                    return
                end
                if
                    not (Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.CurrentExpansionOnly)
                then
                    return
                end
                local filterEnum = Enum.AuctionHouseFilter.CurrentExpansionOnly
                local filters = fallback:GetFilters()
                -- The filter state is Blizzard's per-character saved table,
                -- reached only through the button's accessors (the button
                -- carries no filters field of its own). ToggleFilter flips the
                -- entry for the next query; toggling an already-set filter
                -- would switch it off, hence the read first.
                if not (filters and filters[filterEnum]) then
                    fallback:ToggleFilter(filterEnum)
                end
                if AuctionHouseFrame.SearchBar.UpdateClearFiltersButton then
                    AuctionHouseFrame.SearchBar:UpdateClearFiltersButton()
                end
            end)
        end)
        -- Uninstall CUI: while the option is on, this character's filter is ours, so it
        -- goes back off (Blizzard's default). Its saved table only exists once Blizzard's
        -- Auction House UI has loaded.
        CludesUI.OnUninstall(function()
            if not (CludesUIDB and CludesUIDB.ahCurrentExpansion) then
                return
            end
            local filterEnum = Enum
                and Enum.AuctionHouseFilter
                and Enum.AuctionHouseFilter.CurrentExpansionOnly
            if not filterEnum then
                return
            end
            if not C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
                C_AddOns.LoadAddOn("Blizzard_AuctionHouseUI")
            end
            local fallback = AuctionHouseFrame
                and AuctionHouseFrame.SearchBar
                and AuctionHouseFrame.SearchBar.FilterButton
            local filters = fallback and fallback.GetFilters and fallback:GetFilters()
            if filters and filters[filterEnum] then
                fallback:ToggleFilter(filterEnum)
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Sell Junk + Auto Repair
    ---------------------------------------------------------------------------
    -- Coin icons (opt-in via the Auto Repair cog) use the game's localized coin
    -- textures; default short text builds "12o 34a" from localized suffixes
    -- (L translates g/s -> o/a in frFR; copper "c" is untranslated).
    local function RepairCostString(repairCost)
        if CludesUIDB and CludesUIDB.repairCoinIcons then
            return C_CurrencyInfo.GetCoinTextureString(repairCost)
        end
        local g = floor(repairCost / 10000)
        local text = floor((repairCost % 10000) / 100)
        local c = repairCost % 100
        local out = ""
        if g > 0 then
            out = g .. CludesUI.L("g")
        end
        if text > 0 then
            out = out .. (out ~= "" and " " or "") .. text .. CludesUI.L("s")
        end
        if c > 0 then
            out = out .. (out ~= "" and " " or "") .. c .. CludesUI.L("c")
        end
        if out == "" then
            out = "0" .. CludesUI.L("c")
        end
        return out
    end

    -- Junk sweep. SellAllJunkItems() is fire-and-forget: the server drops sell
    -- requests past its rate limit, and uncached item data at MERCHANT_SHOW is
    -- skipped, so one call routinely strands grays -- re-count after each pass and
    -- fire again while still falling. Gated on MERCHANT_SHOW/CLOSED, not
    -- MerchantFrame:IsShown(): the interaction (not the frame) allows selling, and the frame may not be shown yet at MERCHANT_SHOW.
    local atMerchant = false
    local SellJunk, StopJunkSweep
    do
        -- Self-rescheduling timer, not a ticker: a fixed retry cadence against the
        -- same limiter that ate the pass just gets eaten again, so the delay backs off instead.
        local BASE_DELAY = 0.4
        local MAX_DELAY = 1.6
        local MAX_PASSES = 12
        local MAX_STALLS = 3
        local waiting, passes, lastCount, stallCount, warned, delay

        local function CountJunk()
            local junkTotal, unknown = 0, 0
            for bagId = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                for slotId = 1, C_Container.GetContainerNumSlots(bagId) do
                    local details = C_Container.GetContainerItemInfo(bagId, slotId)
                    if details and details.itemID then
                        if details.quality == nil then
                            unknown = unknown + 1
                        elseif details.quality == Enum.ItemQuality.Poor and not details.hasNoValue then
                            junkTotal = junkTotal + 1
                        end
                    end
                end
            end
            return junkTotal, unknown
        end

        StopJunkSweep = function()
            if waiting then
                waiting:Cancel()
                waiting = nil
            end
        end

        local Pass
        local function Schedule()
            waiting = C_Timer.NewTimer(delay, Pass)
        end

        -- Verify-and-report, no selling: the pass-cap exit's sell is still in flight, so only a re-count after the server answers says what stranded.
        local function Report()
            waiting = nil
            if not atMerchant then
                return
            end
            local leftX = CountJunk()
            if leftX > 0 and not warned then
                warned = true
                CludesUI.Print(
                    CludesUI.COLOR_CODES.BRAND
                        .. "CludesUI:|r "
                        .. CludesUI.Lf("%d junk item(s) could not be sold.", leftX)
                )
            end
        end

        Pass = function()
            waiting = nil
            if not atMerchant then
                return
            end
            if CludesUIDB and CludesUIDB.autoSellJunk == false then
                return
            end

            local junkTotal, unknown = CountJunk()
            if junkTotal == 0 and unknown == 0 then
                return
            end

            passes = passes + 1
            if junkTotal > lastCount then
                -- Count ROSE: uncached slots resolved into newly visible junk --
                -- discovery, not a stall (the case this sweep exists for).
                stallCount, delay = 0, BASE_DELAY
            elseif junkTotal == lastCount then
                -- Nothing shifted: either unsellable (refundable purchases open a
                -- confirm popup) or the limiter dropped the request -- indistinguishable, so back off before giving up.
                stallCount = stallCount + 1
                delay = math.min(delay * 2, MAX_DELAY)
                if stallCount >= MAX_STALLS then
                    if junkTotal > 0 and not warned then
                        warned = true
                        CludesUI.Print(
                            CludesUI.COLOR_CODES.BRAND
                                .. "CludesUI:|r "
                                .. CludesUI.Lf("%d junk item(s) could not be sold.", junkTotal)
                        )
                    end
                    return
                end
            else
                stallCount, delay = 0, BASE_DELAY
            end

            lastCount = junkTotal
            -- Only round-trip when there's something to sell; junk-free is just waiting on item data to cache.
            if junkTotal > 0 then
                C_MerchantFrame.SellAllJunkItems()
            end
            if passes >= MAX_PASSES then
                -- Cap hit while still moving; bailing silently is the exact failure this sweep fixes, so hand off one verification pass.
                waiting = C_Timer.NewTimer(delay, Report)
                return
            end
            Schedule()
        end

        SellJunk = function()
            -- Bags' Junk Marker on: sell what it calls junk (marked items, and
            -- greys not filed in another category) instead of every grey. The
            -- merchant is vouched for only while it is open: a sweep the repair
            -- watch held back can run after it closed.
            local bags, cats = _G.CUI_Bags, _G.CUI_CategoryManager
            if bags and bags.SellJunk and cats and cats:IsJunkMarkerEnabled() then
                return bags:SellJunk(atMerchant)
            end
            if not (C_MerchantFrame and C_MerchantFrame.SellAllJunkItems) then
                return
            end
            StopJunkSweep()
            passes, lastCount, stallCount, warned = 0, math.huge, 0, false
            delay = BASE_DELAY
            -- Pass reschedules itself only when there's more to do, so a no-gray visit costs one bag scan and arms no timer.
            Pass()
        end
    end

    -- Auto-repair result watcher. RepairAllItems(true) never fails for lack of guild
    -- funds -- the server pays what the allowance covers and silently charges the
    -- player the rest, so success alone doesn't say who paid. GetGuildBankMoney()
    -- (GuildRepairFunds) reads 0 until a guild bank opens this session, so it's a
    -- ceiling only. Share is deduced from the player's ledger (outgoing sums only),
    -- immune to an incoming credit except one sharing the SAME PLAYER_MONEY event (nets off) -- hence the caller holds the junk sweep until the debit lands.
    local repairWatch, repairWatchLast, repairWatchOut
    local repairSerial = 0
    local repairWatchSweep -- junk sweep on hold; see ReleaseJunkSweep

    -- Mirrors Blizzard's guild-repair tooltip: today's remaining allowance, bounded by balance; -1 means an unlimited rank.
    local function GuildRepairFunds()
        local allowance = GetGuildBankWithdrawMoney()
        local balance = GetGuildBankMoney()
        if allowance < 0 or allowance > balance then
            return balance
        end
        return allowance
    end

    -- Total, then guild's share; spelled out only on a split bill since a wholly guild-funded one is unambiguous from the suffix alone.
    local function ReportRepairOutcome(guildText, ownPart)
        local lineText = CludesUI.Lf("Repaired all items for %s", RepairCostString(guildText + ownPart))
        if guildText > 0 then
            lineText = lineText .. CludesUI.L(" (guild bank)")
            if ownPart > 0 then
                lineText = lineText .. " " .. RepairCostString(guildText)
            end
        end
        CludesUI.Print(CludesUI.COLOR_CODES.BRAND .. "CludesUI:|r " .. lineText)
    end

    local function ReportRepairBroke()
        local colorCodes = CludesUI.COLOR_CODES
        CludesUI.Print(
            colorCodes.BRAND .. "CludesUI:|r " .. colorCodes.ERROR .. CludesUI.L("Not enough gold to repair.") .. "|r"
        )
    end

    -- Releases the held-back junk sweep. Idempotent: debit or settle timer, whichever arrives first, starts it.
    local function ReleaseJunkSweep()
        local sweep = repairWatchSweep
        repairWatchSweep = nil
        if sweep then
            sweep()
        end
    end

    -- A remainder can outlive the watch, so it gets its own waiter instead of a
    -- verdict at the half-second mark: the held-back junk sweep often pays the rest,
    -- its first sale barely landed by then. Ends on enough gold, merchant close, or deadline (only then is broke declared).
    local TOPUP_WINDOW = 8 -- outlasts a full junk sweep (12 passes backing off to 1.6s)
    local repairExtra, repairTopUpGen = nil, 0

    local function CancelRepairTopUp()
        repairTopUpGen = repairTopUpGen + 1
        if repairExtra then
            repairExtra:UnregisterAllEvents()
            repairExtra:SetScript("OnEvent", nil)
        end
    end

    local function StartRepairTopUp(remainCost)
        CancelRepairTopUp()
        if not repairExtra then
            repairExtra = CreateFrame("Frame", "CUI_RepairTopUp", UIParent)
        end
        local gen = repairTopUpGen
        local settled = false

        local function Finish(afford)
            settled = true
            CancelRepairTopUp()
            -- Giving up isn't the same as being broke: gold still in pocket is nobody's fault.
            if not afford then
                if GetMoney() < remainCost then
                    ReportRepairBroke()
                end
                return
            end
            -- Re-read: seconds have passed, player may have repaired by hand, so the armed figure can't be trusted.
            local nowCost, stillNeed = GetRepairAllCost()
            if not (stillNeed and nowCost > 0) then
                return
            end
            RepairAllItems(false)
            ReportRepairOutcome(0, nowCost)
        end

        local function Poll(_, eventName)
            if settled or gen ~= repairTopUpGen then
                return
            end
            -- MERCHANT_CLOSED rather than merchantOpen: two frames listening for
            -- the same event have no defined order, so the flag may not be down yet
            if eventName == "MERCHANT_CLOSED" or not CanMerchantRepair() then
                return Finish(false)
            end
            if GetMoney() >= remainCost then
                return Finish(true)
            end
        end

        Poll()
        if settled then
            return
        end
        repairExtra:SetScript("OnEvent", Poll)
        repairExtra:RegisterEvent("PLAYER_MONEY")
        repairExtra:RegisterEvent("MERCHANT_CLOSED")
        C_Timer.After(TOPUP_WINDOW, function()
            if settled or gen ~= repairTopUpGen then
                return
            end
            Finish(false)
        end)
    end

    local function OnRepairWatchEvent() -- PLAYER_MONEY: accumulate only, never decide
        local nowTime = GetMoney()
        local spent = repairWatchLast - nowTime
        if spent > 0 then
            repairWatchOut = repairWatchOut + spent
            -- The debit is booked, so nothing later can net against it; holding
            -- the sweep longer only risks losing the sale on a visit that ends within the window.
            ReleaseJunkSweep()
        end
        repairWatchLast = nowTime
    end

    -- One timer settles everything: resolving early on a big-enough deduction would
    -- misread an unrelated purchase as paying the whole bill, and MERCHANT_CLOSED
    -- could fire before an in-flight deduction lands. sweep is the junk sweep this
    -- watch holds back, released on the debit or here at the latest; a watch
    -- superseded by a new merchant never gets this far, which is correct (that merchant holds its own).
    local function StartRepairWatch(repairCost, moneyBefore, guildFunds, sweep)
        if not repairWatch then
            repairWatch = CreateFrame("Frame", "CUI_RepairWatcher", UIParent)
            repairWatch:SetScript("OnEvent", OnRepairWatchEvent)
        end

        -- The bump IS the cancellation: a timeout still pending from a previous merchant sees a stale gen and dies.
        repairSerial = repairSerial + 1
        repairWatchLast = moneyBefore
        repairWatchOut = 0
        repairWatchSweep = sweep
        CancelRepairTopUp() -- a remainder from the last merchant is no longer payable
        repairWatch:RegisterEvent("PLAYER_MONEY")

        local gen = repairSerial
        C_Timer.After(0.5, function()
            if gen ~= repairSerial then
                return
            end
            repairWatch:UnregisterAllEvents()
            local remainCost, stillNeed = GetRepairAllCost()
            if not (stillNeed and remainCost > 0) then
                remainCost = 0
            end

            local own = repairWatchOut
            local paid = repairCost - remainCost
            if own > paid then
                own = paid
            end
            local guildText = paid - own

            -- Backstop for a credit sharing an event with the debit: pre-repair
            -- funds cap the deduced share. Weak alone (unread/empty bank reads 0 --
            -- exactly the guild-is-broke case), so it only ever tightens, never decides.
            if guildFunds > 0 and guildText > guildFunds then
                guildText = guildFunds
                own = paid - guildText
            end

            if paid > 0 then
                ReportRepairOutcome(guildText, own)
            end

            -- Release before handing the remainder over: funds can run dry mid-bill and the sweep's income is what the top-up waits for.
            ReleaseJunkSweep()
            if remainCost > 0 then
                StartRepairTopUp(remainCost)
            end
        end)
    end

    local merchantFrame = CreateFrame("Frame", "CUI_MerchantHandler", UIParent)
    merchantFrame:RegisterEvent("MERCHANT_SHOW")
    merchantFrame:RegisterEvent("MERCHANT_CLOSED")
    merchantFrame:SetScript("OnEvent", function(_, eventName)
        if eventName == "MERCHANT_CLOSED" then
            atMerchant = false
            return StopJunkSweep()
        end
        atMerchant = true
        if not CludesUIDB then
            return
        end

        local sweep = (CludesUIDB.autoSellJunk ~= false) and SellJunk or nil

        -- Auto repair goes first; on the guild path the junk sweep is handed to
        -- the watcher instead of started here, since sale income sharing a
        -- PLAYER_MONEY event with the debit would net against it and credit the
        -- whole bill to the guild bank. Held back only until the debit lands.
        if CludesUIDB.autoRepair ~= false and CanMerchantRepair() then
            local repairCost, canRepair = GetRepairAllCost()
            if canRepair and repairCost > 0 then
                -- No affordability test on purpose: Blizzard's own button just calls
                -- RepairAllItems(true) and lets the server split the bill -- gating on "guild covers it all" would bill the player the lot.
                local useGuild = (CludesUIDB.autoRepairGuild ~= false)
                    and IsInGuild()
                    and CanGuildBankRepair()

                if not useGuild and GetMoney() < repairCost then
                    ReportRepairBroke() -- nothing was spent, so nothing to watch
                elseif useGuild then
                    -- Both readings must predate the repair; only matter when the guild bank is in play.
                    local moneyBefore, guildFunds = GetMoney(), GuildRepairFunds()
                    RepairAllItems(true)
                    -- Reports once the real payer is known; the sweep rides along, let go the moment the ledger is safe.
                    StartRepairWatch(repairCost, moneyBefore, guildFunds, sweep)
                    return
                else
                    RepairAllItems(false)
                    ReportRepairOutcome(0, repairCost) -- own gold: no ambiguity, report now
                end
            end
        end

        if sweep then
            sweep()
        end
    end)

    ---------------------------------------------------------------------------
    --  Quick Loot -- frame created lazily on first enable; LOOT_READY
    --  registers/unregisters with the toggle so it applies live and costs zero when off.
    ---------------------------------------------------------------------------
    do
        local lootPanel
        CludesUI._applyQuickLoot = function()
            if CludesUIDB and CludesUIDB.quickLoot then
                if not lootPanel then
                    lootPanel = CreateFrame("Frame")
                    lootPanel:SetScript("OnEvent", function()
                        if IsShiftKeyDown() then
                            return
                        end
                        -- Nothing to take: no slot empties, so the window would never close by itself.
                        if GetNumLootItems() == 0 then
                            CloseLoot()
                            return
                        end
                        for i = 1, GetNumLootItems() do
                            local index = i
                            C_Timer.After(0.05 * index, function()
                                LootSlot(index)
                            end)
                        end
                    end)
                end
                lootPanel:RegisterEvent("LOOT_READY")
            elseif lootPanel then
                lootPanel:UnregisterEvent("LOOT_READY")
            end
        end
        CludesUI._applyQuickLoot()
    end

    ---------------------------------------------------------------------------
    --  Auto Select Single Gossip -- picks the only gossip option. Skipped when
    --  the NPC offers a quest or has one ready to turn in. GOSSIP_SHOW and
    --  GOSSIP_CLOSED are registered only while the toggle is on.
    ---------------------------------------------------------------------------
    do
        local gossipPanel
        -- Page and option pairs picked in this conversation (cleared when it
        -- ends): each is picked once, so two single-option pages that lead to
        -- each other cannot flip back and forth.
        local picked = {}

        local function OnGossipShow()
            local store = CludesUIDB
            if store.autoGossipShiftSkip ~= false and IsShiftKeyDown() then
                return
            end
            if store.autoGossipDisableInstance ~= false and IsInInstance() then
                return
            end

            local options = C_GossipInfo.GetOptions()
            if not options or #options ~= 1 then
                return
            end
            local option = options[1]
            -- A locked or unavailable option would only fail again.
            if option.status ~= Enum.GossipOptionStatus.Available then
                return
            end
            local settingKey = (C_GossipInfo.GetText() or "") .. "\0" .. (option.gossipOptionID or option.name)
            if picked[settingKey] then
                return
            end

            -- Trivial quests only stay ignorable if Quest Tracker auto-accept also ignores them.
            local qtDB = _G._CUQT_DB
            local trackerCfg = qtDB and qtDB.profile and qtDB.profile.questTracker
            local ignoreTrivial = store.autoGossipIgnoreTrivial
                and not (trackerCfg and trackerCfg.enabled ~= false and trackerCfg.autoAccept and not trackerCfg.autoAcceptIgnoreTrivial)
            for _, quest in ipairs(C_GossipInfo.GetAvailableQuests()) do
                if not (ignoreTrivial and quest.isTrivial) then
                    return
                end
            end
            local isActive = C_GossipInfo.GetActiveQuests()
            for _, quest in ipairs(isActive) do
                if quest.isComplete then
                    return
                end
            end

            -- Blizzard already auto-selects this case itself.
            if
                #isActive == 0
                and C_GossipInfo.GetNumAvailableQuests() == 0
                and option.selectOptionWhenOnlyOption
            then
                return
            end

            picked[settingKey] = true
            C_GossipInfo.SelectOptionByIndex(option.orderIndex)
        end

        local function OnGossipEvent(_, eventName)
            if eventName == "GOSSIP_CLOSED" then
                wipe(picked)
            else
                OnGossipShow()
            end
        end

        CludesUI._applyAutoGossip = function()
            if CludesUIDB and CludesUIDB.autoGossip then
                if not gossipPanel then
                    gossipPanel = CreateFrame("Frame")
                    gossipPanel:SetScript("OnEvent", OnGossipEvent)
                end
                gossipPanel:RegisterEvent("GOSSIP_SHOW")
                gossipPanel:RegisterEvent("GOSSIP_CLOSED")
            elseif gossipPanel then
                gossipPanel:UnregisterEvent("GOSSIP_SHOW")
                gossipPanel:UnregisterEvent("GOSSIP_CLOSED")
                wipe(picked)
            end
        end
        CludesUI._applyAutoGossip()
    end

    ---------------------------------------------------------------------------
    --  Auto-Fill Delete Confirmation
    ---------------------------------------------------------------------------
    do
        for i = 1, 4 do
            local dialog = _G["StaticPopup" .. i]
            if dialog then
                hooksecurefunc(dialog, "Show", function(self)
                    if not self then
                        return
                    end
                    if self.which ~= "DELETE_GOOD_ITEM" and self.which ~= "DELETE_GOOD_QUEST_ITEM" then
                        return
                    end
                    if not (CludesUIDB and CludesUIDB.autoFillDelete) then
                        return
                    end
                    local editBox = self.editBox or (self.GetEditBox and self:GetEditBox())
                    if not editBox then
                        return
                    end
                    editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
                    editBox:SetFocus()
                end)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Skip Cinematics
    ---------------------------------------------------------------------------
    do
        local cinHooked = false
        local skipArmed = false

        -- CancelScene() is hardware-gated: blocked from an event handler but
        -- allowed while processing a key press, so auto skip arms a one-shot
        -- cancel the key hooks consume on the cutscene's first keypress.
        local function ConsumeArmedSkip()
            if not skipArmed then
                return
            end
            if not (CludesUIDB and CludesUIDB.skipCinematicsAuto) then
                return
            end
            if not (CinematicFrame and CinematicFrame:IsShown()) then
                return
            end
            skipArmed = false
            if CinematicFrame.isRealCinematic then
                StopCinematic()
            elseif CanCancelScene and CanCancelScene() then
                CancelScene()
            end
        end

        local function SetupCinematicHooks()
            if cinHooked then
                return
            end
            if not CinematicFrame or not CinematicFrame.HookScript then
                return
            end
            cinHooked = true

            CinematicFrame:HookScript("OnKeyDown", function(_, settingKey)
                if not (CludesUIDB and CludesUIDB.skipCinematics) then
                    return
                end
                if settingKey == "ESCAPE" then
                    if CinematicFrame:IsShown() and CinematicFrame.closeDialog then
                        CinematicFrame.closeDialog:Hide()
                    end
                end
            end)

            CinematicFrame:HookScript("OnKeyUp", function(_, settingKey)
                if not (CludesUIDB and CludesUIDB.skipCinematics) then
                    return
                end
                if settingKey == "SPACE" or settingKey == "ESCAPE" or settingKey == "ENTER" then
                    if CinematicFrame:IsShown() and CinematicFrame.closeDialog then
                        local confirmBtn = _G["CinematicFrameCloseDialogConfirmButton"]
                        if confirmBtn then
                            confirmBtn:Click()
                        end
                    end
                end
            end)

            if MovieFrame and MovieFrame.HookScript then
                MovieFrame:HookScript("OnKeyUp", function(_, settingKey)
                    if not (CludesUIDB and CludesUIDB.skipCinematics) then
                        return
                    end
                    if settingKey == "SPACE" or settingKey == "ESCAPE" or settingKey == "ENTER" then
                        if
                            MovieFrame:IsShown()
                            and MovieFrame.CloseDialog
                            and MovieFrame.CloseDialog.ConfirmButton
                        then
                            MovieFrame.CloseDialog.ConfirmButton:Click()
                        end
                    end
                end)
            end

            CinematicFrame:HookScript("OnKeyDown", ConsumeArmedSkip)
        end

        local cineEvents = CreateFrame("Frame")
        cineEvents:RegisterEvent("CINEMATIC_START")
        cineEvents:RegisterEvent("CINEMATIC_STOP")
        cineEvents:RegisterEvent("PLAY_MOVIE")
        cineEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
        cineEvents:SetScript("OnEvent", function(self, eventName)
            if eventName == "PLAYER_ENTERING_WORLD" then
                self:UnregisterEvent("PLAYER_ENTERING_WORLD")
                SetupCinematicHooks()
                return
            end
            if eventName == "CINEMATIC_STOP" then
                skipArmed = false
                return
            end
            if not (CludesUIDB and CludesUIDB.skipCinematicsAuto) then
                return
            end
            if eventName == "CINEMATIC_START" then
                -- Real cinematics can still be stopped from event context;
                -- scenes are left to the armed key-press cancel.
                skipArmed = true
                if CinematicFrame and CinematicFrame.isRealCinematic then
                    StopCinematic()
                end
            elseif eventName == "PLAY_MOVIE" then
                if MovieFrame then
                    MovieFrame:Hide()
                end
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Auto Insert Keystone (no keystones on WoW Forever: the block, its events
    --  and its options row do not exist there)
    ---------------------------------------------------------------------------
    if not CludesUI.IS_FOREVER then
        local function InsertKeystone()
            if CludesUIDB and CludesUIDB.autoInsertKeystone == false then
                return
            end
            if C_ChallengeMode.GetSlottedKeystoneInfo() then
                return
            end
            for bagId = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
                local slots = C_Container.GetContainerNumSlots(bagId)
                for slotId = 1, slots do
                    local itemLink = C_Container.GetContainerItemLink(bagId, slotId)
                    if itemLink and itemLink:find("|Hkeystone:") then
                        C_Container.PickupContainerItem(bagId, slotId)
                        if CursorHasItem() then
                            C_ChallengeMode.SlotKeystone()
                        end
                        return
                    end
                end
            end
        end

        local ksFrame = CreateFrame("Frame")
        ksFrame:RegisterEvent("CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN")
        ksFrame:RegisterEvent("ADDON_LOADED")
        ksFrame:SetScript("OnEvent", function(self, eventName, arg1)
            if eventName == "CHALLENGE_MODE_KEYSTONE_RECEPTABLE_OPEN" then
                InsertKeystone()
            elseif eventName == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
                self:UnregisterEvent("ADDON_LOADED")
                if ChallengesKeystoneFrame then
                    ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
                end
            end
        end)

        if C_AddOns.IsAddOnLoaded("Blizzard_ChallengesUI") then
            if ChallengesKeystoneFrame then
                ChallengesKeystoneFrame:HookScript("OnShow", InsertKeystone)
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Quick Signup and Persistent Signup Note -- implemented in the parent
    --  (CludesUI_SignupHelpers.lua) so Group Finder shares them; the QoL
    --  toggles drive them via CludesUI._applyQuickSignup / _applyPersistSignupNote.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Hide Blizzard Party / Raid Manager frame -- implemented in the parent
    --  (CludesUI_BlizzardParty.lua) so Raid Frames shares the same logic +
    --  saved setting; QoL toggle drives it via CludesUI._applyHideBlizzardPartyFrame.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  Hide Talking Head Frame (the NPC dialogue rectangle during quests/dungeons)
    --  and Talking Head Audio (its voice lines), each on its own; not on WoW
    --  Forever: the block, its hooks and its options rows do not exist there.
    --
    --  The frame stays shown but invisible: alpha 0 and no mouse on the frame
    --  itself and on its close button, its one mouse-enabled child. A Hide()
    --  from here would run the bottom managed column's layout under our taint,
    --  and would leave the line half-closed (the close fade never runs on a
    --  hidden frame), so Blizzard showed it again on its next pass. Shown, the
    --  line closes through Blizzard's own fade. Edit Mode still shows the frame.
    --  The 3D portrait model draws past its parents' alpha, so it is hidden
    --  itself while suppressed (Blizzard never shows or hides it) and shown
    --  again only if this block hid it.
    ---------------------------------------------------------------------------
    if not CludesUI.IS_FOREVER then
        local isHooked, isSuppressed = false, false
        local frameMouse, closeMouse -- mouse states found when suppression began
        local modelHidden = false -- the portrait model was hidden here

        local function Wanted()
            local store = CludesUIDB
            return store and (store.hideTalkingHead or store.muteTalkingHead)
        end

        local function ApplyTalkingHead(threatFrame)
            local close, model = threatFrame.MainFrame.CloseButton, threatFrame.MainFrame.Model
            if CludesUIDB and CludesUIDB.hideTalkingHead and not threatFrame.isInEditMode then
                if not isSuppressed then
                    isSuppressed = true
                    frameMouse, closeMouse = threatFrame:IsMouseEnabled(), close:IsMouseEnabled()
                    threatFrame:EnableMouse(false)
                    close:EnableMouse(false)
                end
                if threatFrame:GetAlpha() ~= 0 then
                    threatFrame:SetAlpha(0)
                end
                if model:IsShown() then
                    model:Hide()
                    modelHidden = true
                end
            elseif isSuppressed then
                isSuppressed = false
                threatFrame:SetAlpha(1)
                threatFrame:EnableMouse(frameMouse)
                close:EnableMouse(closeMouse)
                if modelHidden then
                    modelHidden = false
                    model:Show()
                end
            end
        end

        local function Install(threatFrame)
            if isHooked then
                return
            end
            isHooked = true
            -- Every show and hide runs through UpdateShownState: each line, its
            -- close, a loading screen, Edit Mode coming and going.
            hooksecurefunc(threatFrame, "UpdateShownState", ApplyTalkingHead)
            -- The bottom managed column sets the frame's alpha back to 1 when
            -- the UI returns from Alt-Z.
            hooksecurefunc(threatFrame, "SetAlpha", function(self, alpha)
                if isSuppressed and alpha ~= 0 then
                    ApplyTalkingHead(self)
                end
            end)
            -- Audio: PlayCurrent keeps the line's sound handle in voHandle.
            hooksecurefunc(threatFrame, "PlayCurrent", function(self)
                if CludesUIDB and CludesUIDB.muteTalkingHead and self.voHandle then
                    StopSound(self.voHandle)
                end
            end)
        end

        -- Install now, or arm ONE waiter for the frame's addon (shared by the
        -- login install and a mid-session enable).
        local waitArmed = false
        local function EnsureInstalled()
            local threatFrame = _G.TalkingHeadFrame
            if threatFrame then
                Install(threatFrame)
                ApplyTalkingHead(threatFrame)
                return
            end
            if waitArmed then
                return
            end
            waitArmed = true
            local waitFrame = CreateFrame("Frame")
            waitFrame:RegisterEvent("ADDON_LOADED")
            waitFrame:SetScript("OnEvent", function(self)
                if _G.TalkingHeadFrame then
                    self:UnregisterAllEvents()
                    EnsureInstalled()
                end
            end)
        end

        -- Options-side apply (both options): a change bites at once, mid-line
        -- included.
        CludesUI._applyHideTalkingHead = function()
            if Wanted() then
                EnsureInstalled()
                local threatFrame = _G.TalkingHeadFrame
                if CludesUIDB.muteTalkingHead and threatFrame and threatFrame.voHandle then
                    StopSound(threatFrame.voHandle)
                end
            elseif isHooked then
                ApplyTalkingHead(_G.TalkingHeadFrame)
            end
        end

        -- Login install only with an option on (nothing is hooked otherwise;
        -- a later enable installs through _applyHideTalkingHead above).
        if Wanted() then
            EnsureInstalled()
        end
    end

    ---------------------------------------------------------------------------
    --  Hide Loot Rolls Window (GroupLootHistoryFrame) -- the running list of
    --  what dropped, who rolled what, and who won. Two modes off one toggle:
    --  hide it outright, or let it appear and close itself after a delay.
    --
    --  Blizzard re-shows the window on every drop and roll result, so a single
    --  Hide() never sticks -- enforcement has to ride the show path. BOTH the
    --  OnShow script and the Show method are hooked: a drop landing while the
    --  window is already up re-calls Show() without firing OnShow, and that is
    --  exactly when the auto-close delay has to restart.
    --
    --  The window is unprotected and purely informational (no secure state, no
    --  managed-position involvement), so a plain Hide() is safe. Nothing is
    --  unregistered or reparented either, so turning the toggle back off hands
    --  the window straight back to Blizzard without a reload.
    ---------------------------------------------------------------------------
    do
        local DEFAULT_DELAY = 5
        local closeSerial = 0 -- bumped on every show; invalidates older timers

        local function HistoryFrame()
            local frame = _G.GroupLootHistoryFrame
            if not frame or not frame.HookScript then
                return nil
            end
            if frame.IsForbidden and frame:IsForbidden() then
                return nil
            end
            return frame
        end

        local function CloseDelay()
            local skinData = CludesUIDB and CludesUIDB.lootHistoryDelay
            if type(skinData) ~= "number" or skinData <= 0 then
                return DEFAULT_DELAY
            end
            return skinData
        end

        local function Enforce()
            if not (CludesUIDB and CludesUIDB.hideLootHistory) then
                return
            end
            local frame = HistoryFrame()
            if not frame then
                return
            end
            closeSerial = closeSerial + 1
            if CludesUIDB.lootHistoryMode ~= "autoclose" then
                frame:Hide()
                return
            end
            local gen = closeSerial
            C_Timer.After(CloseDelay(), function()
                -- A newer show (or a settings change) armed its own timer.
                if gen ~= closeSerial then
                    return
                end
                if not (CludesUIDB and CludesUIDB.hideLootHistory) then
                    return
                end
                local live = HistoryFrame()
                if live and live:IsShown() then
                    live:Hide()
                end
            end)
        end

        local function HookHistory()
            local frame = HistoryFrame()
            if not frame or CludesUI._GetFFD(frame).lootHistHooked then
                return
            end
            CludesUI._GetFFD(frame).lootHistHooked = true
            frame:HookScript("OnShow", Enforce)
            hooksecurefunc(frame, "Show", Enforce)
        end

        -- Hook now, or arm ONE waiter for the frame's Blizzard_ addon (it is
        -- created on first use, not necessarily at login). Shared by the
        -- load-time install and a mid-session enable that beats the frame's
        -- creation -- without the waiter half, that enable would silently
        -- never hook.
        local waitArmed = false
        local function EnsureInstalled()
            if _G.GroupLootHistoryFrame then
                HookHistory()
                return
            end
            if waitArmed then
                return
            end
            waitArmed = true
            local waitFrame = CreateFrame("Frame")
            waitFrame:RegisterEvent("ADDON_LOADED")
            waitFrame:SetScript("OnEvent", function(self)
                if _G.GroupLootHistoryFrame then
                    HookHistory()
                    self:UnregisterAllEvents()
                end
            end)
        end

        -- Options-side apply: a toggle must bite now, not on the next drop.
        -- The closeGen bump also cancels a pending auto-close when the mode
        -- changes or the feature is switched off mid-countdown.
        CludesUI._applyHideLootHistory = function()
            if CludesUIDB and CludesUIDB.hideLootHistory then
                EnsureInstalled()
            end
            closeSerial = closeSerial + 1
            local frame = HistoryFrame()
            if frame and frame:IsShown() then
                Enforce()
            end
        end

        -- Load-time install ONLY for users with the feature already on
        -- (zero cost disabled: no waiter frame, no ADDON_LOADED listener,
        -- no hooks -- a later enable installs through _applyHideLootHistory
        -- above).
        if CludesUIDB and CludesUIDB.hideLootHistory then
            EnsureInstalled()
        end
    end

    if not CludesUI.IS_FOREVER then
        local function EndHiddenBanner()
            if not (CludesUIDB and CludesUIDB.hideBanners) then
                return
            end
            local current = TopBannerMgr.currentBanner
            local frame = current and current.frame
            if not frame then
                return
            end
            if frame == BossBanner then
                -- The banner's own right-click dismiss: its state stays mid-show, so
                -- no loot banner (or its sound) starts for this encounter; the next
                -- boss kill starts it fresh.
                BossBanner_Stop(frame)
                TopBannerManager_BannerFinished()
            elseif
                frame:GetParent() == EventToastManagerFrame
                and frame.hideAutomatically
                and not frame:ShouldSuppressAnimOut()
            then
                frame.showAnim:Stop()
                frame.hideAnim:Stop()
                EventToastManagerFrame:Reset()
                frame:OnAnimatedOut()
            end
        end

        local bannerHooks = false
        CludesUI._applyHideBanners = function()
            if not (CludesUIDB and CludesUIDB.hideBanners) then
                return
            end
            if not bannerHooks then
                bannerHooks = true
                hooksecurefunc("TopBannerManager_Show", EndHiddenBanner)
                hooksecurefunc("TopBannerManager_BannerFinished", EndHiddenBanner)
            end
            EndHiddenBanner()
        end

        local TOAST_KINDS = {
            {
                key = "hideAlertToastsLoot",
                default = true,
                systems = {
                    LootAlertSystem,
                    LootUpgradeAlertSystem,
                    MoneyWonAlertSystem,
                    HonorAwardedAlertSystem,
                    LegendaryItemAlertSystem,
                },
            },
            {
                key = "hideAlertToastsAchievements",
                systems = {
                    AchievementAlertSystem,
                    CriteriaAlertSystem,
                },
            },
            {
                key = "hideAlertToastsHousing",
                systems = {
                    HousingItemEarnedAlertFrameSystem,
                    InitiativeTaskCompleteAlertFrameSystem,
                },
            },
        }
        local kindOf = {}
        for i = 1, #TOAST_KINDS do
            local kind = TOAST_KINDS[i]
            for jdx = 1, #kind.systems do
                kindOf[kind.systems[jdx]] = kind
            end
        end

        local function KindHidden(kind)
            local store = CludesUIDB
            if not (store and store.hideAlertToasts) then
                return false
            end
            local val = store[kind.key]
            if val == nil then
                return kind.default or false
            end
            return val
        end

        local hidingToasts = false

        local function FirstShownToast(systemMsg)
            for widget in systemMsg.alertFramePool:EnumerateActive() do
                if widget:IsShown() then
                    return widget
                end
            end
        end

        local function HideAlertToasts(systemMsg)
            if hidingToasts or not KindHidden(kindOf[systemMsg]) then
                return
            end
            hidingToasts = true
            local widget = FirstShownToast(systemMsg)
            while widget do
                widget:Hide()
                widget = FirstShownToast(systemMsg)
            end
            hidingToasts = false
        end

        local isHooked = {}
        CludesUI._applyHideAlertToasts = function()
            for i = 1, #TOAST_KINDS do
                local kind = TOAST_KINDS[i]
                if KindHidden(kind) then
                    for jdx = 1, #kind.systems do
                        local systemMsg = kind.systems[jdx]
                        if not isHooked[systemMsg] then
                            isHooked[systemMsg] = true
                            hooksecurefunc(systemMsg, "ShowAlert", HideAlertToasts)
                        end
                        HideAlertToasts(systemMsg)
                    end
                end
            end
        end

        CludesUI._applyHideBanners()
        CludesUI._applyHideAlertToasts()
    end

    ---------------------------------------------------------------------------
    --  Instance Reset Announce -- after a successful /reset, posts to instance
    --  chat so the group knows it's ready to re-enter.
    ---------------------------------------------------------------------------
    do
        local playerName = UnitName("player") or "Unknown"

        -- Success detected from Blizzard's CHAT_MSG_SYSTEM confirmation; the string varies by locale, so match common substrings across clients.
        local RESET_PATTERNS = {
            "has been reset", -- enUS / enGB
            "wurde zur", -- deDE (zurückgesetzt)
            "a été réinitialisé", -- frFR
            "ha sido reiniciada", -- esES / esMX
            "è stato resettato", -- itIT
            "foi reiniciada", -- ptBR / ptPT
            "сброшен", -- ruRU
            "已重置", -- zhCN / zhTW
            "초기화되었습니다", -- koKR
        }

        -- Patterns that indicate a reset FAILED because players are still inside.
        local FAIL_PATTERNS = {
            "players still", -- enUS / enGB: "There are players still inside..."
            "noch spieler", -- deDE
            "joueurs sont encore", -- frFR
            "jugadores todavía", -- esES / esMX
            "giocatori sono ancora", -- itIT
            "jogadores ainda", -- ptBR / ptPT
            "игроки ещё", -- ruRU
            "还有玩家", -- zhCN
            "아직 플레이어", -- koKR
        }

        local function MatchesAny(message, patterns)
            if not message then
                return false
            end
            local ok, lower = pcall(string.lower, message)
            if not ok then
                return false
            end
            for _, pat in ipairs(patterns) do
                local ok2, result = pcall(string.find, lower, string.lower(pat), 1, true)
                if ok2 and result then
                    return true
                end
            end
            return false
        end

        local resetAnnouncePending = false -- one announce per /reset batch (multi-dungeon reset = multiple system msgs)
        local resetFailPending = false

        local resetAnnounceFrame = CreateFrame("Frame")
        resetAnnounceFrame:SetScript("OnEvent", function(self, eventName, message)
            -- CHAT_MSG_SYSTEM fires for every system message all session (this frame
            -- stays registered while the toggle is on, not just around /reset), and some
            -- carry secret text in protected content. Bail before touching msg at all.
            if issecretvalue and issecretvalue(message) then
                return
            end
            if not (CludesUIDB and CludesUIDB.instanceResetAnnounce) then
                return
            end

            -- Instance group only: LE_PARTY_CATEGORY_INSTANCE covers party/raid; IsInGroup() is the older-API fallback.
            local inInstanceGroup = (
                IsInGroup
                and LE_PARTY_CATEGORY_INSTANCE
                and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
            ) or (IsInGroup and IsInGroup())

            if not inInstanceGroup then
                return
            end

            -- A reset cannot fail in a party: there a "players still inside" line
            -- still means the instance reset, so it announces success.
            local success = MatchesAny(message, RESET_PATTERNS)
                or (not IsInRaid() and MatchesAny(message, FAIL_PATTERNS))

            -- Small delay so Blizzard's own system message renders first.
            if success then
                if resetAnnouncePending then
                    return
                end
                resetAnnouncePending = true
                C_Timer.After(0.3, function()
                    resetAnnouncePending = false
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    local customMsg = (
                        CludesUIDB.instanceResetAnnounceMsg
                        and CludesUIDB.instanceResetAnnounceMsg ~= ""
                    )
                            and CludesUIDB.instanceResetAnnounceMsg
                        or "Instance has been reset - you can re-enter now!"
                    C_ChatInfo.SendChatMessage("[CUI] " .. customMsg, channel)
                end)
            elseif MatchesAny(message, FAIL_PATTERNS) then
                if resetFailPending then
                    return
                end
                resetFailPending = true
                C_Timer.After(0.3, function()
                    resetFailPending = false
                    local channel = IsInRaid() and "RAID" or "PARTY"
                    C_ChatInfo.SendChatMessage(
                        "[CUI] Reset failed - there are still players inside the instance.",
                        channel
                    )
                end)
            end
        end)

        -- CHAT_MSG_SYSTEM fires for all system chat, so registered only while on (toggle re-applies live).
        CludesUI._applyInstanceResetAnnounce = function()
            if CludesUIDB and CludesUIDB.instanceResetAnnounce then
                resetAnnounceFrame:RegisterEvent("CHAT_MSG_SYSTEM")
            else
                resetAnnounceFrame:UnregisterEvent("CHAT_MSG_SYSTEM")
            end
        end
        CludesUI._applyInstanceResetAnnounce()
    end

    ---------------------------------------------------------------------------
    --  24-Hour Clock Fix -- Blizzard's timeMgrUseMilitaryTime CVar resets to 12h
    --  on every login; save the user's choice on toggle, restore it on login.
    ---------------------------------------------------------------------------
    do
        local saved = CludesUIDB and CludesUIDB.clockFormat24h
        -- Restore: only if user previously chose 24h and the CVar got reset
        if saved and GetCVar("timeMgrUseMilitaryTime") ~= "1" then
            C_Timer.After(0.5, function()
                if not TimeManagerFrame then
                    if TimeManager_LoadUI then
                        TimeManager_LoadUI()
                    end
                end
                local callback = TimeManagerMilitaryTimeCheck
                if callback then
                    callback:SetChecked(true)
                    local func = callback:GetScript("OnClick")
                    if func then
                        func(callback)
                    end
                end
            end)
        end
        -- Track: hook the checkbox to remember user changes
        local function HookClockCheckbox()
            local callback = TimeManagerMilitaryTimeCheck
            if not callback then
                return
            end
            callback:HookScript("OnClick", function(self)
                if not CludesUIDB then
                    CludesUIDB = {}
                end
                CludesUIDB.clockFormat24h = self:GetChecked() and true or nil
            end)
        end
        -- The TimeManager may not be loaded yet; hook when it appears
        if TimeManagerMilitaryTimeCheck then
            HookClockCheckbox()
        else
            local hookFrame = CreateFrame("Frame")
            hookFrame:RegisterEvent("ADDON_LOADED")
            hookFrame:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_TimeManager" then
                    self:UnregisterEvent("ADDON_LOADED")
                    HookClockCheckbox()
                end
            end)
        end
    end
end)

-------------------------------------------------------------------------------
--  Guild Chat Privacy
--  Streamer feature: overlay on CommunitiesFrame guild chat, click to reveal.
-------------------------------------------------------------------------------
do
    local overlayFrame
    local function ShowOverlay()
        if not overlayFrame then
            return
        end
        if not (CludesUIDB and CludesUIDB.guildChatPrivacy) then
            return
        end
        local castFrame = CommunitiesFrame
        if not castFrame or not castFrame.Chat or not castFrame.Chat.MessageFrame then
            return
        end
        local mf = castFrame.Chat.MessageFrame
        overlayFrame:SetParent(mf)
        overlayFrame:SetAllPoints(mf)
        overlayFrame:SetFrameLevel(mf:GetFrameLevel() + 20)
        overlayFrame:Show()
    end

    local function ApplyGuildChatPrivacy()
        local isEnabled = CludesUIDB and CludesUIDB.guildChatPrivacy
        if not isEnabled then
            if overlayFrame then
                overlayFrame:Hide()
            end
            return
        end

        if not overlayFrame then
            overlayFrame = CreateFrame("Button", nil, UIParent)
            overlayFrame:SetFrameStrata("DIALOG")
            local backdrop = overlayFrame:CreateTexture(nil, "BACKGROUND")
            backdrop:SetPoint("TOPLEFT", -2, 0)
            backdrop:SetPoint("BOTTOMRIGHT", 2, -4)
            backdrop:SetColorTexture(0.133, 0.133, 0.133, 1)
            local txt = overlayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            txt:SetPoint("CENTER")
            txt:SetText("Click to Show")
            txt:SetTextColor(0.7, 0.7, 0.7, 1)
            overlayFrame:SetScript("OnClick", function(self)
                self:Hide()
            end)
        end

        if CommunitiesFrame then
            ShowOverlay()
            if not overlayFrame._hooked then
                CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                overlayFrame._hooked = true
            end
        else
            local loadFrame = CreateFrame("Frame")
            loadFrame:RegisterEvent("ADDON_LOADED")
            loadFrame:SetScript("OnEvent", function(self, _, addon)
                if addon == "Blizzard_Communities" then
                    self:UnregisterAllEvents()
                    if CludesUIDB and CludesUIDB.guildChatPrivacy then
                        ShowOverlay()
                        if not overlayFrame._hooked then
                            CommunitiesFrame:HookScript("OnShow", ShowOverlay)
                            overlayFrame._hooked = true
                        end
                    end
                end
            end)
        end
    end
    CludesUI._applyGuildChatPrivacy = ApplyGuildChatPrivacy

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyGuildChatPrivacy()
    end)
end

-------------------------------------------------------------------------------
--  Auto-Accept Resurrection
--  Accepts res requests automatically. A res from a caster in combat (a
--  battle res) is left to the player unless the combat option is on.
-------------------------------------------------------------------------------
do
    local IsSecret = CludesUI.IsSecret
    local widget

    -- A secret or unreadable answer counts as in combat.
    local function CasterInCombat(caster)
        if not caster then
            return false
        end
        local ok, val = pcall(UnitAffectingCombat, caster)
        if not ok or IsSecret(val) then
            return true
        end
        return val and true or false
    end

    local function OnEvent(_, _, caster)
        if not CludesUIDB.autoAcceptResCombat and CasterInCombat(caster) then
            return
        end
        AcceptResurrect()
    end

    local function ApplyAutoAcceptRes()
        local isEnabled = CludesUIDB and CludesUIDB.autoAcceptRes
        if isEnabled and not widget then
            widget = CreateFrame("Frame")
            widget:SetScript("OnEvent", OnEvent)
        end
        if not widget then
            return
        end
        if isEnabled then
            widget:RegisterEvent("RESURRECT_REQUEST")
        else
            widget:UnregisterEvent("RESURRECT_REQUEST")
        end
    end
    CludesUI._applyAutoAcceptRes = ApplyAutoAcceptRes

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if CludesUIDB and CludesUIDB.autoAcceptRes then
            ApplyAutoAcceptRes()
        end
    end)
end

-------------------------------------------------------------------------------
--  Secondary Stats Display
--  On-screen overlay showing crit/haste/mastery/vers (+ optional tertiaries).
-------------------------------------------------------------------------------
do
    local statsPanel, statsLabel
    local format = string.format
    local floor = math.floor

    -- Single-string layout: one FontString, "Label:  value" per row. The
    -- two-column split (separate right-justified values FontString) was
    -- reverted -- per-column sizing/anchor interplay caused more issues
    -- than the aligned numbers were worth.
    local ROW_GAP = 3 -- extra pixels between rows (SetSpacing)

    -- Dim span for the attached FPS rows, which build their own bodies. Every
    -- span opens and closes rather than nesting, since |r restores one level
    -- only.
    local DIM = "|cff9d9d9d"

    -- Gap between a label and its figure, and either side of the latency
    -- divider so the whole block keeps one rhythm.
    local LABEL_GAP = " "

    -- Per-stat label colors, used when no custom color is picked in options.
    -- One hue per secondary so the rows scan at a glance; tertiaries share a
    -- single distinct hue so the block reads as its own group.
    local STAT_HEX = {
        crit = "ffd100", -- gold
        haste = "2ecc71", -- green
        mastery = "55aaff", -- blue
        vers = "c77dff", -- violet
    }
    local DEFAULT_STAT_ORDER = {
        "crit",
        "haste",
        "mastery",
        "vers",
        "leech",
        "avoidance",
        "speed",
    }
    local VALID_STAT = {
        crit = true,
        haste = true,
        mastery = true,
        vers = true,
        leech = true,
        avoidance = true,
        speed = true,
    }
    -- WoW Forever has none of these ratings: the block shows the stat catalog
    -- of CludesUIQoL_ForeverStats.lua instead (FV is nil on retail).
    local FV = mod.FvStats
    local FV_STAT = FV and FV.byKey
    if FV then
        DEFAULT_STAT_ORDER, VALID_STAT = FV.order, FV_STAT
    end

    local function SecondaryStatsOrder()
        local saved = CludesUI.QoLExtrasGet("secondaryStatsOrder")
        if type(saved) ~= "table" then
            return DEFAULT_STAT_ORDER
        end

        local sequence, added = {}, {}
        for _, settingKey in ipairs(saved) do
            if VALID_STAT[settingKey] and not added[settingKey] then
                added[settingKey] = true
                sequence[#sequence + 1] = settingKey
            end
        end
        for _, settingKey in ipairs(DEFAULT_STAT_ORDER) do
            if not added[settingKey] then
                sequence[#sequence + 1] = settingKey
            end
        end
        return sequence
    end
    CludesUI._secondaryStatsOrder = SecondaryStatsOrder
    -- Tertiaries keep the original default: the player's class color.

    -- SECRET STATS. In restricted content the stat getters return secret
    -- numbers. A secret refuses INSPECTION -- compare one, do arithmetic on
    -- one, or format one in Lua, and that errors -- but it renders perfectly
    -- through an engine sink. SetFormattedText is such a sink (see the CDM
    -- timer and the inspect sheet's M+ score), so every figure below is passed
    -- to it as an ARGUMENT against a template built only from clean data.
    -- That is what keeps the block live in combat instead of reading "?".
    --
    -- The one thing a secret still costs is measurement: GetStringWidth errors
    -- on a FontString that was fed one, so the block keeps its last known size
    -- until the values are readable again (see UpdateSecondaryStats).
    --
    -- Labels are interpolated INTO that template, so a "%" in a translation
    -- would become a stray format spec. Escape it.
    local function Esc(s)
        return (tostring(s):gsub("%%", "%%%%"))
    end

    -- Set when a figure is genuinely absent (nil) -- NOT when it is merely
    -- secret, which now renders fine.
    local statUnreadable = false

    -- Load-in settle heal: the login/zone-in window can outlast the first paint
    -- AND every stat event, leaving a nil figure reading "?" until gear swaps.
    -- There is no event for that settle, so a paint that saw one arms ONE
    -- bounded retry chain -- never a loop: the budget stops it, and a clean
    -- paint resets it.
    local _healPending = false
    local UpdateSecondaryStats

    local function ArmSecretHeal()
        if _healPending then
            return
        end
        local tries = statsPanel._secretHeals or 0
        if tries >= 5 then
            return
        end
        statsPanel._secretHeals = tries + 1
        _healPending = true
        C_Timer.After(2, function()
            _healPending = false
            UpdateSecondaryStats()
        end)
    end

    -- Latency sources for the attached rows. Local MS defaults to ON when the
    -- setting has never been written, matching the standalone counter.
    local function LatencySources()
        local _localMS = CludesUI.QoLExtrasGet("fpsShowLocalMS")
        local localShown = (_localMS == nil) and true or _localMS
        return CludesUI.QoLExtrasGet("fpsShowWorldMS"), localShown
    end

    -- Position authority. A center names a corner only once you know the size,
    -- so a CENTER/CENTER anchor walks a text-sized block sideways by half of
    -- every width change -- a digit on the latency, a row appearing -- and puts
    -- it somewhere new on each reload. This block stores an EDGE anchor
    -- instead, the convention the growth-direction bars already use, after
    -- which nothing about its size can move it.
    --
    -- Whole pixels: a center lands on a half pixel at odd sizes, and text drawn
    -- from a fractional origin is free to round either way.
    local function CornerFromCenter(cx, cy, wid, hgt)
        return floor(UIParent:GetWidth() / 2 + cx - wid / 2 + 0.5),
            floor(UIParent:GetHeight() / 2 + cy + hgt / 2 + 0.5)
    end
    CludesUI._secondaryStatsCorner = CornerFromCenter

    local function ApplyStatsPosition()
        -- Unlock mode owns positioning while a session is open.
        if not statsPanel or CludesUI._unlockActive then
            return
        end
        local place = CludesUI.QoLExtrasGet("secondaryStatsPos")
        if not (place and place.point) then
            return
        end
        -- Saved as a center by an earlier build. Resolve it once, at a size we
        -- know is real, and keep the corner from then on -- otherwise it would
        -- go on resolving to a different corner for the life of the profile.
        if place.point == "CENTER" and statsPanel._measured then
            local copy = {}
            for k, val in pairs(place) do
                copy[k] = val
            end
            copy.point, copy.relPoint = "TOPLEFT", "BOTTOMLEFT"
            copy.x, copy.y =
                CornerFromCenter(place.x or 0, place.y or 0, statsPanel:GetWidth(), statsPanel:GetHeight())
            CludesUI.QoLExtrasSet("secondaryStatsPos", copy)
            place = copy
        end
        statsPanel:ClearAllPoints()
        statsPanel:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x or 0, place.y or 0)
    end
    -- For the unlock element, registered in the FPS block below.
    CludesUI._secondaryStatsPin = ApplyStatsPosition

    function UpdateSecondaryStats()
        if not statsPanel or not statsPanel:IsShown() then
            return
        end
        statUnreadable = false
        if not statsPanel._classHex then
            -- Cache ONLY a resolved class color: caching the white fallback
            -- here left class-colored labels white for the whole session
            -- when the first paint beat the color system (login timing) --
            -- invisible against bright scenes. Unresolved = retry next
            -- update, white per-use below. issecretvalue FIRST: UnitClass
            -- returns a secret in restricted content and truthiness on it
            -- throws (a /reload inside an instance killed every update).
            local _, classTok = UnitClass("player")
            if issecretvalue(classTok) then
                classTok = nil
            end
            local colorCodes = classTok and CludesUI.GetClassColor(classTok)
            if colorCodes then
                statsPanel._classHex = format("%02x%02x%02x", colorCodes.r * 255, colorCodes.g * 255, colorCodes.b * 255)
            end
        end
        -- Label color mode: "palette" (multicolored, one hue per stat),
        -- "class" (default), or "custom". No mode saved: a stored custom
        -- color means the user was using it, so custom wins; otherwise class
        -- color, the pre-mode default look.
        local color = CludesUI.QoLExtrasGet("secondaryStatsColor")
        local mode = CludesUI.QoLExtrasGet("secondaryStatsColorMode") or (color and "custom" or "class")
        local customColorHex
        if mode == "custom" and color then
            customColorHex = format("%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
        elseif mode == "class" then
            -- Per-use white fallback while the class color is still
            -- resolving; never cached, so the real color takes over.
            customColorHex = statsPanel._classHex or "ffffff"
        end

        -- Retail's ratings and their raw figures; WoW Forever has none of
        -- them, so nothing here is read there.
        local crit, critCR, haste, hasteCR
        local mastery, vers
        local bothShown, showRawOnly, showRawValues
        local critRaw, hasteRaw, masteryRaw, versRaw
        if not FV then
            crit, critCR = CludesUI.PlayerCritChance()
            haste, hasteCR = UnitSpellHaste("player"), CR_HASTE_MELEE
            mastery = GetMasteryEffect()
            -- Versatility is the only row built by ADDING two getters, and addition
            -- is what a secret refuses -- so under restriction the real total is
            -- not computable here. Blizzard's pane still shows it (its code reads
            -- true values; an addon gets secrets), which is why the two disagreed.
            -- Falling back to the rating alone silently drops the non-rating bonus,
            -- so remember the last clean total and show that instead; "?" is the
            -- floor when there has never been a clean read.
            local versRating = GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
            local versBase = GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE) or 0
            if issecretvalue(versRating) or issecretvalue(versBase) then
                vers = statsPanel._versLastClean -- nil until one exists -> "?"
            else
                vers = versRating + versBase
                statsPanel._versLastClean = vers
            end
            bothShown = CludesUI.QoLExtrasGet("showSecondaryStatsBoth")
            showRawOnly = not bothShown and CludesUI.QoLExtrasGet("showSecondaryStatsRaw")
            showRawValues = showRawOnly or bothShown
            if showRawValues then
                critRaw = GetCombatRating(critCR)
                hasteRaw = GetCombatRating(hasteCR)
                masteryRaw = GetCombatRating(CR_MASTERY)
                versRaw = GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)
            end
        end

        -- One template line per row, plus the figures to fill it. Nothing here
        -- reads a figure -- see the SECRET STATS note above.
        local rowList, vals = {}, {}
        local anySecret = false
        -- Values are white unless Colored Values is on, which colors
        -- each value with its row so the stat reads as one piece.
        local coloredPct = CludesUI.QoLExtrasGet("coloredPercentages")
        local abbreviateLabels = CludesUI.QoLExtrasGet("secondaryStatsAbbreviateLabels")
        local function Label(long, short)
            return abbreviateLabels and short or CludesUI.L(long)
        end
        -- fmt: the figure's format when no raw rating is shown (a percentage
        -- unless given).
        local function Row(hex, labelText, value, raw, formatStr)
            local body, first, second
            if showRawOnly then
                body, first = "%.0f", raw
            elseif bothShown then
                body, first, second = "%.0f (%.2f%%)", raw, value
            else
                body, first = formatStr or "%.2f%%", value
            end
            -- The selected figures travel as arguments so secret values are
            -- never inspected. A nil test is safe on a secret.
            if first == nil or (bothShown and second == nil) then
                statUnreadable = true
                body = "?"
            else
                if issecretvalue(first) then
                    anySecret = true
                end
                vals[#vals + 1] = first
                if bothShown then
                    if issecretvalue(second) then
                        anySecret = true
                    end
                    vals[#vals + 1] = second
                end
            end
            rowList[#rowList + 1] = format(
                "|cff%s%s:|r%s|cff%s%s|r",
                hex,
                Esc(labelText),
                LABEL_GAP,
                coloredPct and hex or "ffffff",
                body
            )
        end
        -- Sibling for rows whose body is already colored (the FPS pair below):
        -- Row would wrap it in a second span, and |r restores one level only.
        -- Those bodies apply Colored Values themselves, per figure, and are
        -- built from figures that are never secret -- so they carry no
        -- placeholder and must be escaped like any other template text.
        local function RawRow(hex, labelText, body)
            rowList[#rowList + 1] = format("|cff%s%s:|r%s%s", hex, Esc(labelText), LABEL_GAP, Esc(body))
        end
        local hiddenStats = CludesUI.QoLExtrasGet("secondaryStatsHidden")
        if type(hiddenStats) ~= "table" then
            hiddenStats = nil
        end
        -- The tertiaries (leech/avoidance/speed) are retail ratings too.
        local hasVisibleTertiary = false
        local tertiaryHex, leechTxt, avoidTxt, speedTxt
        local leechRaw, avoidanceRaw, speedRaw
        if not FV then
            hasVisibleTertiary = not (
                hiddenStats
                and hiddenStats.leech
                and hiddenStats.avoidance
                and hiddenStats.speed
            )
            if hasVisibleTertiary then
                local tertiaryRGB = CludesUI.QoLExtrasGet("tertiaryStatsColor")
                local tmode = CludesUI.QoLExtrasGet("tertiaryStatsColorMode") or (tertiaryRGB and "custom" or "class")
                tertiaryHex = (tmode == "custom" and tertiaryRGB)
                        and format("%02x%02x%02x", tertiaryRGB.r * 255, tertiaryRGB.g * 255, tertiaryRGB.b * 255)
                    or statsPanel._classHex
                    or "ffffff"

                leechTxt = GetLifesteal()
                avoidTxt = GetAvoidance()
                speedTxt = GetSpeed()
                if showRawValues then
                    leechRaw = GetCombatRating(CR_LIFESTEAL)
                    avoidanceRaw = GetCombatRating(CR_AVOIDANCE)
                    speedRaw = GetCombatRating(CR_SPEED)
                end
            end
        end

        for _, settingKey in ipairs(SecondaryStatsOrder()) do
            if not (hiddenStats and hiddenStats[settingKey]) then
                local fv = FV_STAT and FV_STAT[settingKey]
                if fv then
                    Row(customColorHex or fv.hex, Label(fv.label, fv.short), fv.get(), nil, fv.fmt)
                elseif settingKey == "crit" then
                    Row(customColorHex or STAT_HEX.crit, Label("Crit", "C"), crit, critRaw)
                elseif settingKey == "haste" then
                    Row(customColorHex or STAT_HEX.haste, Label("Haste", "H"), haste, hasteRaw)
                elseif settingKey == "mastery" then
                    Row(customColorHex or STAT_HEX.mastery, Label("Mastery", "M"), mastery, masteryRaw)
                elseif settingKey == "vers" then
                    Row(customColorHex or STAT_HEX.vers, Label("Vers", "V"), vers, versRaw)
                elseif settingKey == "leech" then
                    Row(tertiaryHex, Label("Leech", "L"), leechTxt, leechRaw)
                elseif settingKey == "avoidance" then
                    Row(tertiaryHex, Label("Avoidance", "A"), avoidTxt, avoidanceRaw)
                elseif settingKey == "speed" then
                    Row(tertiaryHex, Label("Speed", "S"), speedTxt, speedRaw)
                end
            end
        end

        -- FPS and latency, drawn here rather than by the standalone counter
        -- while Attach to Secondary Stats is on. Label color comes from the FPS
        -- swatch, falling back to class color like the other groups.
        if CludesUI.QoLExtrasGet("fpsAttachToStats") and CludesUI.QoLExtrasGet("showFPS") then
            -- Same resolver the standalone counter uses, so the two owners
            -- cannot disagree about the color.
            local fr, fg, fallback = CludesUI._fpsColorRGB()
            local fpsHex = format("%02x%02x%02x", fr * 255, fg * 255, fallback * 255)
            -- The figures follow Colored Values with the rest of the block.
            -- The "(world)"/"(local)" suffixes and the divider stay dim either
            -- way -- they are annotations, not values.
            local VAL = "|cff" .. (coloredPct and fpsHex or "ffffff")

            RawRow(fpsHex, CludesUI.L("FPS"), VAL .. floor(GetFramerate() + 0.5) .. "|r")

            local showWorld, localShown = LatencySources()
            if showWorld or localShown then
                local noLabel = CludesUI.QoLExtrasGet("fpsHideLabel")
                local _, _, latHome, latWorld = GetNetStats()
                local parts = {}
                if showWorld then
                    parts[#parts + 1] = VAL
                        .. latWorld
                        .. " ms|r"
                        .. (noLabel and "" or (DIM .. " (world)|r"))
                end
                if localShown then
                    parts[#parts + 1] = VAL
                        .. latHome
                        .. " ms|r"
                        .. (noLabel and "" or (DIM .. " (local)|r"))
                end
                -- The divider takes LABEL_GAP on both sides. "||" renders one
                -- literal pipe.
                RawRow(
                    fpsHex,
                    CludesUI.L("Latency"),
                    table.concat(parts, LABEL_GAP .. DIM .. "||" .. "|r" .. LABEL_GAP)
                )
            end
        end

        -- The engine fills the template. This is the whole point: a secret
        -- figure is never read in Lua, so it draws its true number.
        statsLabel:SetFormattedText(table.concat(rowList, "\n"), unpack(vals))

        -- Measuring is the one thing a secret costs us: GetStringWidth errors
        -- on a FontString that was fed one. Keep the last known size until the
        -- figures are readable again -- only the unlock drag box and the corner
        -- migration below read it, and both can wait for the end of combat
        -- (PLAYER_REGEN_ENABLED is registered, so that repaint comes).
        local staleSize = false
        if not anySecret then
            -- Clean figures do NOT buy a clean measurement: the metrics belong
            -- to the last LAID OUT string, so the first paint AFTER a secret
            -- one still hands back a secret width -- which is what errored
            -- here. Test what the arithmetic is about to touch, not what was
            -- fed in.
            local wid, hgt = statsLabel:GetStringWidth(), statsLabel:GetStringHeight()
            if issecretvalue(wid) or issecretvalue(hgt) then
                -- Nothing left to wait on but the next layout, and there is no
                -- event for that -- so borrow the bounded retry chain below.
                staleSize = true
            else
                statsPanel:SetSize(wid + 2, hgt + 2)
                -- The block has now been measured at a real size, which is what
                -- a stored center needs before it can be resolved to a corner.
                -- Only worth a call while one is still stored; the migration
                -- runs once.
                statsPanel._measured = true
                local savedPos = CludesUI.QoLExtrasGet("secondaryStatsPos")
                if savedPos and savedPos.point == "CENTER" then
                    ApplyStatsPosition()
                end
            end
        end

        -- A missing figure and a not-yet-relaid-out measurement both heal on
        -- their own clock rather than an event, so they share the one chain.
        -- anySecret deliberately does NOT arm it: that clears on
        -- PLAYER_REGEN_ENABLED, and spending the budget on a whole fight would
        -- leave none for the settle that actually needs it.
        if statUnreadable or staleSize then
            ArmSecretHeal()
        else
            statsPanel._secretHeals = nil
        end
    end

    -- The stat rows redraw on events; FPS and latency need their own clock.
    -- Rebuilt on every apply so the interval takes effect and never doubles up.
    local function RefreshFPSTicker()
        if not statsPanel then
            return
        end
        if statsPanel._fpsTicker then
            statsPanel._fpsTicker:Cancel()
            statsPanel._fpsTicker = nil
        end
        if not (CludesUI.QoLExtrasGet("fpsAttachToStats") and CludesUI.QoLExtrasGet("showFPS")) then
            return
        end
        statsPanel._fpsTicker =
            C_Timer.NewTicker(CludesUI.QoLExtrasGet("fpsUpdateInterval") or 3, UpdateSecondaryStats)
    end

    local function ApplySecondaryStats()
        local isEnabled = CludesUI.QoLExtrasGet("showSecondaryStats")
        if not isEnabled then
            if statsPanel then
                statsPanel:Hide()
                statsPanel:UnregisterAllEvents()
                if statsPanel._fpsTicker then
                    statsPanel._fpsTicker:Cancel()
                    statsPanel._fpsTicker = nil
                end
            end
            return
        end
        if not statsPanel then
            statsPanel = CreateFrame("Frame", "CUI_SecondaryStats", UIParent)
            statsPanel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 12, -12)
            statsPanel:SetSize(160, 60)
            statsPanel:SetFrameStrata("LOW")
            statsLabel = statsPanel:CreateFontString(nil, "OVERLAY")
            statsLabel:SetPoint("TOPLEFT")
            statsLabel:SetJustifyH("LEFT")
        end
        if statsLabel then
            local font = CludesUI.ResolveFontName(CludesUI.GetFontsDB().global)
            CludesUI.PrimeFontShadow(statsLabel, CludesUI.GetFontUseShadow("extras"))
            statsLabel:SetFont(font, 12, CludesUI.GetFontOutlineFlag("extras"))
            statsLabel:SetSpacing(ROW_GAP)
        end
        ApplyStatsPosition()
        local place = CludesUI.QoLExtrasGet("secondaryStatsPos")
        local scale = (place and place.scale) or 1.0
        if statsLabel then
            local font = CludesUI.ResolveFontName(CludesUI.GetFontsDB().global)
            local fontSize = math.floor(12 * scale + 0.5)
            CludesUI.PrimeFontShadow(statsLabel, CludesUI.GetFontUseShadow("extras"))
            statsLabel:SetFont(font, fontSize, CludesUI.GetFontOutlineFlag("extras"))
            -- Row gap scales with the font so the block keeps its rhythm.
            statsLabel:SetSpacing(math.floor(ROW_GAP * scale + 0.5))
        end
        -- Unit-scoped events filter at the engine (player only); a plain RegisterEvent would deliver every raid member's stat changes.
        for _, ev in ipairs({
            "UNIT_STATS",
            "UNIT_ATTACK_POWER",
            "UNIT_RANGED_ATTACK_POWER",
            "UNIT_SPELL_HASTE",
        }) do
            statsPanel:RegisterUnitEvent(ev, "player")
        end
        -- WoW Forever: melee and ranged haste change without UNIT_SPELL_HASTE,
        -- and auras move regen, armor, resistances and run speed with no stat
        -- event of their own; the character pane listens to the same pair.
        if FV then
            statsPanel:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
            statsPanel:RegisterUnitEvent("UNIT_RANGEDDAMAGE", "player")
            statsPanel:RegisterUnitEvent("UNIT_AURA", "player")
            statsPanel:RegisterUnitEvent("UNIT_RESISTANCES", "player")
        end
        for _, ev in ipairs({
            "COMBAT_RATING_UPDATE",
            "PLAYER_EQUIPMENT_CHANGED",
            "MASTERY_UPDATE",
            "SPELL_POWER_CHANGED",
            "PLAYER_DAMAGE_DONE_MODS",
            "PLAYER_SPECIALIZATION_CHANGED",
            "PLAYER_ENTERING_WORLD",
            -- Combat-scoped stat secrecy lifts here. The figures themselves
            -- stay live through a fight (they render as arguments), but the
            -- block cannot be MEASURED while any of them is secret -- so this
            -- is the edge that catches its footprint back up.
            "PLAYER_REGEN_ENABLED",
        }) do
            statsPanel:RegisterEvent(ev)
        end
        local _statsPending = false
        -- No runtime unit filter: unit events are engine-filtered to player above;
        -- a `unit ~= "player"` check would wrongly swallow PLAYER_EQUIPMENT_CHANGED, whose first arg is a slot id.
        --
        -- Leading edge, then a trailing pass. COMBAT_RATING_UPDATE fires many
        -- times a second in combat, so the window has to stay -- but spending it
        -- BEFORE the first redraw is what put the block half a second behind the
        -- character sheet. Redraw at once instead, and again once the burst has
        -- settled, for the same two updates per window.
        statsPanel:SetScript("OnEvent", function()
            if _statsPending then
                return
            end
            _statsPending = true
            UpdateSecondaryStats()
            C_Timer.After(0.5, function()
                _statsPending = false
                UpdateSecondaryStats()
            end)
        end)
        statsPanel:Show()
        RefreshFPSTicker()
        UpdateSecondaryStats()
    end
    CludesUI._applySecondaryStats = ApplySecondaryStats

    -- The frame is sized from the text on every update, but only while it is
    -- shown. Catch it up when unlock mode opens so the mover box matches.
    CludesUI:RegisterUnlockModeListener("CUI_SecondaryStats", function(opening)
        if opening then
            UpdateSecondaryStats()
        end
    end)

    CludesUI._getSecondaryStatsFrame = function()
        if not statsPanel then
            ApplySecondaryStats()
        end
        return statsPanel
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplySecondaryStats()
    end)
end

-------------------------------------------------------------------------------
--  FPS Counter
-------------------------------------------------------------------------------
do
    local fpsPanel
    local floor = math.floor

    -- Resolved readout color, shared by this frame and the attached rows so
    -- the two owners can never disagree. No mode saved means "custom", which
    -- with no stored color is white -- the look before the mode existed, so
    -- an existing profile is unchanged.
    local function FPSColorRGB()
        if CludesUI.QoLExtrasGet("fpsColorMode") == "class" then
            -- issecretvalue FIRST: UnitClass returns a secret in restricted
            -- content and truthiness on one throws.
            local _, classTok = UnitClass("player")
            if issecretvalue(classTok) then
                classTok = nil
            end
            local colorCodes = classTok and CludesUI.GetClassColor(classTok)
            if colorCodes then
                return colorCodes.r, colorCodes.g, colorCodes.b, 1
            end
            return 1, 1, 1, 1 -- class color not resolved yet; retry next update
        end
        local color = CludesUI.QoLExtrasGet("fpsColor")
        if color then
            return color.r or 1, color.g or 1, color.b or 1, color.a or 1
        end
        return 1, 1, 1, 1
    end
    CludesUI._fpsColorRGB = FPSColorRGB

    local function CreateFPSCounter()
        if fpsPanel then
            return
        end
        local FONT = CludesUI.GetFontPath("extras")
        local FONT_SIZE = CludesUI.QoLExtrasGet("fpsTextSize") or 12
        local LABEL_SIZE = FONT_SIZE - 2
        fpsPanel = CreateFrame("Frame", "CUI_FPSCounter", UIParent)
        fpsPanel:SetSize(60, 20)
        fpsPanel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 10, -10)
        fpsPanel:SetFrameStrata("MEDIUM")
        fpsPanel:SetFrameLevel(10)
        fpsPanel:EnableMouse(false)

        local function MakeFS(px)
            local frame = fpsPanel:CreateFontString(nil, "OVERLAY")
            CludesUI.PrimeFontShadow(frame, CludesUI.GetFontUseShadow("extras"))
            frame:SetFont(FONT, px, CludesUI.GetFontOutlineFlag("extras"))
            frame:SetTextColor(1, 1, 1, 1)
            return frame
        end

        local fpsText = MakeFS(FONT_SIZE)
        fpsText:SetPoint("LEFT")
        fpsPanel._text = fpsText

        local DIV_W, DIV_H = 1, 10
        local DIV_PAD = 6

        local function MakeDivider()
            local skinData = fpsPanel:CreateTexture(nil, "OVERLAY")
            skinData:SetColorTexture(1, 1, 1, 0.25)
            skinData:SetSize(DIV_W, DIV_H)
            return skinData
        end

        local divWorld = MakeDivider()
        local worldValueText = MakeFS(FONT_SIZE)
        local worldLabelText = MakeFS(LABEL_SIZE)
        fpsPanel._divWorld = divWorld
        fpsPanel._textWorld = worldValueText
        fpsPanel._lblWorld = worldLabelText

        local divLocal = MakeDivider()
        local localValueText = MakeFS(FONT_SIZE)
        local localLabelText = MakeFS(LABEL_SIZE)
        fpsPanel._divLocal = divLocal
        fpsPanel._textLocal = localValueText
        fpsPanel._lblLocal = localLabelText

        local function UpdateFPS(self)
            local cr, cg, callback, ca = CludesUI._fpsColorRGB()
            fpsText:SetTextColor(cr, cg, callback, ca)
            worldValueText:SetTextColor(cr, cg, callback, ca)
            worldLabelText:SetTextColor(cr, cg, callback, ca * 0.6)
            localValueText:SetTextColor(cr, cg, callback, ca)
            localLabelText:SetTextColor(cr, cg, callback, ca * 0.6)
            divWorld:SetColorTexture(cr, cg, callback, ca * 0.35)
            divLocal:SetColorTexture(cr, cg, callback, ca * 0.35)

            local fps = floor(GetFramerate() + 0.5)
            fpsText:SetText(fps .. " fps")

            local showWorld = CludesUI.QoLExtrasGet("fpsShowWorldMS")
            local _localMS = CludesUI.QoLExtrasGet("fpsShowLocalMS")
            local localShown = (_localMS == nil) and true or _localMS
            local noLabel = CludesUI.QoLExtrasGet("fpsHideLabel")
            local _, _, latHome, latWorld = GetNetStats()

            fpsText:ClearAllPoints()
            fpsText:SetPoint("LEFT", fpsPanel, "LEFT", 0, 0)
            local anchorFrame = fpsText

            if showWorld then
                worldValueText:SetText(latWorld .. " ms")
                divWorld:ClearAllPoints()
                divWorld:SetPoint("LEFT", anchorFrame, "RIGHT", DIV_PAD, 0)
                divWorld:Show()
                worldValueText:ClearAllPoints()
                worldValueText:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                worldValueText:Show()
                if noLabel then
                    worldLabelText:Hide()
                    anchorFrame = worldValueText
                else
                    worldLabelText:SetText("(world)")
                    worldLabelText:ClearAllPoints()
                    worldLabelText:SetPoint("LEFT", worldValueText, "RIGHT", 3, 0)
                    worldLabelText:Show()
                    anchorFrame = worldLabelText
                end
            else
                divWorld:Hide()
                worldValueText:Hide()
                worldLabelText:Hide()
            end

            if localShown then
                localValueText:SetText(latHome .. " ms")
                divLocal:ClearAllPoints()
                divLocal:SetPoint("LEFT", anchorFrame, "RIGHT", DIV_PAD, 0)
                divLocal:Show()
                localValueText:ClearAllPoints()
                localValueText:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                localValueText:Show()
                if noLabel then
                    localLabelText:Hide()
                    anchorFrame = localValueText
                else
                    localLabelText:SetText("(local)")
                    localLabelText:ClearAllPoints()
                    localLabelText:SetPoint("LEFT", localValueText, "RIGHT", 3, 0)
                    localLabelText:Show()
                    anchorFrame = localLabelText
                end
            else
                divLocal:Hide()
                localValueText:Hide()
                localLabelText:Hide()
            end

            local totalW = fpsText:GetStringWidth()
            if showWorld then
                totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + worldValueText:GetStringWidth()
                if not noLabel then
                    totalW = totalW + 3 + worldLabelText:GetStringWidth()
                end
            end
            if localShown then
                totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + localValueText:GetStringWidth()
                if not noLabel then
                    totalW = totalW + 3 + localLabelText:GetStringWidth()
                end
            end
            self:SetSize(totalW + 4, 20)
        end

        local elapsed = 0
        fpsPanel:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed < (self._interval or 3) then
                return
            end
            elapsed = 0
            UpdateFPS(self)
        end)
        fpsPanel._updateNow = function()
            elapsed = 0
            UpdateFPS(fpsPanel)
        end
        fpsPanel:Hide()
    end

    -- Attached = drawn as extra rows in the Secondary Stats block rather than by
    -- this frame. Requires that block to be on, so turning it off pops the
    -- counter back to standalone instead of making it disappear.
    local function IsAttached()
        return (CludesUI.QoLExtrasGet("fpsAttachToStats") and CludesUI.QoLExtrasGet("showSecondaryStats"))
                and true
            or false
    end
    CludesUI._fpsAttachedToStats = IsAttached

    CludesUI._applyFPSCounter = function()
        local shouldShow = CludesUI.QoLExtrasGet("showFPS") and not IsAttached()
        if shouldShow then
            CreateFPSCounter()
            fpsPanel._interval = CludesUI.QoLExtrasGet("fpsUpdateInterval") or 3
            local size = CludesUI.QoLExtrasGet("fpsTextSize") or 12
            local lblSz = size - 2
            local fontPath = CludesUI.GetFontPath("extras")
            local outFrame = CludesUI.GetFontOutlineFlag("extras")
            if fpsPanel._text then
                fpsPanel._text:SetFont(fontPath, size, outFrame)
            end
            if fpsPanel._textWorld then
                fpsPanel._textWorld:SetFont(fontPath, size, outFrame)
            end
            if fpsPanel._textLocal then
                fpsPanel._textLocal:SetFont(fontPath, size, outFrame)
            end
            if fpsPanel._lblWorld then
                fpsPanel._lblWorld:SetFont(fontPath, lblSz, outFrame)
            end
            if fpsPanel._lblLocal then
                fpsPanel._lblLocal:SetFont(fontPath, lblSz, outFrame)
            end
            local place = CludesUI.QoLExtrasGet("fpsPos")
            if place and place.point then
                if place.scale then
                    pcall(function()
                        fpsPanel:SetScale(place.scale)
                    end)
                end
                fpsPanel:ClearAllPoints()
                fpsPanel:SetPoint(
                    place.point,
                    UIParent,
                    place.relPoint or place.point,
                    place.x or 0,
                    place.y or 0
                )
            end
            fpsPanel._updateNow()
            fpsPanel:Show()
        elseif fpsPanel then
            fpsPanel:Hide()
        end
    end

    local RegisterFPSUnlockElement -- forward: defined below

    -- A settings change can move the readout between its two owners, so every
    -- FPS option writes through here rather than calling one side directly.
    CludesUI._applyFPSDisplay = function()
        if CludesUI._applyFPSCounter then
            CludesUI._applyFPSCounter()
        end
        if CludesUI._applySecondaryStats then
            CludesUI._applySecondaryStats()
        end
        -- Re-registering is how an open unlock session gains or loses a mover,
        -- so a showFPS flip (options toggle or the keybind, both of which land
        -- here) takes effect without leaving and re-entering.
        if CludesUI._unlockActive then
            RegisterFPSUnlockElement()
        end
    end

    RegisterFPSUnlockElement = function()
        local MK = CludesUI.MakeUnlockElement
        if not MK then
            return
        end
        CludesUI:RegisterUnlockElements({
            MK({
                key = "CUI_FPS",
                label = "FPS Counter",
                group = "General",
                order = 700,
                -- Off, or dragged by the Secondary Stats element while
                -- attached. Read live, so detaching restores the mover without
                -- re-registering.
                isHidden = function()
                    return not CludesUI.QoLExtrasGet("showFPS") or IsAttached()
                end,
                getFrame = function()
                    if not fpsPanel then
                        CreateFPSCounter()
                    end
                    return fpsPanel
                end,
                getSize = function()
                    if fpsPanel then
                        return fpsPanel:GetWidth(), fpsPanel:GetHeight()
                    end
                    return 80, 20
                end,
                noResize = true,
                savePos = function(settingKey, anchorPoint, relPoint, posX, posY)
                    if not anchorPoint then
                        return
                    end
                    CludesUI.QoLExtrasSet(
                        "fpsPos",
                        { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    )
                    if fpsPanel and not CludesUI._unlockActive then
                        fpsPanel:ClearAllPoints()
                        fpsPanel:SetPoint(
                            anchorPoint,
                            UIParent,
                            relPoint or anchorPoint,
                            posX or 0,
                            posY or 0
                        )
                    end
                end,
                loadPos = function()
                    return CludesUI.QoLExtrasGet("fpsPos")
                end,
                clearPos = function()
                    CludesUI.QoLExtrasSet("fpsPos", nil)
                end,
                applyPos = function()
                    if not fpsPanel then
                        return
                    end
                    local place = CludesUI.QoLExtrasGet("fpsPos")
                    if place and place.point then
                        fpsPanel:ClearAllPoints()
                        fpsPanel:SetPoint(
                            place.point,
                            UIParent,
                            place.relPoint or place.point,
                            place.x or 0,
                            place.y or 0
                        )
                    end
                end,
            }),
        })
    end
    C_Timer.After(2, RegisterFPSUnlockElement)

    C_Timer.After(2.5, function()
        local MK = CludesUI.MakeUnlockElement
        CludesUI:RegisterUnlockElements({
            MK({
                key = "CUI_SecondaryStats",
                label = "Secondary Stats",
                group = "General",
                order = 710,
                getFrame = function()
                    local frame = CludesUI._getSecondaryStatsFrame and CludesUI._getSecondaryStatsFrame()
                    return frame
                end,
                getSize = function()
                    local frame = CludesUI._getSecondaryStatsFrame and CludesUI._getSecondaryStatsFrame()
                    if frame then
                        return frame:GetWidth(), frame:GetHeight()
                    end
                    return 160, 60
                end,
                noResize = true,
                -- Self-positioning: makes NotifyElementResized call applyPos
                -- below rather than re-applying a stored center over the top.
                noInitHook = true,
                savePos = function(settingKey, anchorPoint, relPoint, posX, posY)
                    if not anchorPoint then
                        return
                    end
                    -- Scale lives in this same table; carry it over so a drag doesn't wipe it.
                    local previous = CludesUI.QoLExtrasGet("secondaryStatsPos")
                    local newPos = {
                        point = anchorPoint,
                        relPoint = relPoint,
                        x = posX,
                        y = posY,
                        scale = previous and previous.scale,
                    }
                    -- Rebase the center unlock mode hands back onto the corner
                    -- it currently resolves to, and store THAT -- a center would
                    -- name a different corner the moment a figure gains a digit.
                    -- Resolved against the handed-over center, not the frame's
                    -- own point, which on Save & Exit may not have moved yet.
                    local frame = CludesUI._getSecondaryStatsFrame and CludesUI._getSecondaryStatsFrame()
                    if
                        frame
                        and anchorPoint == "CENTER"
                        and (relPoint or "CENTER") == "CENTER"
                        and CludesUI._secondaryStatsCorner
                    then
                        newPos.point, newPos.relPoint = "TOPLEFT", "BOTTOMLEFT"
                        newPos.x, newPos.y =
                            CludesUI._secondaryStatsCorner(posX or 0, posY or 0, frame:GetWidth(), frame:GetHeight())
                    end
                    CludesUI.QoLExtrasSet("secondaryStatsPos", newPos)
                    if not CludesUI._unlockActive and CludesUI._secondaryStatsPin then
                        CludesUI._secondaryStatsPin()
                    end
                end,
                loadPos = function()
                    return CludesUI.QoLExtrasGet("secondaryStatsPos")
                end,
                clearPos = function()
                    CludesUI.QoLExtrasSet("secondaryStatsPos", nil)
                end,
                -- NotifyElementResized calls this after every resize. Re-applying
                -- an edge anchor at a new size is a no-op, which is the point.
                applyPos = function()
                    if CludesUI._secondaryStatsPin then
                        CludesUI._secondaryStatsPin()
                    end
                end,
            }),
        })
    end)

    local fpsBind = CreateFrame("Button", "CUI_FPSBindBtn", UIParent)
    fpsBind:Hide()
    fpsBind:SetScript("OnClick", function()
        CludesUI.QoLExtrasSet("showFPS", not CludesUI.QoLExtrasGet("showFPS"))
        -- The keybind has to toggle whichever owner is drawing the readout.
        CludesUI._applyFPSDisplay()
    end)

    C_Timer.After(1, function()
        if CludesUI.QoLExtrasGet("showFPS") then
            CludesUI._applyFPSDisplay()
        end
        local function ApplyFPSBind()
            if CludesUIDB and CludesUIDB.fpsToggleKey then
                SetOverrideBindingClick(fpsBind, true, CludesUIDB.fpsToggleKey, "CUI_FPSBindBtn")
            end
        end
        if InCombatLockdown() then
            mod.CombatQueue.Defer("FPSBind", ApplyFPSBind)
        else
            ApplyFPSBind()
        end
    end)
end

-------------------------------------------------------------------------------
--  Environment Ping keybind: while the key is held, a left click in the world
--  sends "/ping [@cursor]" (SendMacroPing's point branch: the spot under the
--  cursor, never a unit, whatever the Ping Target setting; no CVar is written).
--  The hold button owns the BUTTON1 claim and must stay a separate frame from
--  the ping button: a click routed to the frame the held key is bound to
--  swallows that key's up edge, and the claim would never be released.
--  Nothing is built until a key is bound (applied at login by qolFrame).
-------------------------------------------------------------------------------
do
    local holdBtn, pingButton, bindOwner, holdBase

    local function Release()
        ClearOverrideBindings(holdBtn)
    end

    local function Build()
        pingButton = CreateFrame("Button", "CUI_EnvPingButton", UIParent, "SecureActionButtonTemplate")
        pingButton:RegisterForClicks("AnyDown")
        pingButton:SetAttribute("useOnKeyDown", true)
        pingButton:SetAttribute("type", "macro")
        pingButton:SetAttribute("macrotext", (SLASH_PING1 or "/ping") .. " [@cursor]")
        -- A key-up lost to alt-tab or a loading screen would leave every left
        -- click pinging: once the key is up, a ping releases the claim.
        pingButton:SetScript("PostClick", function()
            if holdBase and IsKeyDown(holdBase) then
                return
            end
            if InCombatLockdown() then
                mod.CombatQueue.Defer("EnvPingRelease", Release)
            else
                Release()
            end
        end)
        holdBtn = CreateFrame("Button", "CUI_EnvPingHoldButton", UIParent, "SecureHandlerClickTemplate")
        holdBtn:RegisterForClicks("AnyDown", "AnyUp")
        holdBtn:SetFrameRef("ping", pingButton)
        holdBtn:SetAttribute(
            "_onclick",
            [[
            if down then
                self:SetBindingClick(true, "BUTTON1", self:GetFrameRef("ping"))
            else
                self:ClearBindings()
            end
        ]]
        )
        bindOwner = CreateFrame("Frame")
    end

    function CludesUI._applyEnvPing()
        if InCombatLockdown() then
            mod.CombatQueue.Defer("EnvPing", CludesUI._applyEnvPing)
            return
        end
        local settingKey = CludesUIDB.envPingKey
        if not (settingKey or bindOwner) then
            return
        end
        if not bindOwner then
            Build()
        end
        ClearOverrideBindings(bindOwner)
        Release()
        holdBase = settingKey and settingKey:match("[^%-]+$")
        if settingKey then
            SetOverrideBindingClick(bindOwner, true, settingKey, "CUI_EnvPingHoldButton")
        end
    end
end

-------------------------------------------------------------------------------
--  Durability Warning
-------------------------------------------------------------------------------
do
    local durabilityAlert
    local function CreateDurabilityWarning()
        if durabilityAlert then
            return
        end

        durabilityAlert = CreateFrame("Frame", nil, UIParent)
        durabilityAlert:SetSize(400, 40)
        durabilityAlert:SetFrameStrata("HIGH")
        durabilityAlert:SetFrameLevel(50)
        durabilityAlert:EnableMouse(false)
        durabilityAlert:SetMouseClickEnabled(false)

        local fontStr = durabilityAlert:CreateFontString(nil, "OVERLAY")
        fontStr:SetFont(
            CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF",
            18,
            CludesUI.GetFontOutlineFlag("extras")
        )
        fontStr:SetPoint("CENTER")
        fontStr:SetText(CludesUI.L("Low Durability"))
        durabilityAlert._text = fontStr

        local function ApplySettings()
            durabilityAlert:ClearAllPoints()
            local place = CludesUIDB and CludesUIDB.durWarnPos
            if place and place.point then
                durabilityAlert:SetPoint(
                    place.point,
                    UIParent,
                    place.relPoint or place.point,
                    place.x or 0,
                    place.y or 250
                )
            else
                local yOff = CludesUIDB and CludesUIDB.durWarnYOffset or 250
                durabilityAlert:SetPoint("CENTER", UIParent, "CENTER", 0, yOff)
            end
            durabilityAlert:SetScale(1)

            local fontFile = CludesUI.GetFontPath("extras")
            local durSz = (CludesUIDB and CludesUIDB.durWarnTextSize) or 30
            fontStr:SetFont(fontFile, durSz, CludesUI.GetFontOutlineFlag("extras"))

            local color = CludesUIDB and CludesUIDB.durWarnColor
            if color then
                fontStr:SetTextColor(color.r, color.g, color.b, 1)
            else
                fontStr:SetTextColor(1, 0.27, 0.27, 1)
            end
        end
        durabilityAlert._applySettings = ApplySettings

        local animGroup = fontStr:CreateAnimationGroup()
        local fadeOutAnim = animGroup:CreateAnimation("Alpha")
        fadeOutAnim:SetFromAlpha(1)
        fadeOutAnim:SetToAlpha(0.3)
        fadeOutAnim:SetDuration(0.4)
        fadeOutAnim:SetOrder(1)
        local fadeInAnim = animGroup:CreateAnimation("Alpha")
        fadeInAnim:SetFromAlpha(0.3)
        fadeInAnim:SetToAlpha(1)
        fadeInAnim:SetDuration(0.4)
        fadeInAnim:SetOrder(2)
        animGroup:SetLooping("REPEAT")

        durabilityAlert._show = function(pct)
            ApplySettings()
            durabilityAlert._text:SetText(CludesUI.Lf("Low Durability (%d%%)", math.floor(pct)))
            durabilityAlert:Show()
            animGroup:Play()
        end

        durabilityAlert:SetScript("OnHide", function()
            animGroup:Stop()
        end)

        durabilityAlert:Hide()
    end

    CludesUI._applyDurWarn = function()
        CreateDurabilityWarning()
        durabilityAlert._applySettings()
    end
    CludesUI._durWarnApplySettings = CludesUI._applyDurWarn

    CludesUI._durWarnPreview = function()
        CreateDurabilityWarning()
        durabilityAlert._show(25)
        durabilityAlert._text:SetText(CludesUI.L("Low Durability (Preview)"))
    end

    CludesUI._durWarnHidePreview = function()
        if durabilityAlert then
            durabilityAlert:Hide()
        end
    end

    local repairAlert = CreateFrame("Frame", nil, UIParent)

    local function CheckDurabilityAndShow()
        if not CludesUIDB then
            return
        end
        if CludesUIDB.repairWarning == false then
            if durabilityAlert then
                durabilityAlert:Hide()
            end
            return
        end
        if InCombatLockdown() then
            return
        end

        -- WoW Forever: each throw spends one point of a thrown weapon's
        -- durability, so it counts remaining throws rather than wear.
        -- Skipped unless the player turned Ignore Thrown Weapons off.
        local thrownSlot
        if CludesUI.IS_FOREVER and CludesUIDB.durWarnIgnoreThrown ~= false then
            local rangedSlot = GetInventorySlotInfo("RangedSlot")
            local itemId = rangedSlot and GetInventoryItemID("player", rangedSlot)
            if itemId then
                local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemId)
                if classID == Enum.ItemClass.Weapon and subclassID == Enum.ItemWeaponSubclass.Thrown then
                    thrownSlot = rangedSlot
                end
            end
        end

        local lowestDur = 100
        for slotId = 1, 18 do
            local current, mx = GetInventoryItemDurability(slotId)
            if current and mx and mx > 0 and slotId ~= thrownSlot then
                local pct = (current / mx) * 100
                if pct < lowestDur then
                    lowestDur = pct
                end
            end
        end

        if lowestDur < (CludesUIDB.durWarnThreshold or 40) then
            CreateDurabilityWarning()
            durabilityAlert._show(lowestDur)
        elseif durabilityAlert then
            durabilityAlert:Hide()
        end
    end

    -- Durability + alert events land together per damaged slot; one check
    -- after the frame settles (the check itself returns in combat, so a flush
    -- landing after PLAYER_REGEN_DISABLED cannot re-show the warning).
    local durCheckPending = false
    local function FlushDurabilityCheck()
        durCheckPending = false
        CheckDurabilityAndShow()
    end
    repairAlert:SetScript("OnEvent", function(_, eventName)
        if eventName == "PLAYER_REGEN_DISABLED" then
            if durabilityAlert then
                durabilityAlert:Hide()
            end
            return
        end
        if durCheckPending then
            return
        end
        durCheckPending = true
        C_Timer.After(0, FlushDurabilityCheck)
    end)

    -- Events registered only while enabled; toggle re-syncs live, and one immediate check on enable surfaces an already-low item.
    CludesUI._syncDurWarnEvents = function()
        if CludesUIDB and CludesUIDB.repairWarning == false then
            repairAlert:UnregisterAllEvents()
            if durabilityAlert then
                durabilityAlert:Hide()
            end
        else
            repairAlert:RegisterEvent("PLAYER_REGEN_ENABLED")
            repairAlert:RegisterEvent("PLAYER_REGEN_DISABLED")
            repairAlert:RegisterEvent("PLAYER_ENTERING_WORLD")
            repairAlert:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
            -- Self-repair items recalculate alerts without the durability event.
            repairAlert:RegisterEvent("UPDATE_INVENTORY_ALERTS")
            CheckDurabilityAndShow()
        end
    end
    CludesUI._syncDurWarnEvents()
end

-------------------------------------------------------------------------------
--  Pixel-Perfect UI Scale
-------------------------------------------------------------------------------
do
    local function ApplyPPUIScale()
        local scale = CludesUIDB and CludesUIDB.ppUIScale
        if not scale then
            return
        end
        local mf = CludesUI._mainFrame
        local panelScaleBefore
        if mf then
            panelScaleBefore = mf:GetEffectiveScale()
        end
        CludesUI.PP.SetUIScale(scale)
        if mf and panelScaleBefore then
            local newEff = UIParent:GetEffectiveScale()
            if newEff > 0 then
                mf:SetScale(panelScaleBefore / newEff)
            end
        end
    end

    CludesUI._applyPPUIScale = ApplyPPUIScale

    local ppScaleFrame = CreateFrame("Frame")
    ppScaleFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    ppScaleFrame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        ApplyPPUIScale()
    end)
end

-------------------------------------------------------------------------------
--  Disable Right Click Targeting
-------------------------------------------------------------------------------
do
    -- Safety net for a mouselook we started: the BUTTON2 override can vanish
    -- between the down and the up click (combat edge, or the engine dropping
    -- the mouseover while the button is held), and the up would then never
    -- reach this button, leaving mouselook on until a /reload. The registration
    -- itself is the "we own this mouselook" flag, so it can only undo our own
    -- start, never a toggle-mouselook addon's, and costs nothing when idle.
    local mlookGuard = CreateFrame("Frame")
    mlookGuard:SetScript("OnEvent", function(self)
        if IsMouseButtonDown("RightButton") then
            return
        end
        self:UnregisterEvent("GLOBAL_MOUSE_UP")
        if IsMouselooking() then
            MouselookStop()
        end
    end)

    local mlookBtn = CreateFrame("Button", "CUI_MouseLookBtn", UIParent)
    mlookBtn:RegisterForClicks("AnyDown", "AnyUp")
    mlookBtn:SetScript("OnClick", function(_, _, down)
        if down then
            mlookGuard:RegisterEvent("GLOBAL_MOUSE_UP")
            MouselookStart()
        else
            mlookGuard:UnregisterEvent("GLOBAL_MOUSE_UP")
            MouselookStop()
        end
    end)

    local statePanel = CreateFrame("Frame", "CUI_NoRightClickState", UIParent, "SecureHandlerStateTemplate")

    -- The binding is the OR of two states with separate writers:
    --   "mov" -- the secure state driver (engine-evaluated), BOTH arms [combat]:
    --            out of combat the driver's cached value sits at 0 and never
    --            re-pushes, so it can't stomp the Lua lane below.
    --   "rc"  -- Lua-pushed OOC enemy arm. [harm] matches capturable wild pets
    --            (no macro token excludes them), so the OOC verdict is computed
    --            in Lua where UnitIsWildBattlePet can veto -- the pet-capture
    --            right-click fix. In combat this lane is suspended; pets are
    --            not capturable there.
    -- Each snippet's clear defers to the other state, so the writers compose.
    -- "combatclear" zeroes rc from a SECURE snippet at combat entry: Lua cannot
    -- SetAttribute on this protected frame in lockdown, and a stale rc=1
    -- (pulled while hovering an enemy) would otherwise pin the bind on allies
    -- for the whole fight.
    -- "rcclear" zeroes rc the same way when the engine reports no harmful
    -- mouseover at all. UPDATE_MOUSEOVER_UNIT fires when a mouseover STARTS but
    -- never when it clears, so the Lua lane alone stays pinned at 1 after the
    -- last enemy hover and keeps BUTTON2 bound over quest objects and terrain
    -- until something else is hovered or the UI is reloaded. This rides
    -- SecureStateDriverManager's existing 0.2s sweep (it re-resolves every
    -- driver on a timer, not only on its registered events), so the clear costs
    -- no Lua per frame and needs no ticker of our own.
    local ONSTATE_MOV = [[
        if newstate == 1 then
            self:SetBindingClick(1, "BUTTON2", "CUI_MouseLookBtn")
        elseif (self:GetAttribute("state-rc") or 0) ~= 1 then
            self:ClearBindings()
        end
    ]]
    local ONSTATE_RC = [[
        if newstate == 1 then
            self:SetBindingClick(1, "BUTTON2", "CUI_MouseLookBtn")
        elseif (self:GetAttribute("state-mov") or 0) ~= 1 then
            self:ClearBindings()
        end
    ]]
    local ONSTATE_COMBATCLEAR = [[
        if newstate == 1 then
            self:SetAttribute("state-rc", 0)
        end
    ]]
    local ONSTATE_RCCLEAR = [[
        if newstate ~= 1 then
            self:SetAttribute("state-rc", 0)
        end
    ]]

    -- OOC enemy-arm verdict, edge-memoed: one attribute push per verdict CHANGE,
    -- not per hover. The memo reads the live attribute rather than a Lua cache,
    -- because the two secure snippets above also write it -- a private cache
    -- would go stale against them and swallow the next arming push. All reads
    -- are clean out of combat.
    local function PushRCState()
        local match = (
            UnitExists("mouseover")
            and not UnitIsDeadOrGhost("mouseover")
            and UnitCanAttack("player", "mouseover")
            and not UnitIsWildBattlePet("mouseover")
            and not UnitIsBattlePetCompanion("mouseover")
        )
                and 1
            or 0
        if match == (statePanel:GetAttribute("state-rc") or 0) then
            return
        end
        statePanel:SetAttribute("state-rc", match)
    end

    -- Registered only while the enemy toggle is on (feature-off users pay
    -- nothing); the mouseover event additionally drops during combat.
    local rightClickHover = CreateFrame("Frame")
    rightClickHover:SetScript("OnEvent", function(self, eventName)
        if eventName == "UPDATE_MOUSEOVER_UNIT" then
            PushRCState()
        elseif eventName == "PLAYER_REGEN_DISABLED" then
            self:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        elseif eventName == "PLAYER_REGEN_ENABLED" then
            self:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            PushRCState()
        end
    end)

    local function ApplyRightClickTarget()
        if InCombatLockdown() then
            mod.CombatQueue.Defer("RightClickTarget", ApplyRightClickTarget)
            return
        end
        local store = CludesUIDB
        local enemy = store and store.disableRightClickTarget
        local allyCombat = store and store.disableRightClickTargetAllyCombat
        if enemy or allyCombat then
            -- Capturable pets exist only in the outdoor world, so the Lua rc
            -- lane (and its mouseover listener) runs ONLY there. In instanced
            -- content the driver owns the enemy arm unconditionally -- pure
            -- engine evaluation, zero Lua per hover, and the OOC-between-pulls
            -- suppression still works. Re-applied on PLAYER_ENTERING_WORLD so
            -- the mode follows zone transitions.
            local inInstance = IsInInstance()
            local ruleLaneOn = enemy and not inInstance
            local macro = ""
            if enemy then
                macro = macro
                    .. (inInstance and "[@mouseover,harm,nodead]1;" or "[@mouseover,harm,nodead,combat]1;")
            end
            -- Ally arm = party/raid MEMBERS only. Plain [help] also matches any
            -- friendly-classified world object (a Warlock's Demonic Gateway),
            -- which captured the right-click that would have used it. The
            -- UNIT-relative conditionals [party]/[raid] test the @mouseover unit
            -- itself; [group] would test whether the PLAYER is grouped (the
            -- visibility-driver sense) and would neither free the gateway in a
            -- group nor guard anything solo. Both clauses so a 5-man and a raid
            -- read the same. Accepted: non-grouped friendlies are not guarded.
            if allyCombat then
                macro = macro
                    .. "[@mouseover,help,party,nodead,combat]1;[@mouseover,help,raid,nodead,combat]1;"
            end
            macro = macro .. "0"
            SecureStateDriverManager:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
            -- [combat] arms re-evaluate on combat edges even when the mouseover
            -- unit hasn't changed.
            SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_DISABLED")
            SecureStateDriverManager:RegisterEvent("PLAYER_REGEN_ENABLED")
            -- Handlers before drivers so the initial evaluation lands on them.
            statePanel:SetAttribute("_onstate-mov", ONSTATE_MOV)
            statePanel:SetAttribute("_onstate-rc", ONSTATE_RC)
            statePanel:SetAttribute("_onstate-combatclear", ONSTATE_COMBATCLEAR)
            statePanel:SetAttribute("_onstate-rcclear", ONSTATE_RCCLEAR)
            RegisterStateDriver(statePanel, "mov", macro)
            RegisterStateDriver(statePanel, "combatclear", "[combat]1;0")
            if ruleLaneOn then
                rightClickHover:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
                rightClickHover:RegisterEvent("PLAYER_REGEN_DISABLED")
                rightClickHover:RegisterEvent("PLAYER_REGEN_ENABLED")
                -- Registered with the lane it clears, so the extra driver only
                -- exists where the Lua lane does.
                RegisterStateDriver(statePanel, "rcclear", "[@mouseover,harm,nodead]1;0")
                PushRCState()
            else
                rightClickHover:UnregisterAllEvents()
                UnregisterStateDriver(statePanel, "rcclear")
                statePanel:SetAttribute("state-rc", 0)
            end
        else
            UnregisterStateDriver(statePanel, "mov")
            UnregisterStateDriver(statePanel, "combatclear")
            UnregisterStateDriver(statePanel, "rcclear")
            rightClickHover:UnregisterAllEvents()
            statePanel:SetAttribute("state-rc", 0)
            ClearOverrideBindings(statePanel)
        end
    end

    CludesUI._applyRightClickTarget = ApplyRightClickTarget

    local rcInitFrame = CreateFrame("Frame")
    -- Persistent (not one-shot): the instanced-vs-outdoor mode split above is
    -- re-derived on every zone transition. Feature off = one cheap idempotent
    -- call per loading screen.
    rcInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rcInitFrame:SetScript("OnEvent", function()
        ApplyRightClickTarget()
    end)
end

-------------------------------------------------------------------------------
--  Character Crosshair
-------------------------------------------------------------------------------
do
    local crosshair

    -- The account-wide CludesUIDB root is the inherited global default
    -- (preserved, never cleared); QoL per-profile DB holds overrides. Existing
    -- users keep their current crosshair until a profile overrides it.
    -- CrosshairDB() is nil until the Cursor module creates it.
    local function CrosshairDB()
        return _G._CUCL_AceDB and _G._CUCL_AceDB.profile
    end
    CludesUI.GetCrosshairDB = CrosshairDB

    -- Effective read: profile override -> global root -> nil (inline default).
    local function CrosshairGet(key)
        local p = CrosshairDB()
        if p and p[key] ~= nil then
            return p[key]
        end
        return CludesUIDB and CludesUIDB[key]
    end
    CludesUI.GetCrosshairValue = CrosshairGet

    -- Holy-Paladin melee opt-in, cached: CrosshairGet is a DB read and the
    -- cutoff getter runs at crosshair tick cadence. The engine caches the
    -- spec-derived cutoff itself (invalidated on spec/talent churn) and keeps
    -- the druid-form check live, so this flag is the only local state left.
    local _chHpalMelee = false

    local function RefreshCrosshairCutoffRange()
        _chHpalMelee = CrosshairGet("crosshairHpalMelee") and true or false
    end
    RefreshCrosshairCutoffRange()
    -- Exposed so the crosshair options toggle can re-resolve the cutoff live.
    CludesUI._RefreshCrosshairCutoffRange = RefreshCrosshairCutoffRange

    CludesUI._getCrosshairCutoffRange = function()
        return CludesUI.Range_GetAttackCutoff(nil, _chHpalMelee)
    end

    -- True only when there is an attackable, living target out of range.
    local function TargetOutOfRange()
        if not (UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")) then
            return false
        end
        local cutoff = CludesUI._getCrosshairCutoffRange()

        local beyond = CludesUI.Range_IsBeyondAttackRange("target", cutoff)
        return beyond == nil or beyond
    end

    local function CreateCrosshair()
        if crosshair then
            return
        end
        crosshair = CreateFrame("Frame", "CUI_CharacterCrosshair", UIParent)
        -- MEDIUM sits above gameplay HUD but below DIALOG/HIGH panels (talents, character, etc.).
        crosshair:SetFrameStrata("MEDIUM")
        crosshair:SetFrameLevel(100)
        crosshair:EnableMouse(false)
        crosshair:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        crosshair:SetSize(1, 1)

        local function MakeArm(layer)
            local tex = crosshair:CreateTexture(nil, layer or "OVERLAY")
            if tex.SetSnapToPixelGrid then
                tex:SetSnapToPixelGrid(false)
                tex:SetTexelSnappingBias(0)
            end
            return tex
        end
        -- Borders sit on artwork so the overlay arms render on top of them.
        crosshair._hBorder = MakeArm("ARTWORK")
        crosshair._vBorder = MakeArm("ARTWORK")
        crosshair._hBar = MakeArm("OVERLAY")
        crosshair._vBar = MakeArm("OVERLAY")

        -- Throttled recolor when the target is out of melee range. No-ops unless enabled and the class has a mapped melee spell.
        local meleeAccum = 0
        crosshair:SetScript("OnUpdate", function(self, elapsed)
            meleeAccum = meleeAccum + elapsed
            if meleeAccum < 0.15 then
                return
            end
            meleeAccum = 0
            local nameColor = self._normalColor
            if not nameColor then
                return
            end
            if not CrosshairGet("crosshairMeleeColorEnabled") then
                CludesUI.Range_SetActive("crosshair", false)
                if self._meleeActive then
                    self._meleeActive = false
                    self._hBar:SetColorTexture(nameColor.r, nameColor.g, nameColor.b, nameColor.a)
                    self._vBar:SetColorTexture(nameColor.r, nameColor.g, nameColor.b, nameColor.a)
                end
                return
            end
            -- Cheap and idempotent: keeps the shared engine's activation in step with this live toggle read.
            CludesUI.Range_SetActive("crosshair", true)
            local outOfRange = TargetOutOfRange()
            if outOfRange ~= self._meleeActive then
                self._meleeActive = outOfRange
                local color = outOfRange
                        and (CrosshairGet("crosshairMeleeColor") or { r = 1, g = 0, b = 0, a = 1 })
                    or nameColor
                self._hBar:SetColorTexture(color.r or 1, color.g or 0, color.b or 0, color.a or 1)
                self._vBar:SetColorTexture(color.r or 1, color.g or 0, color.b or 0, color.a or 1)
            end
        end)
    end

    -- Presets: thickness + total arm length. Options dropdown stamps these onto
    -- H/V Width/Length and they're the fallback when unset; cog sliders fine-tune.
    CludesUI.CROSSHAIR_PRESETS = {
        Thin = { width = 1, length = 40 },
        Normal = { width = 2, length = 40 },
        Thick = { width = 3, length = 40 },
    }

    -- Re-evaluates visibility on combat/zone transitions, refreshes cutoff on
    -- spec changes. Registered only while enabled (size "None" fires nothing);
    -- off->on re-reads the cutoff directly to catch changes made while unregistered.
    local visibilityWatch = CreateFrame("Frame")
    local visWatchRegistered = false
    visibilityWatch:SetScript("OnEvent", function(_, eventName)
        if
            eventName == "PLAYER_SPECIALIZATION_CHANGED"
            or eventName == "PLAYER_ENTERING_WORLD"
            or eventName == "TRAIT_CONFIG_UPDATED"
        then
            RefreshCrosshairCutoffRange()
        end
        -- _applyCrosshair self-guards: nil DB returns, "None" hides, and it runs
        -- the one-time migration once the profile DB is ready.
        if CludesUI._applyCrosshair then
            CludesUI._applyCrosshair()
        end
    end)
    local function SyncVisWatch(wanted)
        if wanted == visWatchRegistered then
            return
        end
        visWatchRegistered = wanted
        if wanted then
            visibilityWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
            visibilityWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
            visibilityWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
            visibilityWatch:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            visibilityWatch:RegisterEvent("TRAIT_CONFIG_UPDATED")
            RefreshCrosshairCutoffRange()
        else
            visibilityWatch:UnregisterAllEvents()
        end
    end

    CludesUI._applyCrosshair = function()
        local Pix = CludesUI.PP
        -- Effective reads (profile override -> global root -> inline default)
        local G = CrosshairGet
        local px = G("crosshairSize") or "None"
        if px == "None" then
            SyncVisWatch(false)
            -- OnUpdate stops with the frame hidden and can't release the shared range engine itself, so release it here.
            CludesUI.Range_SetActive("crosshair", false)
            if crosshair then
                crosshair:Hide()
            end
            return
        end
        SyncVisWatch(true)
        CludesUI.Range_SetActive("crosshair", G("crosshairMeleeColorEnabled") and true or false)

        CreateCrosshair()

        -- Strata (cog dropdown); MEDIUM = the original hardcoded value.
        -- Change-guarded: SetFrameStrata re-sorts the frame tree.
        local strata = G("crosshairStrata") or "MEDIUM"
        if crosshair._strata ~= strata then
            crosshair._strata = strata
            crosshair:SetFrameStrata(strata)
        end

        local color = G("crosshairColor")
        local cr = color and color.r or 1
        local cg = color and color.g or 1
        local callback = color and color.b or 1
        local ca = color and color.a or 0.75

        -- Preset gives the baseline width/length, sliders override per axis.
        local preset = CludesUI.CROSSHAIR_PRESETS[px] or CludesUI.CROSSHAIR_PRESETS.Normal
        local hWidth = G("crosshairHWidth") or preset.width
        local vWidth = G("crosshairVWidth") or preset.width
        local hLen = G("crosshairHLength") or preset.length
        local vLen = G("crosshairVLength") or preset.length
        local xOff = G("crosshairXOffset") or 0
        local yOff = G("crosshairYOffset") or 0
        local bSize = G("crosshairBorderSize") or 0
        local bc = G("crosshairBorderColor") or { r = 0, g = 0, b = 0, a = 1 }

        -- (0,0) = screen center
        crosshair:ClearAllPoints()
        crosshair:SetPoint("CENTER", UIParent, "CENTER", xOff, yOff)

        local hBar, vBar = crosshair._hBar, crosshair._vBar
        local hBorder, vBorder = crosshair._hBorder, crosshair._vBorder

        hBar:ClearAllPoints()
        hBar:SetSize(Pix.Scale(hLen), Pix.Scale(hWidth))
        hBar:SetPoint("CENTER", crosshair, "CENTER", 0, 0)
        hBar:SetColorTexture(cr, cg, callback, ca)

        vBar:ClearAllPoints()
        vBar:SetSize(Pix.Scale(vWidth), Pix.Scale(vLen))
        vBar:SetPoint("CENTER", crosshair, "CENTER", 0, 0)
        vBar:SetColorTexture(cr, cg, callback, ca)

        -- Base colour for out-of-range recolor; melee state resets so OnUpdate re-applies the range colour next tick if still needed.
        crosshair._normalColor = { r = cr, g = cg, b = callback, a = ca }
        crosshair._meleeActive = false

        -- Pixel border: a slightly larger bar of border colour behind each arm.
        if bSize and bSize > 0 then
            local bp = Pix.Scale(bSize)
            local br, backdrop, bb, ba = bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 1
            hBorder:ClearAllPoints()
            hBorder:SetSize(Pix.Scale(hLen) + bp * 2, Pix.Scale(hWidth) + bp * 2)
            hBorder:SetPoint("CENTER", crosshair, "CENTER", 0, 0)
            hBorder:SetColorTexture(br, backdrop, bb, ba)
            hBorder:Show()
            vBorder:ClearAllPoints()
            vBorder:SetSize(Pix.Scale(vWidth) + bp * 2, Pix.Scale(vLen) + bp * 2)
            vBorder:SetPoint("CENTER", crosshair, "CENTER", 0, 0)
            vBorder:SetColorTexture(br, backdrop, bb, ba)
            vBorder:Show()
        else
            hBorder:Hide()
            vBorder:Hide()
        end

        -- Visibility: always / combat / instances / instances_combat (both).
        local vis = G("crosshairVisibility") or "always"
        local inCombat = InCombatLockdown() or UnitAffectingCombat("player")
        local shouldShow = true
        if vis == "combat" then
            shouldShow = inCombat
        elseif vis == "instances" then
            shouldShow = IsInInstance()
        elseif vis == "instances_combat" then
            shouldShow = IsInInstance() and inCombat
        end
        if shouldShow then
            crosshair:Show()
        else
            crosshair:Hide()
        end
    end

    C_Timer.After(1, function()
        if CludesUI._applyCrosshair then
            CludesUI._applyCrosshair()
        end
    end)

    ---------------------------------------------------------------------------
    --  Map Coordinates
    ---------------------------------------------------------------------------
    do
        local coordPanel
        local coordText

        local function CreateCoordFrame()
            if coordPanel then
                return
            end
            local mapLoaded = C_AddOns.IsAddOnLoaded("Blizzard_WorldMap")
            if not mapLoaded or not WorldMapFrame then
                return
            end

            coordPanel = CreateFrame("Frame", nil, WorldMapFrame.ScrollContainer)
            coordPanel:SetFrameStrata("HIGH")
            coordPanel:SetSize(1, 1)
            coordPanel:SetPoint("BOTTOM", WorldMapFrame.ScrollContainer, "BOTTOM", 0, 10)

            local Pix = CludesUI.PanelPP
            local fontPath = CludesUI.GetFontPath("extras")
            local outFrame = CludesUI.GetFontOutlineFlag("extras")
            local size = (CludesUIDB and CludesUIDB.mapCoordsTextSize) or 12

            local dividerTex = coordPanel:CreateTexture(nil, "OVERLAY")
            dividerTex:SetColorTexture(1, 1, 1, 0.9)
            Pix.Size(dividerTex, 2, size)
            dividerTex:SetPoint("BOTTOM", coordPanel, "BOTTOM", 0, 0)

            local useShadow = CludesUI.GetFontUseShadow("extras")

            local cursorText = coordPanel:CreateFontString(nil, "OVERLAY")
            CludesUI.PrimeFontShadow(cursorText, useShadow)
            cursorText:SetFont(fontPath, size, outFrame)
            cursorText:SetTextColor(1, 1, 1, 0.9)
            cursorText:SetJustifyH("RIGHT")
            cursorText:SetPoint("RIGHT", dividerTex, "LEFT", -10, 0)

            local playerText = coordPanel:CreateFontString(nil, "OVERLAY")
            CludesUI.PrimeFontShadow(playerText, useShadow)
            playerText:SetFont(fontPath, size, outFrame)
            playerText:SetTextColor(1, 1, 1, 0.9)
            playerText:SetJustifyH("LEFT")
            playerText:SetPoint("LEFT", dividerTex, "RIGHT", 10, 0)

            coordText = { cursor = cursorText, player = playerText, divider = dividerTex }

            local elapsed = 0
            coordPanel:SetScript("OnUpdate", function(_, dt)
                elapsed = elapsed + dt
                if elapsed < 0.05 then
                    return
                end
                elapsed = 0
                local mapID = WorldMapFrame:GetMapID()
                if not mapID then
                    cursorText:SetText("")
                    playerText:SetText("")
                    dividerTex:Hide()
                    return
                end
                -- Player position (hidden in instances)
                local playerPos = C_Map.GetPlayerMapPosition(mapID, "player")
                local hasPlayer = false
                if playerPos then
                    local px, py = playerPos:GetXY()
                    if px and py and px > 0 and py > 0 then
                        playerText:SetText("P: " .. format("%.0f, %.0f", px * 100, py * 100))
                        hasPlayer = true
                    end
                end
                if hasPlayer then
                    dividerTex:Show()
                    playerText:Show()
                else
                    dividerTex:Hide()
                    playerText:Hide()
                end

                local cText = "0, 0"
                local childFrame = WorldMapFrame.ScrollContainer.Child
                if childFrame and childFrame:IsMouseOver() then
                    local cx, cy = childFrame:GetSize()
                    if cx and cx > 0 and cy and cy > 0 then
                        local scale = childFrame:GetEffectiveScale()
                        local leftX = childFrame:GetLeft()
                        local topY = childFrame:GetTop()
                        if scale and leftX and topY then
                            local curX, curY = GetCursorPosition()
                            local nx = (curX / scale - leftX) / cx
                            local ny = (topY - curY / scale) / cy
                            if nx >= 0 and nx <= 1 and ny >= 0 and ny <= 1 then
                                cText = format("%.0f, %.0f", nx * 100, ny * 100)
                            end
                        end
                    end
                end

                cursorText:SetText("C: " .. cText)
            end)
        end

        CludesUI._applyMapCoords = function()
            local isEnabled = CludesUIDB and CludesUIDB.mapCoords
            if isEnabled then
                CreateCoordFrame()
                if coordPanel then
                    local Pix = CludesUI.PanelPP
                    local fontPath = CludesUI.GetFontPath("extras")
                    local outFrame = CludesUI.GetFontOutlineFlag("extras")
                    local useShadow = CludesUI.GetFontUseShadow("extras")
                    local size = (CludesUIDB and CludesUIDB.mapCoordsTextSize) or 12
                    CludesUI.PrimeFontShadow(coordText.cursor, useShadow)
                    coordText.cursor:SetFont(fontPath, size, outFrame)
                    CludesUI.PrimeFontShadow(coordText.player, useShadow)
                    coordText.player:SetFont(fontPath, size, outFrame)
                    Pix.Size(coordText.divider, 2, size)
                    coordPanel:Show()
                end
            elseif coordPanel then
                coordPanel:Hide()
            end
        end

        -- WorldMapFrame is load-on-demand; hook when it loads
        if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            CludesUI._applyMapCoords()
        else
            local loadFrame = CreateFrame("Frame")
            loadFrame:RegisterEvent("ADDON_LOADED")
            loadFrame:SetScript("OnEvent", function(self, _, addonName)
                if addonName == "Blizzard_WorldMap" then
                    self:UnregisterEvent("ADDON_LOADED")
                    CludesUI._applyMapCoords()
                end
            end)
        end
    end
end

-------------------------------------------------------------------------------
--  Transparent World Map Sidebars: the black beside the maximized world map goes
--  to the chosen opacity (clear by default) and lets the mouse through to
--  the world. Blizzard only shows and hides BlackoutFrame, so the change
--  holds until turned off. Not offered on WoW Forever: Forever Essentials
--  has its own map background option there.
-------------------------------------------------------------------------------
if not CludesUI.IS_FOREVER then
    local loadFrame
    local applied = false
    local mouseWas

    function CludesUI._applyMapSidebars()
        local isEnabled = CludesUIDB and CludesUIDB.mapSidebarsClear == true
        if not (isEnabled or applied or loadFrame) then
            return
        end
        -- The world map loads on demand.
        if not C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
            if isEnabled and not loadFrame then
                loadFrame = CreateFrame("Frame")
                loadFrame:SetScript("OnEvent", function(self, _, label)
                    if label ~= "Blizzard_WorldMap" then
                        return
                    end
                    self:UnregisterEvent("ADDON_LOADED")
                    CludesUI._applyMapSidebars()
                end)
            end
            if isEnabled then
                loadFrame:RegisterEvent("ADDON_LOADED")
            else
                loadFrame:UnregisterEvent("ADDON_LOADED")
            end
            return
        end
        if not (isEnabled or applied) then
            return
        end
        if InCombatLockdown() then
            mod.CombatQueue.Defer("MapSidebars", CludesUI._applyMapSidebars)
            return
        end
        local widget = WorldMapFrame.BlackoutFrame
        if not (widget and widget.Blackout) then
            return
        end
        if isEnabled then
            if not applied then
                mouseWas = widget:IsMouseEnabled()
            end
            widget.Blackout:SetAlpha((CludesUIDB.mapSidebarsOpacity or 0) / 100)
            -- The wheel already passes through: the frame never takes it.
            widget:EnableMouse(false)
        else
            widget.Blackout:SetAlpha(1)
            widget:EnableMouse(mouseWas)
        end
        applied = isEnabled
    end
end

-------------------------------------------------------------------------------
--  Hide Error Messages -- hides red error lines ("Not enough rage", etc.)
--  while a keep list of useful errors stays up. Hidden message types go into
--  UIErrorsFrame's own per-type switch (SetMessageTypeEnabled), which Blizzard
--  checks before it adds a line or plays its sound, so a hidden error stays
--  silent. Never switched: the kept types, the voice chat window's types (that
--  window hands its errors to the frame itself, outside the frame's event
--  handler) and every type already hidden (Blizzard's defaults, other addons'
--  picks). The types the game sends as yellow info lines are left on too,
--  until one arrives as a red error while the option is on. While the switch
--  is in place, a listener on our own frame shows what a type switch cannot:
--  a kept error text under a switched-off type, and a yellow line of a
--  switched-off type. The switch entries are never written back during a
--  session (Blizzard's repeat-flash code would then run tainted), so turning
--  the option off takes effect at the next reload, which the options row
--  offers; nothing new is switched while the option is off. With the option
--  off at login nothing is written and nothing stays registered.
-------------------------------------------------------------------------------
do
    -- A text no line on screen can hold: asking Blizzard whether a type shows
    -- with it never flashes or refreshes a line already up.
    local PROBE = "\0"

    local isActive = false
    local switched = {} -- [messageType] = true: switched off here
    local roleOf -- [messageType] = "keep" | "info" | "voice"
    local throttled -- [messageType] = true: a repeat refreshes the line
    local keepText -- [message] = true: kept error texts
    local typeCount
    local frame = CreateFrame("Frame")

    -- Reads every message type's name once. The client numbers its types
    -- from 1 with no gaps; the scan stops at the first index with no name.
    local function ScanTypes()
        local KEEP = {
            "ERR_INV_FULL",
            "ERR_QUEST_LOG_FULL",
            "ERR_RAID_GROUP_ONLY",
            "ERR_PARTY_LFG_BOOT_LIMIT",
            "ERR_PARTY_LFG_BOOT_NOT_ELIGIBLE_S",
            "ERR_PARTY_LFG_BOOT_DUNGEON_COMPLETE",
            "ERR_PARTY_LFG_BOOT_IN_PROGRESS",
            "ERR_PARTY_LFG_BOOT_LOOT_ROLLS",
            "ERR_PARTY_LFG_TELEPORT_IN_COMBAT",
            "ERR_PET_SPELL_DEAD",
            "ERR_PLAYER_DEAD",
            "ERR_ALREADY_PICKPOCKETED",
        }
        -- Sent as yellow UI_INFO_MESSAGE lines (quest progress, discoveries,
        -- trades, flight paths and the like). The switch is per type, not per
        -- event, so one of these is switched only once it arrives as a red
        -- error while the option is on.
        local INFO = {
            "ERR_TAXINOSUCHPATH",
            "ERR_TAXINOTENOUGHMONEY",
            "ERR_TAXITOOFARAWAY",
            "ERR_TAXINOVENDORNEARBY",
            "ERR_TAXINOTVISITED",
            "ERR_TAXIPLAYERMOVING",
            "ERR_TAXINOTSTANDING",
            "ERR_NEWTAXIPATH",
            "ERR_TRADE_CANCELLED",
            "ERR_TRADE_COMPLETE",
            "ERR_USE_SPELL_FOCUS",
            "ERR_QUEST_OBJECTIVE_COMPLETE_S",
            "ERR_QUEST_UNKNOWN_COMPLETE",
            "ERR_QUEST_ADD_KILL_SII",
            "ERR_QUEST_ADD_FOUND_SII",
            "ERR_QUEST_ADD_ITEM_SII",
            "ERR_QUEST_ADD_PLAYER_KILL_SII",
            "ERR_QUEST_PET_BATTLE_VICTORIES_PVP_II",
            "ERR_ZONE_EXPLORED",
            "ERR_DUEL_CANCELLED",
            "ERR_FISH_NOT_HOOKED",
            "ERR_FISH_ESCAPED",
            "ERR_SPELL_FAILED_NOTUNSHEATHED",
            "ERR_SPELL_FAILED_LEVEL_REQUIREMENT",
            "ERR_MAIL_SENT",
            "ERR_PVP_KILL_HONORABLE",
            "ERR_PVP_KILL_DISHONORABLE",
            "ERR_PVP_TOGGLE_ON",
            "ERR_PVP_TOGGLE_OFF",
            "ERR_PVP_WARMODE_TOGGLE_ON",
            "ERR_PVP_WARMODE_TOGGLE_OFF",
            "ERR_GROUP_JOIN_BATTLEGROUND_DESERTERS",
            "ERR_GROUP_JOIN_BATTLEGROUND_DEAD",
            "ERR_SOLO_JOIN_TRAINING_GROUND",
            "ERR_LFG_JOINED_TRAINING_GROUNDS_QUEUE",
            "ERR_BN_FRIEND_REQUEST_SENT",
            "ERR_BN_BROADCAST_THROTTLE",
            "ERR_BATTLETAG_FRIEND_SUCCESS",
            "ERR_REPORT_SUBMITTED_SUCCESSFULLY",
            "ERR_SUGGESTION_SUBMITTED_SUCCESSFULLY",
            "ERR_BUG_SUBMITTED_SUCCESSFULLY",
        }
        -- The types whose repeat of the same text refreshes the line already
        -- up instead of adding one (UIErrorsFrame's own list).
        local THROTTLED = {
            "ERR_SPELL_FAILED_TOTEMS",
            "ERR_SPELL_FAILED_EQUIPPED_ITEM",
            "ERR_SPELL_ALREADY_KNOWN_S",
            "ERR_SPELL_FAILED_SHAPESHIFT_FORM_S",
            "ERR_SPELL_FAILED_ALREADY_AT_FULL_MANA",
            "ERR_OUT_OF_MANA",
            "ERR_SPELL_OUT_OF_RANGE",
            "ERR_SPELL_FAILED_S",
            "ERR_SPELL_FAILED_REAGENTS",
            "ERR_SPELL_FAILED_REAGENTS_GENERIC",
            "ERR_SPELL_FAILED_NOTUNSHEATHED",
            "ERR_SPELL_UNLEARNED_S",
            "ERR_SPELL_FAILED_EQUIPPED_SPECIFIC_ITEM",
            "ERR_SPELL_FAILED_ALREADY_AT_FULL_POWER_S",
            "ERR_SPELL_FAILED_EQUIPPED_ITEM_CLASS_S",
            "ERR_SPELL_FAILED_ALREADY_AT_FULL_HEALTH",
            "ERR_SPELL_FAILED_CANT_FLY_HERE",
            "ERR_GENERIC_NO_VALID_TARGETS",
            "ERR_ITEM_COOLDOWN",
            "ERR_CANT_USE_ITEM",
            "ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS",
        }
        local role, repeats = {}, {}
        keepText = {}
        for i = 1, #KEEP do
            local label = KEEP[i]
            role[label] = "keep"
            local textValue = _G[label]
            if type(textValue) == "string" then
                keepText[textValue] = true
            end
        end
        -- The pickpocket line arrives as a plain spell failure, so it is kept
        -- by its text alone.
        if type(SPELL_FAILED_TARGET_NO_POCKETS) == "string" then
            keepText[SPELL_FAILED_TARGET_NO_POCKETS] = true
        end
        for i = 1, #INFO do
            role[INFO[i]] = "info"
        end
        for i = 1, #THROTTLED do
            repeats[THROTTLED[i]] = true
        end
        roleOf, throttled = {}, {}
        local total = 0
        for i = 1, 8191 do
            local ok, label = pcall(GetGameMessageInfo, i)
            if not (ok and label) then
                break
            end
            roleOf[i] = role[label]
            throttled[i] = repeats[label]
            total = i
        end
        typeCount = total
        -- The voice chat window's types, from its own status-code map.
        if Voice_GetGameErrorFromStatusCode and Enum.VoiceChatStatusCode then
            for _, code in pairs(Enum.VoiceChatStatusCode) do
                local msgKind = Voice_GetGameErrorFromStatusCode(code)
                if type(msgKind) == "number" then
                    roleOf[msgKind] = "voice"
                end
            end
        end
    end

    -- Switches one type off when it shows now; a type already hidden keeps
    -- the entry it has.
    local function SwitchOff(widget, msgKind)
        local ok, isShown = pcall(widget.ShouldDisplayMessageType, widget, msgKind, PROBE)
        if ok and isShown then
            widget:SetMessageTypeEnabled(msgKind, false)
            switched[msgKind] = true
        end
    end

    -- Shows a line of a switched-off type as UIErrorsFrame does: a repeat of
    -- a throttled type only restarts the fade of the same line already up;
    -- anything else is added under its type with the type's voice or sound.
    -- Nothing is drawn while Blizzard holds its messages back, or once
    -- another addon has switched the type back on (Blizzard then drew the
    -- line itself).
    local function ShowLine(msgKind, message, red, green, blue)
        local widget = UIErrorsFrame
        local ok, isShown = pcall(widget.ShouldDisplayMessageType, widget, msgKind, PROBE)
        if not ok then
            return
        end
        if isShown then
            switched[msgKind] = nil
            return
        end
        if widget:GetMessagesSuppressed() then
            return
        end
        if throttled[msgKind] then
            local fontStr = widget:GetFontStringByID(msgKind)
            if fontStr then
                local textValue = fontStr:GetText()
                if not issecretvalue(textValue) and textValue == message then
                    widget:ResetMessageFadeByID(msgKind)
                    return
                end
            end
        end
        widget:AddMessage(message, red, green, blue, 1.0, msgKind)
        local _, soundKitID, voiceID = GetGameMessageInfo(msgKind)
        if voiceID then
            C_Sound.PlayVocalErrorSound(voiceID)
        elseif soundKitID then
            PlaySound(soundKitID)
        end
    end

    local function Enable()
        local widget = UIErrorsFrame
        if not (widget and widget.SetMessageTypeEnabled) then
            return
        end
        if not typeCount then
            ScanTypes()
        end
        for msgKind = 1, typeCount do
            if not roleOf[msgKind] then
                SwitchOff(widget, msgKind)
            end
        end
        frame:RegisterEvent("UI_ERROR_MESSAGE")
        frame:RegisterEvent("UI_INFO_MESSAGE")
        isActive = true
    end

    -- Applies the option. Turning it off is left to the next reload: returns
    -- true while the option is off and the switch is still in place.
    local function ApplyHideErrorMessages()
        local isEnabled = CludesUIDB and CludesUIDB.hideErrorMessages
        if isEnabled and not isActive then
            Enable()
        end
        return (isActive and not isEnabled) and true or false
    end
    CludesUI._applyHideErrorMessages = ApplyHideErrorMessages

    frame:SetScript("OnEvent", function(self, eventName, msgKind, message)
        if eventName == "PLAYER_LOGIN" then
            self:UnregisterEvent("PLAYER_LOGIN")
            ApplyHideErrorMessages()
            return
        end
        if issecretvalue(msgKind) or issecretvalue(message) then
            return
        end
        if switched[msgKind] then
            if eventName == "UI_INFO_MESSAGE" then
                ShowLine(msgKind, message, YELLOW_FONT_COLOR:GetRGB())
            elseif keepText[message] then
                ShowLine(msgKind, message, RED_FONT_COLOR:GetRGB())
            end
        elseif
            eventName == "UI_ERROR_MESSAGE"
            and roleOf[msgKind] == "info"
            and CludesUIDB
            and CludesUIDB.hideErrorMessages
        then
            -- An info type that came as a red error while the option is on:
            -- switched off too, so its later errors hide and its yellow lines
            -- come through ShowLine.
            SwitchOff(UIErrorsFrame, msgKind)
        end
    end)
    frame:RegisterEvent("PLAYER_LOGIN")
end

-------------------------------------------------------------------------------
--  Hide Tutorial Pop-ups
-------------------------------------------------------------------------------
do
    local function Enabled()
        return CludesUIDB and CludesUIDB.hideTutorials
    end

    -- "i" circles are MainHelpPlateButtons, fingerprinted by a mixin method;
    -- Blizzard_HelpPlate is load-on-demand, so resolve lazily and cache.
    local fingerprint
    local function GetFingerprint()
        if not fingerprint and MainHelpPlateButtonMixin then
            fingerprint = MainHelpPlateButtonMixin.ShowTooltip
        end
        return fingerprint
    end

    local hiddenByUs = setmetatable({}, { __mode = "k" })
    local function HideButton(button)
        button:SetAlpha(0)
        button:EnableMouse(false)
        hiddenByUs[button] = true
    end

    -- Hoisted out of the pcall: one reused function, not a closure per call
    -- (runs on each panel open and each HelpTip show).
    local function DoHideOpenTips()
        for tipText in HelpTip.framePool:EnumerateActive() do
            if tipText:IsShown() then
                local details = tipText.info
                if details and details.cvarBitfield and details.bitfieldFlag then
                    CludesUI.SetCVarBitfield(details.cvarBitfield, details.bitfieldFlag, true, "CludesUIQoL")
                end
                tipText:Hide()
            end
        end
    end
    local function HideOpenTips()
        if not (HelpTip and HelpTip.framePool and HelpTip.framePool.EnumerateActive) then
            return
        end
        pcall(DoHideOpenTips)
    end

    local HideButtonsUnder
    local function ScanChildren(...)
        for i = 1, select("#", ...) do
            HideButtonsUnder((select(i, ...)))
        end
    end
    -- Some Blizzard frame trees refuse GetChildren from insecure code with a usage
    -- error (house editor list rows do). This walk runs inside a ShowUIPanel hooksecurefunc, so an uncaught
    -- error would abort the panel's caller. pcall per node: a refusing frame
    -- skips only its subtree, siblings still get scanned; ScanFrame is hoisted so pcall allocates nothing per node.
    local function ScanFrame(root)
        ScanChildren(root:GetChildren())
    end
    function HideButtonsUnder(root)
        if not root then
            return
        end
        local fontPath = GetFingerprint()
        if not fontPath then
            return
        end
        if root.ShowTooltip == fontPath then
            HideButton(root)
        end
        if root.GetChildren then
            pcall(ScanFrame, root)
        end
    end

    local function RestoreButtons()
        for button in pairs(hiddenByUs) do
            button:SetAlpha(1)
            button:EnableMouse(true)
            hiddenByUs[button] = nil
        end
    end

    -- Core hooks (HelpTip + ShowUIPanel) install once, only via ApplyHideTutorials; each body also gates on Enabled().
    local coreHooked = false
    local function InstallCoreHooks()
        if coreHooked then
            return
        end
        coreHooked = true
        if HelpTip and HelpTip.Show then
            hooksecurefunc(HelpTip, "Show", function()
                if Enabled() then
                    HideOpenTips()
                end
            end)
        end
        if ShowUIPanel then
            hooksecurefunc("ShowUIPanel", function(widget)
                if Enabled() and widget then
                    HideButtonsUnder(widget)
                    HideOpenTips()
                end
            end)
        end
    end

    local tooltipHooked = false
    local function InstallTooltipHook()
        if tooltipHooked or not HelpPlateTooltip then
            return
        end
        tooltipHooked = true
        if HelpPlate and HelpPlate.ShowTutorialTooltip then
            hooksecurefunc(HelpPlate, "ShowTutorialTooltip", function()
                if Enabled() and HelpPlateTooltip then
                    HelpPlateTooltip:Hide()
                end
            end)
        end
        if HelpPlateTooltip.Init then
            hooksecurefunc(HelpPlateTooltip, "Init", function(self)
                if Enabled() then
                    self:Hide()
                end
            end)
        end
    end

    local weSetCVar = false
    local function ApplyHideTutorials()
        if Enabled() then
            InstallCoreHooks()
            InstallTooltipHook()
            pcall(CludesUI.SetCVar, "hideHelptips", "1", "CludesUIQoL")
            pcall(CludesUI.SetCVar, "showTutorials", "0", "CludesUIQoL")
            weSetCVar = true
            -- No global EnumerateFrames walk here (runs inside PLAYER_LOGIN): already-open
            -- panels pick up their "i" buttons on the next ShowUIPanel.
            HideOpenTips()
        else
            if weSetCVar then
                pcall(CludesUI.SetCVar, "hideHelptips", "0", "CludesUIQoL")
                pcall(CludesUI.SetCVar, "showTutorials", "1", "CludesUIQoL")
                weSetCVar = false
            end
            RestoreButtons()
        end
    end
    CludesUI._applyHideTutorials = ApplyHideTutorials

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, eventName, addon)
        if eventName == "ADDON_LOADED" then
            -- Gated: nothing is hooked while the feature is off.
            if addon == "Blizzard_HelpPlate" and Enabled() then
                InstallTooltipHook()
            end
            return
        end
        ApplyHideTutorials() -- PLAYER_LOGIN
    end)
end

-------------------------------------------------------------------------------
--  Group Death Announcer -- shows a center-screen "<name> DIED!" alert on a
--  party/raid death. Midnight has no combat log, so deaths are detected by polling
--  group units for an alive->dead transition (feign/own death excluded). No ticker runs while off or solo.
-------------------------------------------------------------------------------
do
    local POLL_INTERVAL = 0.35
    local alertFrame
    local ticker
    local watchFrame
    local isInstalled = false
    local deadState = {} -- [guid] = true while dead/ghost, false while alive

    local DEFAULT_TEXT_SIZE = 34

    -- Configured font size + saved position (default center-top).
    local function ApplyOverlaySettings()
        if not alertFrame then
            return
        end
        local fontFile = (CludesUI.GetFontPath("extras")) or CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        -- Always keep an outline so the alert stays readable over any background.
        local outlineFlag = (CludesUI.GetFontOutlineFlag("extras")) or ""
        if not outlineFlag:find("OUTLINE") then
            outlineFlag = (outlineFlag == "") and "OUTLINE" or (outlineFlag .. ", OUTLINE")
        end
        local px = (CludesUIDB and CludesUIDB.groupDeathTextSize) or DEFAULT_TEXT_SIZE
        -- A font family: the alert shows a group member's name, in any script
        CludesUI.SetFontFamily(alertFrame._text, fontFile, px, outlineFlag, false)
        -- Keep the frame (and unlock-mode mover) sized to the alert text, not a fixed wide box.
        alertFrame:SetSize(px * 7, px + 14)

        alertFrame:ClearAllPoints()
        local place = CludesUIDB and CludesUIDB.groupDeathAlertPos
        if place and place.point then
            alertFrame:SetPoint(
                place.point,
                UIParent,
                place.relPoint or place.point,
                place.x or 0,
                place.y or 0
            )
        else
            alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
        end
    end

    local function CreateAlertOverlay()
        if alertFrame then
            return
        end

        alertFrame = CreateFrame("Frame", nil, UIParent)
        alertFrame:SetSize(240, 50)
        alertFrame:SetFrameStrata("HIGH")
        alertFrame:SetFrameLevel(60)
        alertFrame:EnableMouse(false)
        alertFrame:SetMouseClickEnabled(false)

        local fontStr = alertFrame:CreateFontString(nil, "OVERLAY")
        fontStr:SetPoint("CENTER")
        alertFrame._text = fontStr
        ApplyOverlaySettings()

        -- Quick fade-in, brief hold, fade-out; hide when finished.
        local animGroup = alertFrame:CreateAnimationGroup()
        local fadeInAnim = animGroup:CreateAnimation("Alpha")
        fadeInAnim:SetFromAlpha(0)
        fadeInAnim:SetToAlpha(1)
        fadeInAnim:SetDuration(0.15)
        fadeInAnim:SetOrder(1)
        local hold = animGroup:CreateAnimation("Alpha")
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        hold:SetDuration(1.6)
        hold:SetOrder(2)
        local fadeOutAnim = animGroup:CreateAnimation("Alpha")
        fadeOutAnim:SetFromAlpha(1)
        fadeOutAnim:SetToAlpha(0)
        fadeOutAnim:SetDuration(0.6)
        fadeOutAnim:SetOrder(3)
        animGroup:SetScript("OnFinished", function()
            alertFrame:Hide()
        end)
        alertFrame._ag = animGroup

        alertFrame:SetScript("OnHide", function()
            animGroup:Stop()
        end)
        alertFrame:Hide()
    end

    local function ShowAlert(label, classFile)
        if not label then
            return
        end
        CreateAlertOverlay()
        ApplyOverlaySettings()

        local colored = label
        local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
        if c then
            colored = "|c" .. (c.colorStr or "ffffffff") .. label .. "|r"
        end
        local skull = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_8:0|t"
        alertFrame._text:SetText(skull .. " " .. colored .. " |cffff2020DIED!|r")

        alertFrame._ag:Stop()
        alertFrame:SetAlpha(1)
        alertFrame:Show()
        alertFrame._ag:Play()
    end

    -- Configurable death alert sound (default "none"): cog dropdown lists
    -- bundled + SharedMedia sounds. Played on "Master" to stay audible with a
    -- low SFX slider; tables exposed on CludesUI for the options dropdown.
    local GROUP_DEATH_SOUND_PATHS, GROUP_DEATH_SOUND_NAMES, GROUP_DEATH_SOUND_ORDER =
        CludesUI.BuildAlertSoundTables()
    -- SharedMedia sounds append at PLAYER_LOGIN (boot frame below), not here:
    -- this do-block runs at addon load, before other addons register their
    -- LibSharedMedia sounds. Tables exposed now by reference, so the append fills the same ones options reads.
    CludesUI._groupDeathSoundPaths = GROUP_DEATH_SOUND_PATHS
    CludesUI._groupDeathSoundNames = GROUP_DEATH_SOUND_NAMES
    CludesUI._groupDeathSoundOrder = GROUP_DEATH_SOUND_ORDER

    local function PlayDeathSound()
        local settingKey = CludesUIDB and CludesUIDB.groupDeathSoundKey
        if not settingKey or settingKey == "none" then
            return
        end
        local filePath = GROUP_DEATH_SOUND_PATHS[settingKey]
        if filePath then
            PlaySoundFile(filePath, "Master")
        end
    end

    local function ForEachGroupUnit(func)
        if IsInRaid() then
            for i = 1, GetNumGroupMembers() do
                local u = "raid" .. i
                if UnitExists(u) and not UnitIsUnit(u, "player") then
                    func(u)
                end
            end
        elseif IsInGroup() then
            for i = 1, 4 do
                local u = "party" .. i
                if UnitExists(u) then
                    func(u)
                end
            end
        end
    end

    -- Minimum gap between death sounds. On a wipe many die within/across polls,
    -- firing once per corpse; the cooldown collapses the burst into one sound.
    -- Applied only in groups larger than 5 (parties are sparse enough).
    local SOUND_COOLDOWN = 3.0
    local COOLDOWN_MIN_GROUP = 5
    local lastSoundTime = 0

    local function TryPlayDeathSound()
        if GetNumGroupMembers() > COOLDOWN_MIN_GROUP then
            local nowTime = GetTime()
            if nowTime - lastSoundTime < SOUND_COOLDOWN then
                return
            end
            lastSoundTime = nowTime
        end
        PlayDeathSound()
    end

    local function Poll()
        if not (CludesUIDB and CludesUIDB.announceGroupDeaths) then
            return
        end
        local seen = {}
        local newlyDeadName, newlyDeadClass, newlyDeadCount
        ForEachGroupUnit(function(unit)
            local unitGuid = UnitGUID(unit)
            if not unitGuid then
                return
            end
            seen[unitGuid] = true
            if not UnitIsConnected(unit) then
                return
            end
            local dead = (UnitIsDeadOrGhost(unit) and not UnitIsFeignDeath(unit)) and true or false
            -- prev == false means we previously saw this unit alive; a nil prev
            -- (first sighting/rejoin) primes state silently so an already-dead member at start is never announced.
            if deadState[unitGuid] == false and dead then
                local _, classFile = UnitClass(unit)
                newlyDeadName = UnitName(unit)
                newlyDeadClass = classFile
                newlyDeadCount = (newlyDeadCount or 0) + 1
            end
            deadState[unitGuid] = dead
        end)
        for unitGuid in pairs(deadState) do
            if not seen[unitGuid] then
                deadState[unitGuid] = nil
            end
        end
        -- One alert per poll (extra ShowAlert calls would just clobber each other) and at most one throttled sound.
        if newlyDeadCount then
            ShowAlert(newlyDeadName, newlyDeadClass)
            TryPlayDeathSound()
        end
    end

    local function StartTicker()
        if ticker then
            return
        end
        wipe(deadState)
        Poll() -- prime alive/dead state without announcing
        ticker = C_Timer.NewTicker(POLL_INTERVAL, Poll)
    end

    local function StopTicker()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
        wipe(deadState)
        if alertFrame then
            alertFrame:Hide()
        end
    end

    local function UpdateActive()
        if CludesUIDB and CludesUIDB.announceGroupDeaths and IsInGroup() then
            StartTicker()
        else
            StopTicker()
        end
    end

    local function ApplyAnnounceGroupDeaths()
        local isEnabled = CludesUIDB and CludesUIDB.announceGroupDeaths
        if isEnabled and not isInstalled then
            watchFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
            watchFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
            isInstalled = true
        elseif not isEnabled and isInstalled then
            watchFrame:UnregisterAllEvents()
            isInstalled = false
        end
        UpdateActive()
    end
    CludesUI._applyAnnounceGroupDeaths = ApplyAnnounceGroupDeaths

    -- Fires a sample alert (with sound) so the look/sound can be checked without a real death; uses your own name/class as preview text.
    CludesUI._announceGroupDeathsPreview = function()
        local _, classFile = UnitClass("player")
        ShowAlert(UnitName("player"), classFile)
        PlayDeathSound()
    end

    -- Visual-only preview (used by the Text Size slider so dragging it doesn't repeatedly fire the sound).
    CludesUI._groupDeathShowVisual = function()
        local _, classFile = UnitClass("player")
        ShowAlert(UnitName("player"), classFile)
    end

    CludesUI._groupDeathPlaySound = PlayDeathSound

    -- Re-apply font size/position (called from the Text Size slider and from unlock mode on saved-position change).
    CludesUI._applyGroupDeathAlert = function()
        CreateAlertOverlay()
        ApplyOverlaySettings()
    end

    -- Register the alert with Unlock Mode so its position can be dragged.
    C_Timer.After(2, function()
        if not (CludesUI and CludesUI.RegisterUnlockElements) then
            return
        end
        local MK = CludesUI.MakeUnlockElement
        if not MK then
            return
        end
        CludesUI:RegisterUnlockElements({
            MK({
                key = "CUI_GroupDeathAlert",
                label = "Group Death Alert",
                group = "Utilities",
                order = 720,
                noResize = true,
                isHidden = function()
                    return not (CludesUIDB and CludesUIDB.announceGroupDeaths)
                end,
                getFrame = function()
                    CreateAlertOverlay()
                    return alertFrame
                end,
                getSize = function()
                    local px = (CludesUIDB and CludesUIDB.groupDeathTextSize) or DEFAULT_TEXT_SIZE
                    return px * 7, px + 14
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    if not anchorPoint then
                        return
                    end
                    if not CludesUIDB then
                        CludesUIDB = {}
                    end
                    CludesUIDB.groupDeathAlertPos =
                        { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    if alertFrame and not CludesUI._unlockActive then
                        ApplyOverlaySettings()
                    end
                end,
                loadPos = function()
                    local place = CludesUIDB and CludesUIDB.groupDeathAlertPos
                    if place and place.point then
                        return place
                    end
                    return { point = "CENTER", relPoint = "CENTER", x = 0, y = 180 }
                end,
                clearPos = function()
                    if CludesUIDB then
                        CludesUIDB.groupDeathAlertPos = nil
                    end
                    if alertFrame then
                        ApplyOverlaySettings()
                    end
                end,
                applyPos = function()
                    CreateAlertOverlay()
                    ApplyOverlaySettings()
                end,
            }),
        })
    end)

    watchFrame = CreateFrame("Frame")
    watchFrame:SetScript("OnEvent", function()
        UpdateActive()
    end)

    local bootFrame = CreateFrame("Frame")
    bootFrame:RegisterEvent("PLAYER_LOGIN")
    bootFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        -- Append now, at login, once other addons have registered theirs (same
        -- timing as Chat's whisper-sound dropdown). Idempotent: skips keys
        -- already present; the tables are the same ones options and PlayDeathSound read.
        CludesUI.AppendSharedMediaSounds(
            GROUP_DEATH_SOUND_PATHS,
            GROUP_DEATH_SOUND_NAMES,
            GROUP_DEATH_SOUND_ORDER
        )
        if CludesUIDB and CludesUIDB.announceGroupDeaths then
            ApplyAnnounceGroupDeaths()
        end
    end)
end

-------------------------------------------------------------------------------
--  Combat Alert -- center-screen text on PLAYER_REGEN_DISABLED/ENABLED. Each
--  transition has its own text/color (custom or class color); one Text Size
--  applies to both. "Show On" selects enter/leave/both. The text is drawn by
--  the shared alert anchor (CludesUIQoL_Alerts.lua), which also owns the
--  Unlock Mode position. No events registered unless enabled.
-------------------------------------------------------------------------------
do
    local watchFrame
    local isInstalled = false

    local DEFAULTS = {
        enterText = "+Combat",
        leaveText = "-Combat",
        enterColor = { r = 1.00, g = 1.00, b = 1.00 },
        leaveColor = { r = 1.00, g = 1.00, b = 1.00 },
    }

    -- Effective color for a transition: player's class color when the class-color toggle is on, else the stored custom color.
    local function ResolveColor(which)
        local store = CludesUIDB
        local useClass = store
            and store[which == "leave" and "combatAlertLeaveUseClassColor" or "combatAlertEnterUseClassColor"]
        if useClass then
            local _, classFile = UnitClass("player")
            local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
            if color then
                return color.r, color.g, color.b
            end
        end
        local color = (store and store[which == "leave" and "combatAlertLeaveColor" or "combatAlertEnterColor"])
            or (which == "leave" and DEFAULTS.leaveColor or DEFAULTS.enterColor)
        return color.r, color.g, color.b
    end

    local function AlertText(which)
        local store = CludesUIDB
        if which == "leave" then
            return (store and store.combatAlertLeaveText) or DEFAULTS.leaveText
        end
        return (store and store.combatAlertEnterText) or DEFAULTS.enterText
    end

    local function ShowAlert(which, preview)
        local red, green, blue = ResolveColor(which)
        CludesUI.Alerts.Line("combat").Show(AlertText(which), red, green, blue, preview)
    end

    local function OnCombatEvent(_, eventName)
        local store = CludesUIDB
        if not (store and store.combatAlertEnabled) then
            return
        end
        local mode = store.combatAlertMode or "both"
        if eventName == "PLAYER_REGEN_DISABLED" then
            if mode ~= "leave" then
                ShowAlert("enter")
            end
        elseif eventName == "PLAYER_REGEN_ENABLED" then
            if mode ~= "enter" then
                ShowAlert("leave")
            end
        end
    end

    local function ApplyCombatAlert()
        local isEnabled = CludesUIDB and CludesUIDB.combatAlertEnabled
        if isEnabled and not isInstalled then
            watchFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            watchFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            isInstalled = true
        elseif not isEnabled and isInstalled then
            watchFrame:UnregisterAllEvents()
            isInstalled = false
            CludesUI.Alerts.Hide("combat")
        end
        CludesUI.Alerts.Refresh()
    end
    CludesUI._applyCombatAlert = ApplyCombatAlert

    -- Fires a sample alert for the given transition so the look can be checked from the options cog without a real combat change.
    CludesUI._combatAlertPreview = function(which)
        ShowAlert(which, true)
    end

    -- Re-apply size/position (called from the Text Size slider).
    CludesUI._applyCombatAlertFrame = function()
        CludesUI.Alerts.Refresh()
    end

    watchFrame = CreateFrame("Frame")
    watchFrame:SetScript("OnEvent", OnCombatEvent)

    local bootFrame = CreateFrame("Frame")
    bootFrame:RegisterEvent("PLAYER_LOGIN")
    bootFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if CludesUIDB and CludesUIDB.combatAlertEnabled then
            ApplyCombatAlert()
        end
    end)
end

-------------------------------------------------------------------------------
--  Target Distance Text -- floating distance text for the target, movable in
--  Unlock Mode. Default format is the item-ladder bracket ("30-35"); optional
--  "30+" (spell-ladder lower bound) or "30" (minimum yards). Answers come from
--  the shared engine (CludesUI_Range.lua), activated only while enabled. Color by yard bracket. Off by default.
-------------------------------------------------------------------------------
do
    local distancePanel
    local driver
    local rangeEvents
    local isInstalled = false
    local acc = 0
    local DEFAULT_TEXT_SIZE = 18
    local DEFAULT_FORMAT = "range" -- "range" (30-35) | "plus" (30+) | "min" (30)
    local DEFAULT_ALIGN = "CENTER" -- "LEFT" | "CENTER" | "RIGHT"
    local DEFAULT_POS = { point = "CENTER", relPoint = "CENTER", x = 0, y = 120 }

    local function GetFormat()
        local frame = CludesUIDB and CludesUIDB.targetDistanceFormat
        if frame == "plus" or frame == "min" or frame == "range" then
            return frame
        end
        return DEFAULT_FORMAT
    end

    local function GetAlign()
        local a = CludesUIDB and CludesUIDB.targetDistanceAlign
        if a == "LEFT" or a == "CENTER" or a == "RIGHT" then
            return a
        end
        return DEFAULT_ALIGN
    end

    local function ColorForYards(distYards)
        if distYards <= 8 then
            return 0.30, 0.95, 0.40
        elseif distYards <= 15 then
            return 0.85, 0.95, 0.25
        elseif distYards <= 25 then
            return 1.00, 0.85, 0.20
        elseif distYards <= 40 then
            return 1.00, 0.55, 0.15
        end
        return 0.95, 0.25, 0.20
    end

    local function FormatDistance(formatStr, lowestY, maxY)
        -- Ladder rungs carry the spell's raw range (a float for some spells); the text shows whole yards.
        if lowestY then
            lowestY = math.floor(lowestY)
        end
        if maxY then
            maxY = math.floor(maxY)
        end
        if formatStr == "plus" then
            if not lowestY or lowestY <= 0 then
                return nil
            end
            return lowestY .. "+"
        elseif formatStr == "min" then
            if not lowestY or lowestY <= 0 then
                return nil
            end
            return tostring(lowestY)
        end
        -- range (default): "30-35", or "80+" beyond the last rung; inside the closest check shows "1-X" (familiar melee band) not "0-X".
        if maxY then
            local lo = (lowestY and lowestY > 0) and lowestY or 1
            return lo .. "-" .. maxY
        end
        if lowestY and lowestY >= 80 then
            return "80+"
        end
        if lowestY and lowestY > 0 then
            return lowestY .. "+"
        end
        return nil
    end

    local function ResolveDisplay(unitToken)
        local formatStr = GetFormat()
        if formatStr == "plus" then
            local lower = CludesUI.Range_LowerBound(unitToken)
            if not lower or lower <= 0 then
                return nil
            end
            return FormatDistance("plus", lower, nil), lower
        end
        local lowestY, maxY = CludesUI.Range_ItemBracket(unitToken)
        if lowestY == nil then
            return nil
        end
        local textValue = FormatDistance(formatStr, lowestY, maxY)
        if not textValue then
            return nil
        end
        local colorY = maxY or lowestY
        return textValue, colorY
    end

    local function SampleForFormat()
        local formatStr = GetFormat()
        if formatStr == "plus" then
            return "30+", 30
        end
        if formatStr == "min" then
            return "30", 30
        end
        return "25-30", 25
    end

    local function ApplyFrameSettings()
        if not distancePanel then
            return
        end
        local fontFile = (CludesUI.GetFontPath("extras")) or CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
        local outlineFlag = (CludesUI.GetFontOutlineFlag("extras")) or ""
        if not outlineFlag:find("OUTLINE") then
            outlineFlag = (outlineFlag == "") and "OUTLINE" or (outlineFlag .. ", OUTLINE")
        end
        local px = (CludesUIDB and CludesUIDB.targetDistanceTextSize) or DEFAULT_TEXT_SIZE
        -- HIGH = the pre-setting strata, so existing installs keep their look; the
        -- setting is the opt-in to sit lower (e.g. under the bank window).
        local strata = (CludesUIDB and CludesUIDB.targetDistanceStrata) or "HIGH"
        local align = GetAlign()
        distancePanel._text:SetFont(fontFile, px, outlineFlag)
        distancePanel._text:SetJustifyH(align)
        distancePanel._text:ClearAllPoints()
        distancePanel._text:SetPoint(align, distancePanel, align, 0, 0)
        distancePanel:SetFrameStrata(strata)
        distancePanel:SetSize(px * 5, px + 10)

        -- Unlock Mode owns anchors while dragging, or when Anchor-to is linked.
        if CludesUI._unlockActive then
            return
        end
        if CludesUIDB and CludesUIDB.unlockAnchors and CludesUIDB.unlockAnchors.CUI_TargetDistance then
            return
        end

        distancePanel:ClearAllPoints()
        local place = CludesUIDB and CludesUIDB.targetDistancePos
        if place and place.point then
            distancePanel:SetPoint(
                place.point,
                UIParent,
                place.relPoint or place.point,
                place.x or 0,
                place.y or 0
            )
        else
            distancePanel:SetPoint(
                DEFAULT_POS.point,
                UIParent,
                DEFAULT_POS.relPoint,
                DEFAULT_POS.x,
                DEFAULT_POS.y
            )
        end
    end

    local function CreateDistFrame()
        if distancePanel then
            return
        end
        distancePanel = CreateFrame("Frame", nil, UIParent)
        distancePanel:SetSize(100, 28)
        distancePanel:SetFrameLevel(55)
        distancePanel:EnableMouse(false)
        distancePanel:SetMouseClickEnabled(false)
        local fontStr = distancePanel:CreateFontString(nil, "OVERLAY")
        fontStr:SetPoint("CENTER", distancePanel, "CENTER", 0, 0)
        fontStr:SetJustifyH("CENTER")
        distancePanel._text = fontStr
        ApplyFrameSettings()
        distancePanel:Hide()
    end

    local function ShowSample()
        CreateDistFrame()
        ApplyFrameSettings()
        local textValue, colorY = SampleForFormat()
        distancePanel._text:SetText(textValue)
        distancePanel._text:SetTextColor(ColorForYards(colorY))
        distancePanel:SetAlpha(1)
        distancePanel:Show()
    end

    local function IsEnabled()
        return CludesUIDB and CludesUIDB.targetDistanceEnabled
    end

    local Tick -- forward decl for StartDriver closures

    local function StopDriver()
        CludesUI.Range_SetActive("qolTargetDistance", false)
        if rangeEvents then
            rangeEvents:UnregisterAllEvents()
        end
        if driver then
            driver:SetScript("OnUpdate", nil)
            driver:Hide()
        end
        isInstalled = false
        acc = 0
        if distancePanel then
            distancePanel:Hide()
        end
    end

    local function StartDriver()
        if not driver then
            driver = CreateFrame("Frame")
            driver:Hide()
        end
        if not rangeEvents then
            rangeEvents = CreateFrame("Frame")
            rangeEvents:SetScript("OnEvent", function()
                if not IsEnabled() then
                    return
                end
                Tick()
            end)
        end
        driver:SetScript("OnUpdate", function(_, elapsed)
            if not IsEnabled() then
                return
            end
            acc = acc + elapsed
            if acc < 0.2 then
                return
            end
            acc = 0
            Tick()
        end)
        rangeEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
        -- Ladder builds and invalidation live in the shared range engine.
        CludesUI.Range_SetActive("qolTargetDistance", true)
        driver:Show()
        isInstalled = true
    end

    Tick = function()
        if not IsEnabled() then
            return
        end
        if CludesUI._unlockActive then
            ShowSample()
            return
        end
        if not UnitExists("target") then
            if distancePanel then
                distancePanel:Hide()
            end
            return
        end
        local textValue, colorY = ResolveDisplay("target")
        if not textValue then
            if distancePanel then
                distancePanel:Hide()
            end
            return
        end
        CreateDistFrame()
        ApplyFrameSettings()
        distancePanel._text:SetText(textValue)
        distancePanel._text:SetTextColor(ColorForYards(colorY))
        distancePanel:Show()
    end

    local function ApplyTargetDistance()
        if IsEnabled() then
            if not isInstalled then
                StartDriver()
            end
            Tick()
            if distancePanel then
                ApplyFrameSettings()
            end
        else
            StopDriver()
        end
    end
    CludesUI._applyTargetDistance = ApplyTargetDistance

    CludesUI._applyTargetDistanceFrame = function()
        if not IsEnabled() then
            return
        end
        CreateDistFrame()
        ApplyFrameSettings()
        Tick()
    end

    C_Timer.After(2, function()
        if not (CludesUI and CludesUI.RegisterUnlockElements) then
            return
        end
        local MK = CludesUI.MakeUnlockElement
        if not MK then
            return
        end
        CludesUI:RegisterUnlockElements({
            MK({
                key = "CUI_TargetDistance",
                label = "Target Distance",
                group = "Utilities",
                order = 722,
                noResize = true,
                isHidden = function()
                    return not IsEnabled()
                end,
                getFrame = function()
                    if not IsEnabled() then
                        return nil
                    end
                    CreateDistFrame()
                    if CludesUI._unlockActive then
                        ShowSample()
                    end
                    return distancePanel
                end,
                getSize = function()
                    local px = (CludesUIDB and CludesUIDB.targetDistanceTextSize) or DEFAULT_TEXT_SIZE
                    return px * 5, px + 10
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    if not anchorPoint then
                        return
                    end
                    if not CludesUIDB then
                        CludesUIDB = {}
                    end
                    CludesUIDB.targetDistancePos =
                        { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    if distancePanel and not CludesUI._unlockActive then
                        ApplyFrameSettings()
                    end
                end,
                loadPos = function()
                    local place = CludesUIDB and CludesUIDB.targetDistancePos
                    if place and place.point then
                        return place
                    end
                    return {
                        point = DEFAULT_POS.point,
                        relPoint = DEFAULT_POS.relPoint,
                        x = DEFAULT_POS.x,
                        y = DEFAULT_POS.y,
                    }
                end,
                clearPos = function()
                    if CludesUIDB then
                        CludesUIDB.targetDistancePos = nil
                    end
                    if distancePanel then
                        ApplyFrameSettings()
                    end
                end,
                applyPos = function()
                    if not IsEnabled() then
                        return
                    end
                    CreateDistFrame()
                    ApplyFrameSettings()
                    if CludesUI._unlockActive then
                        ShowSample()
                    end
                end,
            }),
        })
    end)

    -- One-shot login: only starts the driver when the option is already on.
    local bootFrame = CreateFrame("Frame")
    bootFrame:RegisterEvent("PLAYER_LOGIN")
    bootFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        self:SetScript("OnEvent", nil)
        if IsEnabled() then
            ApplyTargetDistance()
        end
    end)
end

-------------------------------------------------------------------------------
--  Hide Item Transforms -- cancels cosmetic transform auras (profession gear,
--  holiday costumes, toys, consumables) as soon as they land. CancelUnitBuff is
--  blocked in combat, so mid-fight transforms sweep on the next PLAYER_REGEN_ENABLED.
--  The fishing outfit aura persists for the channel's duration, so it's cleared
--  on channel-stop instead. No events registered unless on AND something's included.
-------------------------------------------------------------------------------
do
    local CATEGORY_ORDER = { "professions", "holiday", "toys", "items" }
    local CATEGORY_LABEL = {
        professions = "Profession Gear",
        holiday = "Holiday Costumes",
        toys = "Toys",
        items = "Consumables & Items",
    }

    -- Each entry: stable settings key, category, display label, aura spell IDs.
    -- Fishing lists no aura IDs -- the channel-stop watcher below owns it.
    local TRANSFORMS = {
        -- Profession gear
        { key = "blacksmithing", cat = "professions", label = "Blacksmithing", ids = { 388658 } },
        { key = "jewelcrafting", cat = "professions", label = "Jewelcrafting", ids = { 394015 } },
        { key = "tailoring", cat = "professions", label = "Tailoring", ids = { 391312 } },
        { key = "engineering", cat = "professions", label = "Engineering", ids = { 394007 } },
        { key = "enchanting", cat = "professions", label = "Enchanting", ids = { 394008 } },
        { key = "alchemy", cat = "professions", label = "Alchemy", ids = { 394003 } },
        { key = "inscription", cat = "professions", label = "Inscription", ids = { 394016 } },
        { key = "leatherworking", cat = "professions", label = "Leatherworking", ids = { 394001 } },
        { key = "herbalism", cat = "professions", label = "Herbalism", ids = { 394005 } },
        { key = "mining", cat = "professions", label = "Mining", ids = { 394006 } },
        { key = "skinning", cat = "professions", label = "Skinning", ids = { 394011 } },
        { key = "cooking", cat = "professions", label = "Cooking (Chef's Hat)", ids = { 391775 } },
        { key = "fishing", cat = "professions", label = "Fishing", ids = {} },

        -- Holiday costumes
        { key = "lantern", cat = "holiday", label = "Weighted Jack-o'-Lantern", ids = { 44212 } },
        {
            key = "hallowed",
            cat = "holiday",
            label = "Hallowed Wand",
            ids = {
                172010,
                218132,
                191703,
                24732,
                191210,
                172015,
                24735,
                24736,
                191698,
                191700,
                172008,
                24712,
                24713,
                191701,
                191211,
                24710,
                24711,
                191686,
                191688,
                24708,
                24709,
                173958,
                173959,
                191682,
                191683,
                24723,
                191702,
                172003,
                172020,
                191208,
                24740,
            },
        },
        { key = "noblebunny", cat = "holiday", label = "Noblegarden Bunny", ids = { 61734, 61716 } },
        { key = "turkey", cat = "holiday", label = "Pilgrim's Turkey", ids = { 61781 } },

        -- Toys
        { key = "aqir", cat = "toys", label = "Aqir Egg Cluster", ids = { 318452 } },
        {
            key = "atomic",
            cat = "toys",
            label = "Atomically Recalibrator",
            ids = { 399502 },
            defaultOff = true,
        },
        {
            key = "atomgoblin",
            cat = "toys",
            label = "Atomically Regoblinator",
            ids = { 1215363 },
            defaultOff = true,
        },
        { key = "blight", cat = "toys", label = "Detoxified Blight Grenade", ids = { 290224 } },
        { key = "witch", cat = "toys", label = "Lucille's Sewing Needle", ids = { 279509 } },
        {
            key = "spraybots",
            cat = "toys",
            label = "Spraybots",
            ids = { 301892, 301893, 301894 },
        },

        -- Consumables & items
        { key = "pickaxe", cat = "items", label = "Cursed Pickaxe", ids = { 454405 } },
        {
            key = "noggenfogger",
            cat = "items",
            label = "Noggenfogger Elixir",
            ids = { 16593, 1223630, 16595, 1223629, 1223631 },
        },
        { key = "prism", cat = "items", label = "Reflecting Prism", ids = { 163267 } },
    }

    -- Runtime lookup: [spellID] = true for every included transform.
    local cTable = {}

    -- Per-key default: included unless defaultOff; picker stores only values that differ from default, so nil = default.
    local ITEM_DEFAULT = {}
    for _, entry in ipairs(TRANSFORMS) do
        ITEM_DEFAULT[entry.key] = not entry.defaultOff
    end

    local function ItemEnabled(settingKey)
        local tbl = CludesUIDB and CludesUIDB.hideTransformItems
        local val = tbl and tbl[settingKey]
        if val ~= nil then
            return val
        end
        return ITEM_DEFAULT[settingKey] ~= false
    end

    local function RebuildList()
        wipe(cTable)
        if not (CludesUIDB and CludesUIDB.hideTransforms) then
            return
        end
        for _, entry in ipairs(TRANSFORMS) do
            if ItemEnabled(entry.key) then
                for _, ident in ipairs(entry.ids) do
                    cTable[ident] = true
                end
            end
        end
    end

    local auraWatch = CreateFrame("Frame")

    -- Index scans hard-error while aura restrictions are active (M+/raids, even
    -- out of combat); cosmetic transforms just skip there, re-running on the next event outside.
    local function AurasRestricted()
        local AK = CludesUI and CludesUI.AuraKit
        if AK and AK.AurasRestricted then
            return AK.AurasRestricted()
        end
        return false
    end

    -- Sweep current buffs, canceling any included transform. Descending so a cancel (shifts later indices down) can't skip a match.
    local function CancelMatching(force)
        if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then
            return
        end
        if not force and UnitAffectingCombat("player") then
            return
        end
        if AurasRestricted() then
            return
        end
        for i = 40, 1, -1 do
            local payload = C_UnitAuras.GetBuffDataByIndex("player", i)
            if payload then
                local spellId = payload.spellId
                if spellId and not (issecretvalue and issecretvalue(spellId)) and cTable[spellId] then
                    CancelUnitBuff("player", i)
                end
            end
        end
    end

    auraWatch:SetScript("OnEvent", function(_, eventName, _, updateInfo)
        if eventName == "PLAYER_REGEN_ENABLED" then
            -- Combat just ended: clear anything that landed while locked.
            CancelMatching(true)
            return
        end
        -- UNIT_AURA (player only, via RegisterUnitEvent). The payload (and its fields) can be secret in
        -- restricted content -- boolean use of a secret errors, so bail rather than error the sweep.
        if not updateInfo then
            return
        end
        if issecretvalue and issecretvalue(updateInfo) then
            return
        end
        local isFull = updateInfo.isFullUpdate
        if isFull ~= nil and issecretvalue and issecretvalue(isFull) then
            return
        end
        if isFull then
            CancelMatching(false)
        elseif updateInfo.addedAuras then
            for _, aura in ipairs(updateInfo.addedAuras) do
                local spellId = aura.spellId
                if spellId and not (issecretvalue and issecretvalue(spellId)) and cTable[spellId] then
                    CancelMatching(false)
                    break
                end
            end
        end
    end)

    -- Fishing outfit: aura 394009 sticks while the fishing channel (131476) runs,
    -- so it's cleared on channel-stop. Registered only while on and Fishing is included.
    local fishFrame = CreateFrame("Frame")
    fishFrame:SetScript("OnEvent", function(_, _, _, _, spellId)
        if issecretvalue and issecretvalue(spellId) then
            return
        end
        if spellId ~= 131476 then
            return
        end
        if UnitAffectingCombat("player") then
            return
        end
        if not (C_UnitAuras and C_UnitAuras.GetBuffDataByIndex) then
            return
        end
        if AurasRestricted() then
            return
        end
        for i = 40, 1, -1 do
            local payload = C_UnitAuras.GetBuffDataByIndex("player", i)
            if payload then
                local spellRef = payload.spellId
                if spellRef and not (issecretvalue and issecretvalue(spellRef)) and spellRef == 394009 then
                    CancelUnitBuff("player", i)
                end
            end
        end
    end)

    -- (Re)decide which events are hooked. Nothing registers unless on AND
    -- something's included, so a disabled feature costs zero: handlers are never installed.
    local function ApplyHideTransforms()
        RebuildList()
        local isEnabled = CludesUIDB and CludesUIDB.hideTransforms

        if isEnabled and next(cTable) ~= nil then
            auraWatch:RegisterUnitEvent("UNIT_AURA", "player")
            auraWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
            CancelMatching(false) -- immediate sweep of anything already active
        else
            auraWatch:UnregisterEvent("UNIT_AURA")
            auraWatch:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end

        if isEnabled and ItemEnabled("fishing") then
            fishFrame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        else
            fishFrame:UnregisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
        end
    end
    CludesUI._applyHideTransforms = ApplyHideTransforms

    -- Shared with the options picker popup (CUI_QoL_Options.lua).
    CludesUI.HideTransformsData = {
        order = CATEGORY_ORDER,
        labels = CATEGORY_LABEL,
        items = TRANSFORMS,
    }
    CludesUI.GetHideTransformItem = ItemEnabled
    CludesUI.SetHideTransformItem = function(settingKey, isEnabled)
        if not CludesUIDB then
            CludesUIDB = {}
        end
        CludesUIDB.hideTransformItems = CludesUIDB.hideTransformItems or {}
        -- Store only values that differ from the per-key default, keeping the table sparse.
        isEnabled = isEnabled and true or false
        if isEnabled == (ITEM_DEFAULT[settingKey] ~= false) then
            CludesUIDB.hideTransformItems[settingKey] = nil
        else
            CludesUIDB.hideTransformItems[settingKey] = isEnabled
        end
        ApplyHideTransforms()
    end

    local bootFrame = CreateFrame("Frame")
    bootFrame:RegisterEvent("PLAYER_LOGIN")
    bootFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        ApplyHideTransforms()
    end)
end

-------------------------------------------------------------------------------
--  Equipment Flyout item levels -- Blizzard's gear flyout (hover a character-
--  sheet slot -> popup of same-slot bag/equipped items) only shows icons; when
--  enabled, overlays each button with the item's level, coloured by quality. Hooks
--  EquipmentFlyout_UpdateItems (after every flyout shape is populated) and reads CludesUIDB
--  live, so the toggle applies to the next flyout with no reload. Toggle: CludesUIDB.flyoutItemLevels (Quality of Life -> UI).
--  CludesUIDB.flyoutItemStats adds the stat letters (CludesUI.GetItemStatLetters)
--  centred along the bottom edge; flyoutItemStatsTertiary == true adds Leech/Avoidance/Speed.
-------------------------------------------------------------------------------
do
    local function FlyoutEnabled()
        return CludesUIDB and CludesUIDB.flyoutItemLevels
    end

    -- Item level + quality + link from a decoded bag/slot pair. Prefers the ItemLocation API (exact, no caching); falls back to the item link.
    local function LevelFromSlot(isBags, bagId, slotId)
        if isBags then
            if ItemLocation then
                local location = ItemLocation:CreateFromBagAndSlot(bagId, slotId)
                if location and location:IsValid() and C_Item.DoesItemExist(location) then
                    return C_Item.GetCurrentItemLevel(location),
                        C_Item.GetItemQuality(location),
                        C_Item.GetItemLink(location)
                end
            end
            local itemLink = C_Container and C_Container.GetContainerItemLink(bagId, slotId)
            if itemLink then
                return C_Item.GetDetailedItemLevelInfo(itemLink),
                    select(3, C_Item.GetItemInfo(itemLink)),
                    itemLink
            end
            return
        end
        -- Equipped inventory slot.
        if ItemLocation then
            local location = ItemLocation:CreateFromEquipmentSlot(slotId)
            if location and location:IsValid() and C_Item.DoesItemExist(location) then
                return C_Item.GetCurrentItemLevel(location), C_Item.GetItemQuality(location), C_Item.GetItemLink(location)
            end
        end
        local itemLink = GetInventoryItemLink("player", slotId)
        if itemLink then
            local quality = GetInventoryItemQuality and GetInventoryItemQuality("player", slotId)
            return C_Item.GetDetailedItemLevelInfo(itemLink),
                quality or select(3, C_Item.GetItemInfo(itemLink)),
                itemLink
        end
    end

    -- Item level + quality + link for a flyout button. Handles all three flyout
    -- shapes: modern buttons storing an ItemLocation object; retail packed location
    -- via EquipmentManager_GetLocationData; older clients via EquipmentManager_UnpackLocation.
    local function ButtonItemInfo(btnFrame, useItemLocation)
        if useItemLocation and btnFrame.GetItemLocation then
            local ok, location = pcall(btnFrame.GetItemLocation, btnFrame)
            if ok and location and location.IsValid and location:IsValid() and C_Item.DoesItemExist(location) then
                return C_Item.GetCurrentItemLevel(location), C_Item.GetItemQuality(location), C_Item.GetItemLink(location)
            end
        end

        local location = btnFrame.location
        if not location or type(location) ~= "number" then
            return
        end
        if EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION and location >= EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
            return
        end

        if EquipmentManager_GetLocationData then
            local ld = EquipmentManager_GetLocationData(location)
            if not ld or ld.slot == nil then
                return
            end
            return LevelFromSlot(ld.isBags, ld.bag, ld.slot)
        elseif EquipmentManager_UnpackLocation then
            local _, _, bags, voidStorage, slotId, bagId = EquipmentManager_UnpackLocation(location)
            if voidStorage then
                return
            end
            return LevelFromSlot(bags, bagId, slotId)
        end
    end

    -- Item-level FontStrings live in an external weak-keyed table, NOT on the
    -- button: flyout buttons are Blizzard-owned (secure item-equipping path), so a
    -- custom key would taint execution. Creating the FontString as a child is fine; only the reference stays off the frame table.
    local _flyoutFS = setmetatable({}, { __mode = "k" }) -- [button] = fontstring

    -- Lazily attach (and return) the item-level FontString for a flyout button.
    local function EnsureText(btnFrame)
        local fontStr = _flyoutFS[btnFrame]
        if not fontStr then
            local font = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
            local flag = CludesUI.SlugFlag("OUTLINE, SLUG")
            fontStr = btnFrame:CreateFontString(nil, "OVERLAY", nil, 7)
            fontStr:SetFont(font, 12, flag)
            fontStr:SetPoint("TOP", btnFrame, "TOP", 0, -2)
            fontStr:SetJustifyH("CENTER")
            _flyoutFS[btnFrame] = fontStr
        end
        return fontStr
    end

    -- Stat letters ("MH", tertiaries smaller behind them: "L") centred along
    -- the button's bottom edge, kept off the button like the item level above.
    local _flyoutStatFS = setmetatable({}, { __mode = "k" }) -- [button] = fontstring
    local _flyoutTerFS = setmetatable({}, { __mode = "k" }) -- [button] = fontstring

    local function EnsureStatText(btnFrame)
        local fontStr = _flyoutStatFS[btnFrame]
        if not fontStr then
            local font = CludesUI._font or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
            local flag = CludesUI.SlugFlag("OUTLINE, SLUG")
            fontStr = btnFrame:CreateFontString(nil, "OVERLAY", nil, 7)
            fontStr:SetFont(font, 11, flag)
            fontStr:SetTextColor(1, 1, 1, 1)
            local ter = btnFrame:CreateFontString(nil, "OVERLAY", nil, 7)
            ter:SetFont(font, 8, flag)
            ter:SetPoint("BOTTOMLEFT", fontStr, "BOTTOMRIGHT", 1, 0)
            ter:SetTextColor(0.94, 0.66, 0.94, 1)
            _flyoutStatFS[btnFrame] = fontStr
            _flyoutTerFS[btnFrame] = ter
        end
        return fontStr, _flyoutTerFS[btnFrame]
    end

    -- Built for a button the first time its item has letters to show. True
    -- while the item's data is still on the way (paint again).
    local function PaintStats(btnFrame, itemLink, withTertiary)
        local fontStr, ter = _flyoutStatFS[btnFrame], _flyoutTerFS[btnFrame]
        if itemLink and not fontStr then
            local sec, tert, waiting = CludesUI.GetItemStatLetters(itemLink)
            if sec == "" and (tert == "" or not withTertiary) then
                return waiting
            end
            fontStr, ter = EnsureStatText(btnFrame)
        end
        if fontStr then
            return CludesUI.PaintStatLetters(fontStr, ter, itemLink, withTertiary, btnFrame)
        end
    end

    -- The item link at a flyout button, read with no tables built: the
    -- button's ItemLocation, else its numeric location decoded with the bit
    -- layout EquipmentManager_GetLocationData uses. Nil for an empty or special
    -- location.
    local band, rshift, lshift = bit.band, bit.rshift, bit.lshift
    local function ButtonLink(btnFrame, useItemLocation)
        if useItemLocation and btnFrame.GetItemLocation then
            local ok, location = pcall(btnFrame.GetItemLocation, btnFrame)
            if ok and location and location.IsValid and location:IsValid() and C_Item.DoesItemExist(location) then
                return C_Item.GetItemLink(location)
            end
        end
        local location = btnFrame.location
        if type(location) ~= "number" or location < 0 then
            return
        end
        if EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION and location >= EQUIPMENTFLYOUT_FIRST_SPECIAL_LOCATION then
            return
        end
        local slotId = location
        local isBank = band(location, ITEM_INVENTORY_LOCATION_BANK) ~= 0
        if band(location, ITEM_INVENTORY_LOCATION_PLAYER) ~= 0 then
            slotId = slotId - ITEM_INVENTORY_LOCATION_PLAYER
        elseif isBank then
            slotId = slotId - ITEM_INVENTORY_LOCATION_BANK
        end
        if band(location, ITEM_INVENTORY_LOCATION_BAGS) ~= 0 then
            slotId = slotId - ITEM_INVENTORY_LOCATION_BAGS
            local bagId = rshift(slotId, ITEM_INVENTORY_BAG_BIT_OFFSET)
            slotId = slotId - lshift(bagId, ITEM_INVENTORY_BAG_BIT_OFFSET)
            if isBank then
                bagId = bagId + ITEM_INVENTORY_BANK_BAG_OFFSET
            end
            return C_Container.GetContainerItemLink(bagId, slotId)
        end
        return GetInventoryItemLink("player", slotId)
    end

    -- What each button shows (weak-keyed, off the button like its texts): the
    -- link and the settings it was painted for. Blizzard runs the whole flyout
    -- again every frame while a slot's flyout is pinned open, so a button whose
    -- item and settings are unchanged keeps its paint; a paint still waiting on
    -- item data is redone.
    local _flyoutPaint = setmetatable({}, { __mode = "k" }) -- [button] = state

    local function PaintButton(btnFrame, useItemLocation)
        local showIlvl = FlyoutEnabled() and true or false
        -- Stat letters are retail-only (their rows are not built on WoW Forever).
        local showStats = not CludesUI.IS_FOREVER and CludesUIDB and CludesUIDB.flyoutItemStats and true
            or false
        local withTertiary = CludesUIDB and CludesUIDB.flyoutItemStatsTertiary == true or false
        local itemLink
        if (showIlvl or showStats) and btnFrame:IsShown() then
            itemLink = ButtonLink(btnFrame, useItemLocation)
        end
        local m = _flyoutPaint[btnFrame]
        if
            m
            and not m.pending
            and m.link == itemLink
            and m.ilvl == showIlvl
            and m.stats == showStats
            and m.ter == withTertiary
        then
            return
        end
        if not m then
            m = {}
            _flyoutPaint[btnFrame] = m
        end
        m.link, m.ilvl, m.stats, m.ter, m.pending = itemLink, showIlvl, showStats, withTertiary, false

        local fontStr = _flyoutFS[btnFrame]
        if not itemLink then
            if fontStr then
                fontStr:SetText("")
            end
            PaintStats(btnFrame, nil, withTertiary)
            return
        end

        local ilvl, quality = ButtonItemInfo(btnFrame, useItemLocation)
        m.pending = PaintStats(btnFrame, showStats and itemLink or nil, withTertiary) and true or false
        if not showIlvl then
            if fontStr then
                fontStr:SetText("")
            end
            return
        end
        fontStr = EnsureText(btnFrame)
        if ilvl and ilvl > 0 then
            fontStr:SetText(ilvl)
            -- Match the character sheet: custom color > upgrade/crafted track > rarity.
            local c
            if CludesUI.GetItemLevelColor then
                c = CludesUI.GetItemLevelColor(itemLink, quality)
            elseif quality and ITEM_QUALITY_COLORS then
                c = ITEM_QUALITY_COLORS[quality]
            end
            if c then
                fontStr:SetTextColor(c.r, c.g, c.b, 1)
            else
                fontStr:SetTextColor(1, 1, 1, 1)
            end
        else
            fontStr:SetText("")
            -- No level yet while the item's data is still on the way.
            if not C_Item.GetItemInfo(itemLink) then
                m.pending = true
            end
        end
    end

    local function RefreshFlyoutItemLevels()
        local flyout = EquipmentFlyoutFrame
        if not flyout or not flyout.buttons then
            return
        end
        local source = flyout.button
        local hostFrame = source and source:GetParent()
        local prefs = hostFrame and hostFrame.flyoutSettings
        local useItemLocation = prefs and prefs.useItemLocation == true
        for _, btnFrame in ipairs(flyout.buttons) do
            PaintButton(btnFrame, useItemLocation)
        end
    end

    local function InstallHook()
        if not EquipmentFlyout_UpdateItems then
            return
        end
        -- Item-upgrade flyouts use ItemLocation objects and bypass
        -- EquipmentFlyout_DisplayButton entirely. They also leave that ItemLocation
        -- on pooled buttons when an ordinary numeric-location flyout reuses them.
        -- Refresh after the shared update and follow the active flyout's mode, so
        -- both paths repaint instead of inheriting the other's item or overlay.
        hooksecurefunc("EquipmentFlyout_UpdateItems", RefreshFlyoutItemLevels)
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        InstallHook()
    end)
end
