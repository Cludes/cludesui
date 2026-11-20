if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CludesUI_GoldLedger.lua -- the one gold record shared by Bags and DataBars.
--
--  ACCOUNT-level, NOT the profile: it lists the player's characters and
--  balances, and a profile copy would ride export strings (CludesUI_Profiles
--  FULL_EXPORT_EXCLUDED keeps this key out of full-account exports too).
--
--  CludesUIDB.goldLedger = {
--      chars    = { [guid] = { money, class, name, realm, updated } },
--      warband  = { money, updated },    -- nil until first successful read
--      tracking = false,                 -- only present when switched off
--  }
--  By GUID: WoW Forever first names are not the whole name, and a rename keeps
--  it. Entries from older builds sit under "Name-Realm" until that character
--  next logs in.
--  money is copper. A character's entry is only ever written by that character
--  while it is online, so an offline entry is its balance at logout.
--
--  The ledger owns money tracking for every module: one tracking switch
--  (IsTracking / SetTracking, account-wide) and one set of money events,
--  registered only while a module is Register()ed. Modules never register
--  PLAYER_MONEY / ACCOUNT_MONEY themselves; they get a callback after the
--  ledger has recorded. With the switch off nothing is written and only
--  PLAYER_MONEY stays registered, so displays and live reads keep working.
--
--  Built lazily: CludesUI.GetGoldLedger() creates it on the first call, and
--  only a module that is actually loading calls it. A setup with neither Bags
--  nor DataBars never builds the ledger, however modules get enabled or
--  disabled.
--------------------------------------------------------------------------------

local CUI = _G.CludesUI
local built

local function Build()
    local GL = {}

    local type, pairs = type, pairs
    local issecretvalue = issecretvalue

    local function IsUsable(val)
        return type(val) == "number" and not (issecretvalue and issecretvalue(val))
    end

    -- "Name-Realm": a character name never contains a hyphen, a realm name can (Azjol-Nerub).
    local function SplitKey(key)
        local name, realm = key:match("^([^%-]+)%-(.+)$")
        return name or key, realm
    end

    --------------------------------------------------------------------------------
    --  One-time absorb of the legacy stores:
    --    CludesUIDB.characterGold  (Bags)     { gold, lastUpdated, class, classColor }
    --    CludesUIDB.dataBarsGold   (DataBars) { currentMoney, class, realm, name }
    --    CludesUIDB.warbandGold    (Bags)     { gold, lastUpdated }
    --  Neither store carries both a balance and a trustworthy age, so when both
    --  know a character and disagree the DataBars value wins (written on every
    --  PLAYER_MONEY, ungated) and the entry has no age until that character next
    --  plays. Runs lazily from Data(); idempotent, and the old keys are dropped.
    --------------------------------------------------------------------------------
    local function MigrateLegacy(saved, ledger)
        local bags, dbars, wband = saved.characterGold, saved.dataBarsGold, saved.warbandGold
        if bags == nil and dbars == nil and wband == nil then
            return
        end
        local chars = ledger.chars

        if type(bags) == "table" then
            for key, bag in pairs(bags) do
                if type(key) == "string" and type(bag) == "table" and IsUsable(bag.gold) and bag.gold >= 0 then
                    local name, realm = SplitKey(key)
                    chars[key] = {
                        money = bag.gold,
                        class = bag.class,
                        name = name,
                        realm = realm,
                        updated = IsUsable(bag.lastUpdated) and bag.lastUpdated or nil,
                    }
                end
            end
        end
        if type(dbars) == "table" then
            for key, bar in pairs(dbars) do
                if
                    type(key) == "string"
                    and type(bar) == "table"
                    and IsUsable(bar.currentMoney)
                    and bar.currentMoney >= 0
                then
                    local current = chars[key]
                    local name, realm = SplitKey(key)
                    if current and current.money == bar.currentMoney then
                        current.class = current.class or bar.class
                        current.name, current.realm = bar.name or current.name, bar.realm or current.realm
                    else
                        chars[key] = {
                            money = bar.currentMoney,
                            class = bar.class,
                            name = bar.name or name,
                            realm = bar.realm or realm,
                        }
                    end
                end
            end
        end
        if type(wband) == "table" and IsUsable(wband.gold) and wband.gold >= 0 and not ledger.warband then
            ledger.warband =
                { money = wband.gold, updated = IsUsable(wband.lastUpdated) and wband.lastUpdated or nil }
        end

        saved.characterGold, saved.dataBarsGold, saved.warbandGold = nil, nil, nil
    end

    -- Bags used to keep the tracking switch per profile (addons.CludesUIBags.enableGoldTracking).
    -- Absorbed once: a profile that had it off turns it off for the account, and the key goes.
    -- Later sessions skip it, so an imported profile cannot flip the account switch.
    local function AbsorbTrackingSwitch(saved, ledger)
        if ledger.trackingMigrated or type(saved.profiles) ~= "table" then
            return
        end
        for _, pd in pairs(saved.profiles) do
            local addons = type(pd) == "table" and pd.addons
            local bags = type(addons) == "table" and addons.CludesUIBags
            if type(bags) == "table" and bags.enableGoldTracking ~= nil then
                if bags.enableGoldTracking == false then
                    ledger.tracking = false
                end
                bags.enableGoldTracking = nil
            end
        end
        ledger.trackingMigrated = true
    end

    --- The ledger table. Never nil; a throwaway table if the account DB is somehow
    --- absent (never assign the global here: a pre-SavedVariables call could
    --- shadow the real table).
    function GL.Data()
        local saved = _G.CludesUIDB
        if type(saved) ~= "table" then
            return { chars = {} }
        end
        local ledger = saved.goldLedger
        if type(ledger) ~= "table" then
            ledger = {}
            saved.goldLedger = ledger
        end
        if type(ledger.chars) ~= "table" then
            ledger.chars = {}
        end
        MigrateLegacy(saved, ledger)
        AbsorbTrackingSwitch(saved, ledger)
        return ledger
    end

    --- The current character's GUID, or nil while it cannot be read.
    function GL.CharKey()
        local unitGuid = UnitGUID("player")
        if not unitGuid or (issecretvalue and issecretvalue(unitGuid)) then
            return nil
        end
        return unitGuid
    end

    -- The only places the modules touch the money APIs. A secret or non-number
    -- read comes back nil, so no caller ever does arithmetic on one.
    local function LiveMoney()
        local money = GetMoney()
        if IsUsable(money) then
            return money
        end
    end

    -- Readable at any time, not only with the warband bank open.
    local function LiveWarband()
        local bank = C_Bank
        if not (bank and bank.FetchDepositedMoney and Enum and Enum.BankType) then
            return nil
        end
        local money = bank.FetchDepositedMoney(Enum.BankType.Account)
        if IsUsable(money) then
            return money
        end
    end

    --- The current character's balance, for display. Does not write the ledger
    --- (writing is the caller's call; Bags can turn tracking off). When the live
    --- read is unusable, falls back to the last stored balance; nil if neither.
    function GL.Money()
        local money = LiveMoney()
        if money then
            return money
        end
        local key = GL.CharKey()
        local e = key and GL.Data().chars[key]
        return e and e.money
    end

    --- The warband bank balance, for display. Live when the read is usable,
    --- otherwise the last stored balance; nil if never seen. Does not write.
    function GL.WarbandMoney()
        local money = LiveWarband()
        if money then
            return money
        end
        local wid = GL.Data().warband
        return wid and wid.money
    end

    --- Store the current character's balance. `money` defaults to a live read.
    --- Returns the balance, or nil when the read was unusable (secret or not a
    --- number); a failed read never overwrites a good entry. Nothing is written
    --- while tracking is off, but the balance is still returned.
    function GL.RecordCharacter(money)
        if money == nil then
            money = LiveMoney()
        end
        if not IsUsable(money) then
            return nil
        end
        if not GL.IsTracking() then
            return money
        end
        local key = GL.CharKey()
        if not key then
            return money
        end
        local chars = GL.Data().chars
        -- Drop the entries older builds filed under "Name-Realm".
        local short = UnitName("player")
        if short then
            chars[short .. "-" .. (CUI.RealmGroupName() or "")] = nil
            chars[short .. "-" .. (GetRealmName() or "")] = nil
        end
        local e = chars[key]
        if not e then
            e = {}
            chars[key] = e
        end
        local _, class = UnitClass("player")
        -- The full name whatever the show-surname preference.
        local name, surname = (UnitNameUnmodified or UnitName)("player")
        e.money, e.class, e.name, e.realm, e.updated =
            money, class, CUI.WithSurname(name, surname, true), CUI.RealmGroupName(), time()
        return money
    end

    --- Store the warband bank balance. An unusable read (secret or not a number)
    --- changes nothing and the stored value stays.
    function GL.RecordWarband()
        if not GL.IsTracking() then
            return nil
        end
        local money = LiveWarband()
        if not money then
            return nil
        end
        local ledger = GL.Data()
        local wid = ledger.warband
        if not wid then
            wid = {}
            ledger.warband = wid
        end
        wid.money, wid.updated = money, time()
        return money
    end

    --- Account-wide tracking switch. On by default; only the off state is stored.
    function GL.IsTracking()
        return GL.Data().tracking ~= false
    end

    function GL.SetTracking(enabled)
        local ledger = GL.Data()
        if enabled == false then
            ledger.tracking = false
        else
            ledger.tracking = nil
        end
        GL.SyncEvents()
        if enabled ~= false then
            GL.RecordCharacter()
            GL.RecordWarband()
        end
    end

    --------------------------------------------------------------------------------
    --  Money events. One frame, registered only while a module is Register()ed.
    --  Tracking on: PLAYER_MONEY, ACCOUNT_MONEY, BANKFRAME_OPENED and
    --  PLAYER_ENTERING_WORLD, each recorded before the callbacks run.
    --  Tracking off: PLAYER_MONEY alone, so displays can repaint; nothing is
    --  recorded and nothing else runs.
    --  Writes from these events are coalesced: the first event of a burst starts a
    --  0.5s timer and one write then stores the latest values, so a flurry of
    --  PLAYER_MONEY (looting, vendor sweeps) costs one table write.
    --  Callbacks run immediately, fn(event, money): the live balance for
    --  character events, nil for warband ones. Display code reads live values.
    --------------------------------------------------------------------------------
    local consumers, consumerCount = {}, 0
    local eventFrame

    function GL.SyncEvents()
        if not eventFrame then
            return
        end
        eventFrame:UnregisterAllEvents()
        if consumerCount == 0 then
            return
        end
        eventFrame:RegisterEvent("PLAYER_MONEY")
        if GL.IsTracking() then
            eventFrame:RegisterEvent("ACCOUNT_MONEY")
            eventFrame:RegisterEvent("BANKFRAME_OPENED")
            eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        end
    end

    local WRITE_DELAY = 0.5
    local dirtyChar, dirtyWarband, flushQueued

    local function FlushWrites()
        flushQueued = false
        if dirtyChar then
            dirtyChar = false
            GL.RecordCharacter()
        end
        if dirtyWarband then
            dirtyWarband = false
            GL.RecordWarband()
        end
    end

    local function OnMoneyEvent(_, evt)
        local money
        if evt ~= "ACCOUNT_MONEY" and evt ~= "BANKFRAME_OPENED" then
            money = LiveMoney()
            if GL.IsTracking() then
                dirtyChar = true
            end
        end
        if evt ~= "PLAYER_MONEY" then
            dirtyWarband = true
        end
        if (dirtyChar or dirtyWarband) and not flushQueued then
            flushQueued = true
            C_Timer.After(WRITE_DELAY, FlushWrites)
        end
        for ownerFrame, func in pairs(consumers) do
            if func ~= true then
                local success, err = pcall(func, evt, money)
                if not success then
                    geterrorhandler()(err)
                end
            end
        end
    end

    --- Start money tracking for `owner` (any unique key). `fn` is optional.
    --- Registering twice for one owner just replaces its callback.
    function GL.Register(ownerFrame, func)
        if consumers[ownerFrame] == nil then
            consumerCount = consumerCount + 1
        end
        consumers[ownerFrame] = func or true
        if not eventFrame then
            eventFrame = CreateFrame("Frame")
            eventFrame:SetScript("OnEvent", OnMoneyEvent)
        end
        GL.SyncEvents()
        if GL.IsTracking() then
            GL.RecordCharacter()
            GL.RecordWarband()
        end
    end

    function GL.Unregister(ownerFrame)
        if consumers[ownerFrame] == nil then
            return
        end
        consumers[ownerFrame] = nil
        consumerCount = consumerCount - 1
        GL.SyncEvents()
    end

    --- Drop a character the player no longer has (renamed, deleted, transferred).
    function GL.Forget(key)
        GL.Data().chars[key] = nil
    end

    --- Wipe every character and the warband figure.
    function GL.Reset()
        local ledger = GL.Data()
        ledger.chars = {}
        ledger.warband = nil
    end

    return GL
end

function CUI.GetGoldLedger()
    if not built then
        built = Build()
    end
    return built
end
