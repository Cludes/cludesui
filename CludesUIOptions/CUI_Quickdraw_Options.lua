if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Quickdraw_Options.lua  --  Settings page for the Quickdraw
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIQuickdraw"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua), which hands a kept page its previous build's
-- frames back reset to new; on any other parent it is the plain CreateFrame.
local Pool = CludesUI._Pool
local CreateFrame = Pool.CreateFrame

local PAGE_DISPLAY = "Action Wheel"
local BINDING_PREFIX = "CUI_RADIAL"
-- Every palette has a <Binding> entry of its own, so the keybind row below
-- applies to all of them. Read from the module rather than restated, so the two
-- can never disagree about how far the binding actions run.
local MAX_PALETTES = mod.MAX_PALETTES or 16
local MAX_SLOTS = mod.MAX_SLOTS or 12

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not CludesUI or not CludesUI.RegisterModule then
        return
    end

    local db

    -- Through ns.Profile, not db.profile: the module converts a profile's
    -- retired key names on first touch, and reading the table directly here
    -- would skip that whenever the panel is the first to see a profile the user
    -- has just switched to. The db local is still kept for the reset handler.
    local function DB()
        db = db or _G._CUQD_AceDB
        if mod.Profile then
            return mod.Profile()
        end
        return db and db.profile
    end

    local function ProfileGet(key)
        local prof = DB()
        if prof then
            return prof[key]
        end
        return prof
    end

    local function ProfilePut(key, val)
        local prof = DB()
        if not prof then
            return
        end
        prof[key] = val
    end

    -- Whether the page was BUILT with the nest-geometry row on it (some menu
    -- holds a nested entry). Rows are structural, so when nest presence flips
    -- under a plain Refresh -- the first nested entry added, the last one
    -- removed -- the refresh escalates to a rebuild and the row appears or
    -- goes with it. HasAnyNest is assigned below MenuCount.
    local builtWithNest = false
    local HasAnyNest

    -- Hands the edited settings to the running module.
    local function PushToModule()
        local apply = _G._CUQD_Apply
        if apply then
            apply()
        end
    end

    local function Reapply()
        PushToModule()
        local nestFlipped = HasAnyNest and HasAnyNest() ~= builtWithNest
        if nestFlipped and CludesUI.RefreshPage then
            CludesUI:RefreshPage(true)
        else
            CludesUI:RefreshPage()
        end
    end

    local function RedrawPage()
        PushToModule()
        CludesUI:RefreshPage(true)
    end

    -- Which palette the ACTION MENU SETUP section is editing. Transient: the editor
    -- is a panel-session concept, not a saved setting.
    local editingMenu = 1

    local function MenuCount()
        local count = ProfileGet("paletteCount") or 1
        if count < 1 then
            count = 1
        elseif count > MAX_PALETTES then
            count = MAX_PALETTES
        end
        return count
    end

    local function MenuTable(index)
        return mod.EnsurePalette and mod.EnsurePalette(index or editingMenu)
    end

    -- A palette as stored, for getters: nothing created or compacted (getters
    -- must not write; the panel's read trace runs them).
    local function PaletteRead(index)
        local prof = DB()
        local stored = prof and prof.palettes
        if type(stored) ~= "table" then
            return nil
        end
        local found = stored[index or editingMenu]
        if type(found) == "table" then
            return found
        end
        return nil
    end

    -- Does ANY menu hold a nested entry? Read-only walk over the stored
    -- tables (never through EnsurePalette, which compacts and allocates):
    -- this runs on every Refresh to notice presence flipping.
    HasAnyNest = function()
        local prof = DB()
        local stored = prof and prof.palettes
        if type(stored) ~= "table" then
            return false
        end
        for i = 1, MenuCount() do
            local entries = type(stored[i]) == "table" and stored[i].slots
            if type(entries) == "table" then
                for n = 1, #entries do
                    local e = entries[n]
                    if type(e) == "table" and e.kind == "palette" then
                        return true
                    end
                end
            end
        end
        return false
    end

    ---------------------------------------------------------------------------
    --  Per-palette appearance
    --
    --  EVERY setting on the page is read and written against the palette the
    --  Editing Action Menu selector is pointed at. The module holds the list
    --  (ns.APPEARANCE_KEYS) and the fallback: a palette with no override of its
    --  own reads the profile's value, so a profile written before any of this
    --  existed draws exactly as it did. Only the module's enable switch and
    --  the menu list itself are profile state through ProfileGet/ProfilePut; the "Apply All
    --  Settings From" row below the preview is the bridge between menus.
    --
    --  The module is outside Spec Overrides (CludesUI_SpecOverrides.lua):
    --  which specs a menu works in is its own Assign to Spec setting instead.
    ---------------------------------------------------------------------------
    local function MenuGet(key)
        local menuT = PaletteRead(editingMenu)
        local own = menuT and menuT.appearance and menuT.appearance[key]
        if own == nil then
            return ProfileGet(key)
        end
        return own
    end

    local function MenuPut(key, val)
        local menuT = mod.EnsurePalette and mod.EnsurePalette(editingMenu)
        if menuT then
            local over = menuT.appearance or {}
            menuT.appearance = over
            over[key] = val
        end
    end

    -- From the module, so the name an emptied box reverts to is the same string
    -- the module hands a fresh palette.
    local function AutoName(index)
        local named = mod.AutoPaletteName
        if not named then
            return "Action Menu " .. index
        end
        return named(index)
    end

    -- A menu's name as the page shows it.
    local function MenuName(index)
        local menuT = PaletteRead(index)
        if menuT and menuT.name then
            return menuT.name
        end
        return AutoName(index)
    end

    -- The icon a menu is listed BY, everywhere one is listed: its first entry,
    -- so a "Mounts" menu looks like a mount without anyone having to pick an
    -- icon for it. Same rule the module's SlotDisplay applies to nested
    -- entries, including the one-level stop: a first entry that is itself a
    -- menu would send this round its own loop. An empty menu shows the bag.
    local function PaletteListIcon(pmenu)
        local first = pmenu and pmenu.slots and pmenu.slots[1]
        local glyph = first and first.kind ~= "palette" and mod.SlotDisplay and mod.SlotDisplay(first)
        return glyph or "Interface\\Icons\\INV_Misc_Bag_08"
    end

    ---------------------------------------------------------------------------
    --  Inline keybind button
    --
    --  Binds the real CUI_RADIAL<n> action declared in Bindings.xml via
    --  SetBinding/SaveBindings, rather than storing a key of our own and
    --  routing it separately. That keeps ONE source of truth: this button and
    --  Blizzard's Keybindings page edit the same binding, GetBindingKey keeps
    --  driving ns.UpdateBindings, and the SaveBindings call fires
    --  UPDATE_BINDINGS so the palette re-routes its override binding by itself.
    --
    --  The button is the shared keybind capture button: it does its own
    --  listening -- left-click arms it, the next key press binds, right-click
    --  unbinds, Escape cancels -- with no overlay of any kind. The page's
    --  wrapper lives in BuildKeybindButton below the page's selector.
    ---------------------------------------------------------------------------

    -- The combat rejections below are the one case where CludesUI.Print is
    -- the wrong channel: it deliberately stays silent in raid combat and in an
    -- active M+ (CludesUI.lua:1519), which is precisely when a user would
    -- hit them and see nothing happen.
    local function Complain(msg)
        msg = CludesUI.L(msg)
        if _G.UIErrorsFrame then
            UIErrorsFrame:AddMessage(msg, 1.0, 0.3, 0.3, 1.0)
        else
            CludesUI.Print(CludesUI.COLOR_CODES.BRAND .. "Action Wheel:|r " .. msg)
        end
    end

    -- What the user calls the action a chord is currently bound to. The binding
    -- system stores an action string; BINDING_NAME_<action> is the label every
    -- keybind UI shows, and our own palettes declare one each.
    local function BindingLabel(bindAction)
        return _G["BINDING_NAME_" .. bindAction] or bindAction
    end

    ---------------------------------------------------------------------------
    --  Shared keys
    --
    --  Two menus that can never load in the same spec (Assign to Spec) may share
    --  a key. WoW's binding holds one action per key, so the key stays on its
    --  holder's CUI_RADIAL binding and the sharer records the holder in
    --  palette.keyShare (ns.ShareOwner); the module sends the key to whichever
    --  of them loads. A holder letting a shared key go hands it to its first
    --  sharer, so the sharers keep it.
    ---------------------------------------------------------------------------
    -- The menus sharing owner's key, in index order.
    local function Sharers(ownerFrame)
        local result = {}
        for i = 1, MenuCount() do
            if i ~= ownerFrame and mod.ShareOwner(i) == ownerFrame then
                result[#result + 1] = i
            end
        end
        return result
    end

    -- Their names joined for a message ("Action Menu 2, Action Menu 3") and
    -- their count, or nil when nothing shares owner's key.
    local function SharerNames(ownerFrame)
        local entries = Sharers(ownerFrame)
        if #entries == 0 then
            return nil
        end
        for num = 1, #entries do
            entries[num] = MenuName(entries[num])
        end
        return table.concat(entries, ", "), #entries
    end

    -- Gives the keys owner lets go to its first sharer, which then holds them
    -- for the rest. Returns that heir, or nil when nothing shares them.
    local function HandOffKeys(ownerFrame, k1, k2)
        local entries = Sharers(ownerFrame)
        local heir = entries[1]
        if not heir then
            return nil
        end
        MenuTable(heir).keyShare = nil
        for num = 2, #entries do
            MenuTable(entries[num]).keyShare = heir
        end
        if k1 then
            SetBinding(k1, BINDING_PREFIX .. heir)
        end
        if k2 then
            SetBinding(k2, BINDING_PREFIX .. heir)
        end
        return heir
    end

    -- May menu idx share the key owner holds? Only when idx can never load
    -- together with owner or with any menu already sharing it.
    local function CanShareWith(position, ownerFrame)
        if not mod.PalettesExclusive(position, ownerFrame) then
            return false
        end
        for _, sv in ipairs(Sharers(ownerFrame)) do
            if sv ~= position and not mod.PalettesExclusive(position, sv) then
                return false
            end
        end
        return true
    end

    -- The menu of this profile a binding action opens, or nil.
    local function PaletteOfAction(bindAction)
        local num = type(bindAction) == "string"
            and tonumber(bindAction:match("^" .. BINDING_PREFIX .. "(%d+)$"))
        if num and num >= 1 and num <= MenuCount() then
            return num
        end
        return nil
    end

    -- Menu idx takes on the key owner holds: the keys idx held stay with the
    -- menus sharing them, or are let go. An owner that itself shared another
    -- menu's key (a key bound to it from Blizzard's Keybindings page) holds
    -- this one of its own now, so its old share ends.
    local function ShareKey(position, ownerFrame, keyChord)
        local k1, k2 = GetBindingKey(BINDING_PREFIX .. position)
        if not HandOffKeys(position, k1, k2) then
            if k1 then
                SetBinding(k1, nil)
            end
            if k2 then
                SetBinding(k2, nil)
            end
        end
        MenuTable(ownerFrame).keyShare = nil
        MenuTable(position).keyShare = ownerFrame
        if k1 or k2 then
            SaveBindings(GetCurrentBindingSet())
        end
        CludesUI.Print(
            CludesUI.COLOR_CODES.BRAND
                .. "Action Wheel:|r "
                .. CludesUI.Lf(
                    "%1$s now shares %2$s with %3$s.",
                    MenuName(position),
                    GetBindingText(keyChord) or keyChord,
                    MenuName(ownerFrame)
                )
        )
        RedrawPage()
    end

    -- An Assign to Spec change can let menus that share a key load together:
    -- each such share is broken, its menu left unbound, and said so in chat.
    -- Returns true when it broke one.
    local function CheckShares()
        local broke = false
        for ownerFrame = 1, MenuCount() do
            local kept = {}
            for _, sv in ipairs(Sharers(ownerFrame)) do
                local success = mod.PalettesExclusive(sv, ownerFrame)
                for _, k in ipairs(kept) do
                    if success and not mod.PalettesExclusive(sv, k) then
                        success = false
                    end
                end
                if success then
                    kept[#kept + 1] = sv
                else
                    MenuTable(sv).keyShare = nil
                    broke = true
                    CludesUI.Print(
                        CludesUI.COLOR_CODES.BRAND
                            .. "Action Wheel:|r "
                            .. CludesUI.Lf(
                                "%1$s no longer shares the key of %2$s: they can now load in the same spec.",
                                MenuName(sv),
                                MenuName(ownerFrame)
                            )
                    )
                end
            end
        end
        return broke
    end

    -- Both halves of a commit, past the point of asking. Split out so the
    -- confirmation below can defer exactly this and nothing else. stolenFrom is
    -- the action the chord was taken from, for the record it leaves in chat --
    -- which is what the no-dialog fallback below relies on, and is still worth
    -- having once the dialog has been agreed to.
    local function ApplyKey(pmenu, keyChord, stolenFrom)
        local bindAction = BINDING_PREFIX .. pmenu
        local oldK1, oldK2 = GetBindingKey(bindAction)

        if keyChord then
            -- Bound first, so a key that cannot be bound changes nothing, the
            -- shares included. Then the PRIMARY key is replaced and a secondary
            -- binding left alone: Blizzard's own panel allows two keys per
            -- action, and clearing both silently destroyed the second one with
            -- no message (and no way to see it, since the label shows key1).
            -- Uninstall CUI hands the key back to what it did before.
            CludesUI.NoteBinding(keyChord, GetBindingAction(keyChord))
            if not SetBinding(keyChord, bindAction) then
                Complain("Action Wheel: " .. (GetBindingText(keyChord) or keyChord) .. " could not be bound.")
            else
                -- A key of its own ends a share; a primary that menus share
                -- stays with them, else it is let go.
                MenuTable(pmenu).keyShare = nil
                if oldK1 and oldK1 ~= keyChord and not HandOffKeys(pmenu, oldK1, nil) then
                    SetBinding(oldK1, nil)
                end
                if stolenFrom then
                    -- The menus that shared the key lose it with its holder
                    local holderFrame = PaletteOfAction(stolenFrom)
                    local nameList = holderFrame and SharerNames(holderFrame)
                    CludesUI.Print(
                        CludesUI.COLOR_CODES.BRAND
                            .. "Action Wheel:|r took "
                            .. (GetBindingText(keyChord) or keyChord)
                            .. " from |cffffd100"
                            .. BindingLabel(stolenFrom)
                            .. "|r"
                            .. (nameList and (" (" .. CludesUI.Lf("and %1$s, which shared it", nameList) .. ")") or "")
                            .. "."
                    )
                end
            end
        else
            -- A key of its own (or none) ends a share.
            MenuTable(pmenu).keyShare = nil
            -- Unbind: this one clears every key the palette holds, which is what
            -- "unbind" means; keys menus share stay with them.
            if not HandOffKeys(pmenu, oldK1, oldK2) then
                if oldK1 then
                    SetBinding(oldK1, nil)
                end
                if oldK2 then
                    SetBinding(oldK2, nil)
                end
            end
        end

        SaveBindings(GetCurrentBindingSet())
        RedrawPage()
    end

    -- chord = a binding string to assign, or nil to leave the palette unbound.
    -- The button has already put the bound key back on its own label by the
    -- time this runs, so the rejection paths below leave nothing to restore.
    local function CommitKey(pmenu, keyChord)
        -- SaveBindings raises "can't be done in combat" and SetBinding would
        -- then be half-applied, so nothing is touched until combat drops.
        if InCombatLockdown() then
            Complain("Action Wheel: keybinds can't be changed in combat.")
            return
        end

        local bindAction = BINDING_PREFIX .. pmenu
        -- Only a real theft is worth either a dialog or a notice: an unbound
        -- chord takes nothing, and rebinding a palette to the key it already
        -- holds takes it from itself. A key held by ANOTHER palette of ours
        -- does count -- that one would be left with no way to open at all.
        local stolenFrom = keyChord and GetBindingAction(keyChord) or nil
        if stolenFrom == "" or stolenFrom == bindAction then
            stolenFrom = nil
        end

        -- A key another menu holds is shared rather than taken when the two
        -- can never load in the same spec (Assign to Spec).
        local holderFrame = stolenFrom and PaletteOfAction(stolenFrom)
        if holderFrame and CanShareWith(pmenu, holderFrame) then
            ShareKey(pmenu, holderFrame, keyChord)
            return
        end

        -- SetBinding takes a key from whatever holds it without a word, and the
        -- displaced binding is often something the user cares about and will
        -- not miss until they reach for it mid-fight. Asking first is the only
        -- point at which they can still say no -- a message after the fact
        -- tells them what to go and put back, which is not the same thing.
        if stolenFrom and CludesUI.ShowConfirmPopup then
            local keyText = GetBindingText(keyChord) or keyChord
            local message = CludesUI.Lf(
                '%1$s is bound to "%2$s". Binding it to "%3$s" will leave that unbound.',
                keyText,
                BindingLabel(stolenFrom),
                BindingLabel(bindAction)
            )
            -- Another menu: the menus sharing its key lose it too, and the way
            -- to keep the key on both.
            if holderFrame then
                local nameList, total = SharerNames(holderFrame)
                if nameList then
                    message = message
                        .. "\n\n"
                        .. (
                            total == 1 and CludesUI.Lf("%1$s shares it and will lose it too.", nameList)
                            or CludesUI.Lf("%1$s share it and will lose it too.", nameList)
                        )
                end
                message = message
                    .. "\n\n"
                    .. CludesUI.L(
                        "Two action menus can share a keybind when Assign to Spec keeps them from ever loading in the same spec."
                    )
            end
            CludesUI:ShowConfirmPopup({
                title = "Key Already Bound",
                message = message,
                confirmText = "Rebind",
                cancelText = "Keep",
                -- Re-checked rather than trusted: the dialog sits open for as
                -- long as the user leaves it, and a fight can start under it.
                onConfirm = function()
                    if InCombatLockdown() then
                        Complain("Action Wheel: keybinds can't be changed in combat.")
                        RedrawPage()
                        return
                    end
                    ApplyKey(pmenu, keyChord, stolenFrom)
                end,
            })
            return
        end

        ApplyKey(pmenu, keyChord, stolenFrom)
    end

    -- Keys can also change from Blizzard's Keybindings page or another addon.
    -- The label is built from GetBindingKey, so without this the cached page
    -- keeps showing the old key -- which would make the "one source of truth"
    -- design only half-true in practice.
    --
    -- Signature-guarded, and that guard is not an optimisation: UPDATE_BINDINGS
    -- fires on every override-binding registration anywhere in the suite (the
    -- palette's own UpdateBindings included), and dropping the whole options
    -- page cache on each of those would rebuild the visible page over and
    -- over. Only a change to one of OUR keys is of any interest here.
    --
    -- The watcher serves the page's keybind rows and nothing else, so it is
    -- created the first time the page is built rather than at login: a session
    -- that never opens this page pays no frame and no event.
    local keysSeen = nil
    local keyWatch = nil
    local function PaletteKeySignature()
        local parts = {}
        for i = 1, MAX_PALETTES do
            local k1, k2 = GetBindingKey(BINDING_PREFIX .. i)
            parts[i] = (k1 or "") .. "/" .. (k2 or "")
        end
        return "|" .. table.concat(parts, "|")
    end

    local function EnsureBindWatcher()
        if keyWatch then
            return
        end
        keysSeen = PaletteKeySignature()
        keyWatch = CreateFrame("Frame")
        keyWatch:RegisterEvent("UPDATE_BINDINGS")
        keyWatch:SetScript("OnEvent", function()
            local now = PaletteKeySignature()
            if now ~= keysSeen then
                keysSeen = now
                CludesUI:InvalidatePageCache()
                if CludesUI:IsShown() and CludesUI.RefreshPage then
                    CludesUI:RefreshPage(true)
                end
            end
        end)
    end

    ---------------------------------------------------------------------------
    --  Palette preview
    --
    --  The live palette's own renderer (ns.CreatePaletteView), scaled down to fit the
    --  panel and made interactive: drop an action on the trailing "+" to append
    --  it, drag icons between entries to reorder, right-click to remove. Because
    --  it is the same renderer, the arrangement here is literally the one the
    --  user steers at in play.
    --
    --  Cached, not rebuilt. BuildPage runs on every RedrawPage and WoW frames
    --  are never collected, so re-creating thirteen of them per rebuild would
    --  leak. The page WRAPPER is discarded on rebuild though, so the block is
    --  re-parented and re-anchored on every build.
    ---------------------------------------------------------------------------
    local PREVIEW_H = 280 -- height the block claims in the page layout
    -- Largest radius + iconSize the block can hold. Half of PREVIEW_H less a
    -- margin: the preview turns slot labels off, so the palette only has to clear
    -- the block's own edges rather than leave room for captions under it.
    local PREVIEW_SPAN = 124
    local previewHost, previewWheel

    -- Half-extent the block can give a layout on one axis. The block is as wide
    -- as the panel's content and only PREVIEW_H tall, so the two budgets differ
    -- by a wide margin and every layout has to be measured against both.
    local function BlockSpan(vertical)
        if vertical then
            return PREVIEW_H * 0.5 - 24
        end
        local wid = previewHost and previewHost:GetWidth() or 0
        -- The block is anchored on both sides, so its width is unresolved on
        -- the very first build. Layout re-runs on every Refresh, so a fallback
        -- here corrects itself rather than sticking.
        if wid < 100 then
            wid = 460
        end
        return wid * 0.5 - 24
    end

    -- How far the preview may magnify a layout that does not fill the block on
    -- its own. Fitting used to be a shrink-only rule, which left a short strip
    -- or a small grid as a row of thumbnails in the middle of a 280px block
    -- while the arc -- whose radius alone nearly fills it -- previewed at very
    -- nearly its real size. Growing is capped at REAL size, never past it:
    -- the fit below only ever shrinks a palette into the block, and a short
    -- strip drawn larger than the user actually steers at would misrepresent
    -- the one thing the preview exists to show.
    local PREVIEW_MAX_ZOOM = 1.0

    -- How many entries the preview will actually place, which is what the fit
    -- has to be measured over. The trailing "+" counts only while the palette
    -- has room for another action -- the view stops drawing it at MAX_SLOTS
    -- (see the shownCount it works out in Layout) -- and counting it anyway
    -- fitted a full palette for one entry more than it shows, which drew it
    -- smaller than the block allows.
    local function PreviewEntryCount(pmenu)
        local num = pmenu and #pmenu.slots or 0
        if num < MAX_SLOTS then
            num = num + 1
        end
        return num
    end

    -- Fit to the block, don't crop: the live radius reaches 220, which is wider
    -- than the panel, and a two-entry strip is far narrower than it. Scaling
    -- radius, icon and dead zone by one factor keeps the proportions the user
    -- chose, so a tight arc still previews as a tight one.
    local function PreviewGeom()
        local radius = MenuGet("radius") or 100
        local iconSize = MenuGet("iconSize") or 40
        -- Fixed, not a setting: the module hardcodes the dead zone (see
        -- DefaultGeom). Still scaled by the fit below like the rest.
        local deadZone = 24
        local layout = MenuGet("layout") or "ARC"
        -- No selection zoom (hardcoded off in the module), so the fit
        -- budgets no growth headroom.
        local zoom = 1
        local k
        if layout == "GRID" then
            -- The grid is bounded on BOTH axes, so both budgets have to be met:
            -- the block's width across the columns, and its height down the rows.
            local pmenu = MenuTable(editingMenu)
            local num = PreviewEntryCount(pmenu)
            local cols, rowList
            if previewWheel then
                cols, rowList = previewWheel:GridDims()
            end
            -- The view answers from its last Layout, so it has nothing to say
            -- until the first one has run.
            if not cols or rowList < 1 then
                cols = math.min(MenuGet("gridColumns") or 4, num)
                rowList = math.ceil(num / cols)
            end
            local pitch = iconSize + (MenuGet("fanGap") or 10)
            k = math.min(
                PREVIEW_MAX_ZOOM,
                BlockSpan(false) / (cols * pitch * 0.5 + iconSize * (zoom - 1) * 0.5),
                BlockSpan(true) / (rowList * pitch * 0.5 + iconSize * (zoom - 1) * 0.5)
            )
        elseif layout ~= "ARC" then
            -- A fan's extent is the length of the strip rather than a radius,
            -- so that is what has to be fitted. The preview windows exactly
            -- like play now -- the centre plus the window each way (Visible
            -- Icons), the wheel scrolling the rest into view -- so the fit is
            -- measured over the drawn window, not the whole palette. The "+"
            -- sits off the strip's own line and costs the length nothing.
            local pmenu = MenuTable(editingMenu)
            local nReal = pmenu and #pmenu.slots or 0
            local window = MenuGet("fanVisible") or 2
            local drawn = math.min(math.max(nReal, 1), window * 2 + 1)
            -- Through the module rather than off the key: with the falloff
            -- switched off the strip spreads out to full pitch, and a fit
            -- measured at the stored decay would run it out of the block.
            -- One branch only -- a fan is always wheel-steered now.
            local reach =
                mod.FanReach(drawn, iconSize, MenuGet("fanGap") or 10, (mod.FalloffRatios(editingMenu)))
            local vertical = MenuGet("fanOrientation") == "VERTICAL"
            -- Both axes, not just the one the strip runs along: a short strip
            -- fits its own length several times over, and without the crossways
            -- budget it would grow until the icons ran out of the block.
            k = math.min(
                PREVIEW_MAX_ZOOM,
                BlockSpan(vertical) / reach,
                BlockSpan(not vertical) / (iconSize * 0.5 * zoom)
            )
        else
            -- A CONSTANT miniaturisation, not a fit to the current radius:
            -- the arc previews at a flat 75% of live size, so moving Distance
            -- from Center slides the ring in and out of the block exactly as
            -- it does in play and the icons never change size. Past a radius
            -- of roughly 140 the ring outgrows the block and draws past its
            -- edges -- the accepted price of the fixed scale.
            k = 0.75
        end
        return radius * k, iconSize * k, deadZone * k
    end

    -- Manual drag, threshold-based -- the same shape as the Widgets reorder row
    -- (CludesUI_Widgets.lua:5391), because WoW's built-in RegisterForDrag
    -- threshold is far too large for icons this size.
    local DRAG_THRESHOLD = 4
    local dragFrom, dragStartX, dragStartY, dragging, dragTarget

    -- One escape-coded string, not tooltip lines: the panel helper takes a
    -- single block of text, so the caption and the hints carry their own color
    -- codes. Gray for what the entry IS, blue for what the mouse can do to it.
    local function PreviewTooltip(wdg)
        local pmenu = MenuTable(editingMenu)
        local ent = pmenu and pmenu.slots[wdg.index]
        local textValue
        if ent then
            local _, nm = mod.SlotDisplay(ent)
            local caption
            if ent.kind == "palette" then
                -- Capped at what the palette being edited can seat, which is
                -- the whole nested menu everywhere but the halo -- eight fixed
                -- positions round a cell, and no ninth to put a child in. See
                -- NestChildCap.
                local cap = mod.NestChildCap and mod.NestChildCap(editingMenu)
                local childFrame = mod.ChildIndex(ent)
                local kids = mod.ChildSlots and mod.ChildSlots(childFrame, cap)
                caption = (kids and #kids == 1) and CludesUI.Lf("nested action menu, %1$d entry", 1)
                    or CludesUI.Lf("nested action menu, %1$d entries", kids and #kids or 0)
                -- Said where the user meets it, rather than left to be
                -- discovered by counting the entries that turned up: a menu
                -- holding more than the halo can show looks broken otherwise.
                local all = mod.ChildSlots and mod.ChildSlots(childFrame, MAX_SLOTS)
                if all and kids and #all > #kids then
                    -- The literal stays on the Lf line: the locale extractor
                    -- reads one line at a time, and a string wrapped onto the
                    -- next one is a key it never learns about.
                    caption = caption .. CludesUI.Lf(", %1$d not shown in this layout", #all - #kids)
                end
            else
                -- The stored kind strings are one word each; only the marker
                -- kinds read better with the space put back.
                caption = (ent.kind == "raidtarget" and "target marker")
                    or (ent.kind == "worldmarker" and "world marker")
                    or (ent.kind == "clearmarkers" and "target markers")
                    or (ent.kind == "cycleraidtarget" and "target marker, next on each press")
                    or (ent.kind == "cycleworldmarker" and "world marker, next on each press")
                    or (ent.kind == "randommount" and "mount")
                    or (ent.kind == "randomhearth" and "random hearthstone, rolled again on each open")
                    or (ent.kind == "panel" and "interface panel")
                    or (ent.kind == "equipmentset" and "equipment set")
                    or (ent.kind == "spec" and "specialization")
                    -- Same icon and same name as a fixed spec entry on the
                    -- character that made it, so the caption is the only place
                    -- the difference between the two can be said.
                    or (ent.kind == "dynamicspec" and "specialization, by position on this character")
                    -- Checked before the plain profession caption below,
                    -- since slot.extra would otherwise still match it.
                    or (ent.kind == "dynamicprofession" and ent.specialization and "profession specialization ability, by position on this character")
                    or (ent.kind == "dynamicprofession" and ent.extra and "profession's second ability, by position on this character")
                    -- Same icon and same name as a fixed profession entry on
                    -- the character that made it, just as with dynamicspec.
                    or (ent.kind == "dynamicprofession" and "profession, by position on this character")
                    -- The name above is already the spell this character would
                    -- cast, so the caption says what picked it rather than
                    -- repeating it.
                    or (ent.kind == "dynamicrez" and "resurrection, chosen for this character")
                    or ent.kind
            end
            textValue = CludesUI.L(nm or ent.kind)
                .. "\n|cff999999"
                .. CludesUI.L(caption)
                .. "|r"
                .. CludesUI.L(
                    "\n|cff66ccffDrag to reorder."
                        .. "\nRight-click to change action."
                        .. "\nMiddle-click to remove."
                        .. "\nDrop an action here to replace it.|r"
                )
        else
            textValue = CludesUI.L(
                "Add an action"
                    .. "\n|cff66ccffLeft-click to pick an action from a list."
                    .. "\nYou can also drop an action from the cursor here.|r"
            )
        end
        CludesUI.ShowWidgetTooltip(wdg, textValue)
    end

    local function HidePreviewTooltip()
        CludesUI.HideWidgetTooltip()
    end

    -- Place whatever is on the cursor. An empty cursor is not an error: a bare
    -- left-click on a slot should do nothing at all, cursor untouched.
    local function PreviewPlace(wdg)
        local pmenu = MenuTable(editingMenu)
        local ent = pmenu and mod.SlotFromCursor()
        if not ent then
            return
        end
        if wdg.isPlaceholder then
            if not mod.AddSlot(pmenu, ent) then
                return
            end
        else
            pmenu.slots[wdg.index] = ent
        end
        ClearCursor()
        Reapply()
    end

    ---------------------------------------------------------------------------
    --  Action picker
    --
    --  Left-clicking the "+" entry with an empty cursor opens a category menu,
    --  then that category's actions; choosing one appends a slot to the palette
    --  being edited. Dropping an action from the cursor still works, but it
    --  cannot be the only route: opening the spellbook closes the options
    --  window, so there is no way to get a spell onto the cursor while the
    --  preview is on screen.
    --
    --  Shaped after the Cooldown Manager's bar-glow spell picker
    --  (CUI_CooldownManager_Options.lua:518): one cached anchored menu on
    --  FULLSCREEN_DIALOG, the dropdown palette, pooled rows inside a capped
    --  scroll frame, dismissed by a click outside itself.
    ---------------------------------------------------------------------------
    local PICK_W = 250
    local PICK_ROW_H = 26
    local PICK_MAX_LIST = 286 -- visible list height; a longer list scrolls
    local PICK_HEAD_H = 24 -- title strip
    local PICK_NAV_H = 56 -- back row + search box, category views only
    local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

    -- pickerReplaceIndex: set while the picker was opened by a right-click on
    -- an existing entry -- the pick then replaces that slot instead of
    -- appending. nil on the "+" path.
    local pickerMenu, pickerAnchor, pickerReplaceIndex

    -- Category key -> entry array, built on first use of that category and kept.
    -- The spell and mount lists run to hundreds of rows, so the search box
    -- filters this cache instead of re-enumerating on every keystroke.
    local pickerLists = {}

    ---------------------------------------------------------------------------
    --  Enumeration
    --
    --  Strictly read-only, every list. The journals' filter setters
    --  (C_MountJournal.SetSearch/SetCollectedFilterSetting,
    --  C_ToyBox.SetFilterString, C_PetJournal.SetSearchFilter, ...) rewrite the
    --  user's saved Collections filters as a side effect and several are
    --  protected, so the filtering happens in Lua here. That is also why the
    --  ID-based getters are preferred: the index-based ones walk the journals'
    --  currently FILTERED lists, so what the palette offers would otherwise
    --  depend on what the user last typed in the Collections search box.
    ---------------------------------------------------------------------------
    local function SpellEntries()
        local result, seen = {}, {}
        local bank = Enum.SpellBookSpellBank.Player
        -- WoW Forever: names that have lower ranks, and each spell's top rank.
        local ranked, tops = {}, {}

        local function Add(spellId, nm, glyph, rankText)
            local key = rankText and ("#" .. tostring(spellId)) or spellId
            if type(spellId) ~= "number" or seen[key] or not nm then
                return
            end
            seen[key] = true
            local record = { icon = glyph, name = nm, slot = { kind = "spell", id = spellId } }
            -- A rank row casts exactly that rank, and sorts below its spell's
            -- own row (sortName, rankNum: see the picker's sort).
            if rankText then
                record.name = nm .. " (" .. rankText .. ")"
                record.sortName, record.rankNum = nm, tonumber(rankText:match("%d+")) or 0
                record.slot.rankPinned = true
            end
            result[#result + 1] = record
        end

        -- Dynamic Rez ahead of the spellbook itself, the way the Mount Journal's
        -- random roll leads the mounts: it is one entry that is whichever
        -- resurrection spell the character holding the palette has, so a palette
        -- shared between characters carries the rez once instead of once per
        -- class with all but one of them dead. pin is what holds it at the top
        -- past the sort. Left out entirely for a class with no rez at all.
        if mod.HasRezKit and mod.HasRezKit() then
            local ent = { kind = "dynamicrez" }
            local glyph = mod.SlotDisplay(ent)
            -- Named for what the ENTRY is, not for the spell it happens to
            -- resolve to today: this row is picked from a list, and "Rebirth"
            -- sitting above the real Rebirth would read as a duplicate.
            result[1] = { icon = glyph, name = "Dynamic Rez", slot = ent, pin = true }
        end

        -- There is no C_SpellBook.GetNumSpellBookItems in this client. The book
        -- is described by its skill lines instead, each carrying an offset into
        -- the item indices and a count -- which is how Blizzard's own spellbook
        -- walks it (Blizzard_SpellBookCategory.lua:180-218).
        for line = 1, (C_SpellBook.GetNumSpellBookSkillLines() or 0) do
            local li = C_SpellBook.GetSpellBookSkillLineInfo(line)
            -- offSpecID is set on the other specialisation's tabs; those spells
            -- are listed in the book but cannot be cast.
            if li and not li.shouldHide and not li.offSpecID then
                for i = li.itemIndexOffset + 1, li.itemIndexOffset + li.numSpellBookItems do
                    local details = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    -- FutureSpell (a rank not learned yet) falls out here too:
                    -- only Spell and Flyout are handled. On WoW Forever the book
                    -- holds every learned rank: the spell's own row follows the
                    -- highest known rank, and each rank also gets a row that
                    -- casts exactly that rank.
                    if details and not details.isPassive and not details.isOffSpec then
                        if details.itemType == Enum.SpellBookItemType.Spell then
                            local rankText
                            if CludesUI.IS_FOREVER then
                                rankText = details.subName
                                if not rankText or rankText == "" then
                                    rankText = C_Spell.GetSpellSubtext(details.actionID)
                                end
                                if rankText == "" then
                                    rankText = nil
                                end
                            end
                            -- actionID, not spellID: for a spell actionID is the
                            -- BASE id while spellID is whatever override is up
                            -- right now, and the base is what the game resolves
                            -- overrides from when the button fires. A lower rank
                            -- whose text has not loaded would only repeat its
                            -- spell's row.
                            if CludesUI.IS_FOREVER and C_SpellBook.IsSpellBookItemLowRank(i, bank) then
                                if rankText then
                                    Add(details.actionID, details.name, details.iconID, rankText)
                                    ranked[details.name] = true
                                end
                            else
                                Add(details.actionID, details.name, details.iconID)
                                if rankText then
                                    tops[#tops + 1] =
                                        { details.actionID, details.name, details.iconID, rankText }
                                end
                            end
                        elseif details.itemType == Enum.SpellBookItemType.Flyout then
                            -- A flyout is not castable itself, so its known
                            -- slots are offered as individual spells.
                            local numSlots = select(3, GetFlyoutInfo(details.actionID))
                            for sv = 1, (numSlots or 0) do
                                local spellId, _, isKnown, spellName = GetFlyoutSlotInfo(details.actionID, sv)
                                if isKnown then
                                    -- One icon only: the second return would land in rankText.
                                    Add(spellId, spellName, (C_Spell.GetSpellTexture(spellId)))
                                end
                            end
                        end
                    end
                end
            end
        end
        -- The top rank of a spell with lower ones gets its own rank row too.
        for _, t in ipairs(tops) do
            if ranked[t[2]] then
                Add(t[1], t[2], t[3], t[4])
            end
        end
        return result
    end

    -- The words a collection entry can be searched by besides its own name,
    -- lowercase and space separated, matched by the same plain substring find
    -- the name gets -- so "vend" finds a vendor mount the way "sea" finds a
    -- seahorse.
    --
    -- The source label is the client's own BATTLE_PET_SOURCE_n string, which is
    -- what the Mount Journal and the Toy Box label their own source filters
    -- with, so a localized client searches in its own words. Nothing is
    -- invented here: only what the collection API actually hands back is
    -- indexed.
    local function SourceKeywords(sourceType, isFavorite)
        local result = isFavorite and (CludesUI.L("favorite"):lower() .. " ") or ""
        local labelText = sourceType and _G["BATTLE_PET_SOURCE_" .. sourceType]
        if labelText then
            result = result .. labelText:lower()
        end
        return result ~= "" and result or nil
    end

    local function MountEntries()
        local result = {}
        -- The roll the Mount Journal's own button makes, offered ahead of the
        -- collection itself: it is the entry most palettes want, and hunting
        -- for it among several hundred mounts sorted by name is not a search
        -- anyone can make. pin is what holds it there past the sort.
        do
            local ent = { kind = "randommount" }
            local glyph, nm = mod.SlotDisplay(ent)
            result[1] = { icon = glyph, name = nm, slot = ent, pin = true }
        end
        -- Beside it, and pinned for the same reason: an entry that summons
        -- whatever the player rode last. Its target changes on its own, so it
        -- is a kind rather than a mount -- there is nothing here to pick.
        do
            local ent = { kind = "lastmount" }
            local glyph = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = "Last Used Mount", slot = ent, pin = true }
        end
        for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
            local nm, spellId, glyph, _, _, sourceType, isFavorite, _, _, hideOnChar, isCollected =
                C_MountJournal.GetMountInfoByID(mountID)
            -- isUsable is deliberately not read here. It moves with where the
            -- player stands -- the Mount Journal rebuilds its list on
            -- MOUNT_JOURNAL_USABILITY_CHANGED -- so filtering on it hides an
            -- aquatic mount from anyone picking on dry ground. Whether a mount
            -- can be summoned is a run-time question, not a pick-time one.
            if nm and isCollected and not hideOnChar then
                result[#result + 1] = {
                    icon = glyph,
                    name = nm,
                    -- Where it came from, and whether it is a favorite, so both
                    -- are things the search box can be asked for.
                    keywords = SourceKeywords(sourceType, isFavorite),
                    -- spellID is banked at pickup time because ResolveAction
                    -- needs the summon spell and it is already in hand here.
                    slot = { kind = "mount", id = mountID, spellID = spellId, name = nm },
                }
            end
        end
        return result
    end

    local function ItemEntries()
        local result, seen = {}, {}
        local function ScanBag(bag)
            for ent = 1, C_Container.GetContainerNumSlots(bag) do
                local details = C_Container.GetContainerItemInfo(bag, ent)
                local itemId = details and details.itemID
                -- Only items with a use effect. The palette fires "/use item:<id>",
                -- so an item without one is a slot that can never do anything.
                if itemId and not seen[itemId] and details.itemName and C_Item.GetItemSpell(itemId) then
                    seen[itemId] = true
                    result[#result + 1] = {
                        icon = details.iconFileID,
                        name = details.itemName,
                        slot = { kind = "item", id = itemId, name = details.itemName },
                    }
                end
            end
        end
        for bag = Enum.BagIndex.Backpack, NUM_BAG_SLOTS do
            ScanBag(bag)
        end
        -- The reagent bag is outside that range and easy to forget, but it is
        -- where a lot of players keep their potions and phials -- exactly the
        -- items someone puts on a palette.
        ScanBag(Enum.BagIndex.ReagentBag)
        return result
    end

    -- The toy box has no ID-based enumeration, only a walk over the list the
    -- Collections filters leave standing, so the picker used to show whatever
    -- the player last set there -- with "Not Collected" ticked it came up
    -- empty, which reads as a broken picker rather than as a filter. So the
    -- filters are widened for the length of the walk and every one of them is
    -- put back afterwards. Restoring is the whole cost of this: the scan runs
    -- inside pcall so an error still hands the player their own filters back.
    local function ScanToysUnfiltered(scan)
        local TB = C_ToyBox
        -- The three show switches as { read, write, value for the walk }.
        -- Uncollected toys are left out rather than widened in: PlayerHasToy
        -- turns them away anyway, so showing them would only lengthen the walk.
        local switches = {
            { TB.GetCollectedShown, TB.SetCollectedShown, true },
            { TB.GetUncollectedShown, TB.SetUncollectedShown, false },
            { TB.GetUnusableShown, TB.SetUnusableShown, true },
        }
        for _, sw in ipairs(switches) do
            sw.was = sw[1]()
        end
        local sourceCount = C_PetJournal.GetNumPetSources()
        local sourceWas = {}
        for i = 1, sourceCount do
            sourceWas[i] = TB.IsSourceTypeFilterChecked(i)
        end
        local expansionCount = GetNumExpansions()
        local expansionWas = {}
        for i = 1, expansionCount do
            expansionWas[i] = TB.IsExpansionTypeFilterChecked(i)
        end
        -- The search text has no getter. It can only have come from the Toy
        -- Box's own box, which keeps it here, and it is gone after a reload,
        -- so when it is absent an empty string is the right thing to put back.
        local typed = (ToyBox and ToyBox.searchString) or ""

        for _, sw in ipairs(switches) do
            sw[2](sw[3])
        end
        TB.SetAllSourceTypeFilters(true)
        TB.SetAllExpansionTypeFilters(true)
        TB.SetFilterString("")
        TB.ForceToyRefilter()

        local success, err = pcall(scan)

        for _, sw in ipairs(switches) do
            sw[2](sw.was)
        end
        for i = 1, sourceCount do
            TB.SetSourceTypeFilter(i, sourceWas[i])
        end
        for i = 1, expansionCount do
            TB.SetExpansionTypeFilter(i, expansionWas[i])
        end
        TB.SetFilterString(typed)
        TB.ForceToyRefilter()
        -- An open Toy Box drew its page from the widened list: have it draw
        -- again with the same pair its own filter menu calls.
        if ToyBox and ToyBox:IsVisible() then
            for _, redraw in ipairs({ "ToyBox_UpdatePages", "ToyBox_UpdateButtons" }) do
                local fn = _G[redraw]
                if fn then
                    fn()
                end
            end
        end

        if not success then
            error(err, 0)
        end
    end

    local function ToyEntries()
        local result = {}
        -- A different owned hearthstone on every open, pinned ahead of the
        -- collection the way the random mount leads the mounts. Named for what
        -- the ENTRY is rather than for the toy it happens to draw right now.
        do
            local ent = { kind = "randomhearth" }
            local glyph = mod.SlotDisplay(ent)
            result[1] = { icon = glyph, name = "Random Hearthstone", slot = ent, pin = true }
        end
        ScanToysUnfiltered(function()
            for i = 1, (C_ToyBox.GetNumFilteredToys() or 0) do
                local itemId = C_ToyBox.GetToyFromIndex(i)
                if itemId and itemId > 0 and PlayerHasToy(itemId) then
                    local _, nm, glyph, isFavorite = C_ToyBox.GetToyInfo(itemId)
                    if nm then
                        -- Favorite only: the toy API hands back no source for
                        -- an individual toy, and a source guessed from anywhere
                        -- else would be a made-up answer in a search box.
                        result[#result + 1] = {
                            icon = glyph,
                            name = nm,
                            keywords = SourceKeywords(nil, isFavorite),
                            slot = { kind = "toy", id = itemId, name = nm },
                        }
                    end
                end
            end
        end)
        return result
    end

    local function MacroEntries()
        local result = {}
        local numAccount, numChar = GetNumMacros()
        -- Two separate blocks: the per-character macros start at a fixed offset
        -- rather than continuing from the account ones
        -- (Blizzard_MacroUI.lua:155).
        local function AddBlock(first, total)
            for i = first, first + (total or 0) - 1 do
                local nm, glyph = GetMacroInfo(i)
                if nm then
                    -- Stored by name, matching SlotFromCursor: the index moves
                    -- when the macro list is reordered, the name does not.
                    result[#result + 1] = { icon = glyph, name = nm, slot = { kind = "macro", name = nm } }
                end
            end
        end
        AddBlock(1, numAccount)
        AddBlock(Constants.MacroConsts.MAX_ACCOUNT_MACROS + 1, numChar)
        return result
    end

    local function PetEntries()
        local result = {}
        for _, unitGuid in ipairs(C_PetJournal.GetOwnedPetIDs()) do
            local details = C_PetJournal.GetPetInfoTableByPetID(unitGuid)
            local nm = details and (details.customName or details.name)
            if nm then
                result[#result + 1] = {
                    icon = details.icon,
                    name = nm,
                    slot = { kind = "battlepet", guid = unitGuid, name = nm },
                }
            end
        end
        return result
    end

    -- This character's own specializations, in the order the game lists them.
    -- The slot banks the specID rather than the index -- the module resolves
    -- the index back at fire time, so the same palette carried to an alt
    -- points at nothing instead of at somebody else's spec.
    local function SpecEntries()
        local result = {}
        local classID = select(3, UnitClass("player"))
        if not classID or not C_SpecializationInfo then
            return result
        end
        for i = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0) do
            local specID, nm, _, glyph = C_SpecializationInfo.GetSpecializationInfo(i)
            if specID and nm then
                result[#result + 1] = {
                    icon = glyph,
                    name = nm,
                    slot = { kind = "spec", specID = specID, name = nm },
                }
            end
        end
        return result
    end

    -- The most specializations any class has -- four, the druid's alone.
    -- Walked rather than written down so a class that gains a fourth is picked
    -- up without a code change.
    local function MaxSpecCount()
        if not C_SpecializationInfo or not GetNumClasses then
            return 0
        end
        local most = 0
        for classID = 1, GetNumClasses() do
            local num = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
            if num > most then
                most = num
            end
        end
        return most
    end

    -- The same list by POSITION rather than by identity, offered beside the
    -- fixed entries rather than instead of them: "go Restoration" is not "go
    -- to the third one", and only the second survives being carried to
    -- another class.
    --
    -- Every position ANY class has, not only this character's -- a paladin
    -- offered three could not put a druid's fourth on a palette built FOR the
    -- druid. The usability filter hides the extras until an alt has them.
    local function DynamicSpecEntries()
        local result = {}
        -- Named by the module that also RESOLVES the kind, so an older
        -- CludesUIQuickdraw beside a newer options page offers nothing
        -- rather than a kind that module could not fire.
        if not mod.SpecPositionName then
            return result
        end
        for i = 1, MaxSpecCount() do
            local ent = { kind = "dynamicspec", index = i }
            local glyph = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = mod.SpecPositionName(i), slot = ent }
        end
        return result
    end

    -- Both lists, fixed first: naming a spec is what a player picking one on
    -- their main usually means, and the by-position block reads as the
    -- alternative to it rather than as the lead.
    local function AllSpecEntries()
        local result = SpecEntries()
        for _, record in ipairs(DynamicSpecEntries()) do
            result[#result + 1] = record
        end
        return result
    end

    -- Profession POSITIONS (DynamicSpecEntries counterpart): the five
    -- GetProfessions slots as openers, then the same five as second abilities,
    -- then the two primary slots as gathering specialization abilities (retail
    -- only: WoW Forever's professions have no specializations).
    -- Unlearned or inapplicable positions resolve to nothing and go dark under
    -- Hide Unavailable Actions (see Dynamic Profession in CludesUIQuickdraw).
    local function DynamicProfessionEntries()
        local result = {}
        if not mod.ProfessionPositionName then
            return result
        end
        for i = 1, 5 do
            local ent = { kind = "dynamicprofession", index = i }
            local glyph = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = mod.ProfessionPositionName(i), slot = ent }
        end
        for i = 1, 5 do
            local ent = { kind = "dynamicprofession", index = i, extra = true }
            local glyph = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = mod.ProfessionPositionName(i, true), slot = ent }
        end
        for i = 1, CludesUI.IS_FOREVER and 0 or 2 do
            local ent = { kind = "dynamicprofession", index = i, specialization = true }
            local glyph = mod.SlotDisplay(ent)
            result[#result + 1] = {
                icon = glyph,
                name = mod.ProfessionPositionName(i, false, true),
                slot = ent,
            }
        end
        return result
    end

    -- The markers need no enumeration at all: the slot kinds carry the icon
    -- and the name, so a candidate slot handed to SlotDisplay IS the entry.
    --
    -- One row per marker per set is twenty-one rows, and the two sets are the
    -- one thing a user has already decided between before opening the menu --
    -- so Markers holds two lists rather than one, and neither is long enough to
    -- scroll. See the subs field on its category below.
    local function MarkerAdder(result)
        return function(kind, ident, nm)
            local ent = { kind = kind, id = ident }
            local glyph, drawn = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = nm or drawn, slot = ent }
        end
    end

    -- The cyclers lead each list: one entry that steps through all eight is the
    -- reason to come here at all on a palette with no room for nine, and
    -- burying it under the eight it replaces hides it from exactly the person
    -- who wants it. Deliberately NOT in the two marker presets -- a preset that
    -- lays out all eight has nothing to cycle.
    --
    -- Each is named without the marker SlotDisplay appends. On a placed entry
    -- that suffix says which one is up next, which is the point of it; on a
    -- menu row it would read as the one marker this row places.
    local function TargetMarkerEntries()
        local result = {}
        local Add = MarkerAdder(result)
        Add("cycleraidtarget", nil, "Cycle Target Markers")
        for i = 1, 8 do
            Add("raidtarget", i)
        end
        Add("raidtarget", 0)
        -- The all-units counterpart of the /tm 0 row above; the world markers
        -- need none because their 0 row already clears them all.
        Add("clearmarkers")
        return result
    end

    local function WorldMarkerEntries()
        local result = {}
        local Add = MarkerAdder(result)
        Add("cycleworldmarker", nil, "Cycle World Markers")
        for i = 1, 8 do
            Add("worldmarker", i)
        end
        Add("worldmarker", 0)
        return result
    end

    -- The interface panels this client has, in micro-menu order. The module
    -- owns the list -- which panel is clicked how, and which of them this
    -- client even has -- so the picker only draws what it is handed. Panels
    -- missing from this build (Housing before 12.0, the Shop in a region whose
    -- client has none) never reach the list, so a row here always opens
    -- something.
    local function PanelEntries()
        local result = {}
        for _, ent in ipairs(mod.PanelSlots and mod.PanelSlots(true) or {}) do
            local glyph, nm = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = nm, slot = ent }
        end
        return result
    end

    local function OutfitEntries()
        local result = {}
        for _, ent in ipairs(mod.OutfitSlots and mod.OutfitSlots() or {}) do
            local glyph, nm = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = nm, slot = ent }
        end
        return result
    end

    local function EquipmentSetEntries()
        local result = {}
        for _, ent in ipairs(mod.EquipmentSetSlots()) do
            local glyph, nm = mod.SlotDisplay(ent)
            result[#result + 1] = { icon = glyph, name = nm, slot = ent }
        end
        return result
    end

    -- Every palette this one may open. Not a list of things the game owns, so
    -- it is rebuilt on each use rather than cached: adding a palette or filling
    -- one in has to show up here without reopening the picker.
    --
    -- ns.CanNest does the refusing, and refuses more than the obvious: a palette
    -- inside itself, and any chain that would close a loop -- A holding B
    -- holding A -- which would send every push and every draw round until the
    -- client gave out.
    local function PaletteEntries()
        local result = {}
        for i = 1, MenuCount() do
            if i ~= editingMenu and mod.CanNest and mod.CanNest(editingMenu, i) then
                local pmenu = MenuTable(i)
                local nm = (pmenu and pmenu.name) or AutoName(i)
                local total = pmenu and #pmenu.slots or 0
                result[#result + 1] = {
                    -- Same icon SlotDisplay draws it by: its first entry.
                    icon = PaletteListIcon(pmenu),
                    name = (total > 0) and (nm .. "  |cff808080(" .. total .. ")|r")
                        or (nm .. "  |cff808080(empty)|r"),
                    -- No name on the slot: SlotDisplay reads the palette's own,
                    -- so renaming the palette renames the entry that opens it.
                    slot = { kind = "palette", palette = i },
                }
            end
        end
        return result
    end

    -- custom = the typed-macro pane rather than a list of things to enumerate.
    -- subs = the row opens a second list of categories rather than a list of
    -- entries, for a category whose contents divide the way the user already
    -- has in their head before they open it.
    local PICKER_CATEGORIES = {
        -- First, above the divider the root list draws under it: nesting is
        -- the one row that is about the menus themselves rather than about
        -- something the game owns.
        { key = "palette", label = "Nest Another Action Menu", build = PaletteEntries },
        { key = "spell", label = "Spells", build = SpellEntries },
        { key = "mount", label = "Mounts", build = MountEntries, keywordHint = true },
        { key = "item", label = "Items", build = ItemEntries },
        { key = "toy", label = "Toys", build = ToyEntries, keywordHint = true },
        { key = "macro", label = "Macros", build = MacroEntries },
        { key = "battlepet", label = "Battle Pets", build = PetEntries },
        { key = "outfit", label = "Outfits", build = OutfitEntries, keepOrder = true },
        { key = "equipmentset", label = "Equipment Sets", build = EquipmentSetEntries },
        -- keepOrder on both: the markers run star to skull, the order every
        -- marker menu in the game shows. noSearch on both too -- a fixed
        -- handful of rows has nothing worth filtering, and the nav strip
        -- collapses to the Back row alone.
        {
            key = "marker",
            label = "Markers",
            subs = {
                {
                    key = "marker_target",
                    label = "Target Markers",
                    build = TargetMarkerEntries,
                    keepOrder = true,
                    noSearch = true,
                },
                {
                    key = "marker_world",
                    label = "World Markers",
                    build = WorldMarkerEntries,
                    keepOrder = true,
                    noSearch = true,
                },
            },
        },
        -- keepOrder: the game lists a class's specs in one fixed order that
        -- every character sheet shows, and alphabetising them would be the
        -- one place in the interface they are not in it. It also keeps the
        -- by-position block below the fixed one, which is the whole of how the
        -- two tell themselves apart. noSearch: at most eight rows.
        {
            key = "spec",
            label = "Specializations",
            build = AllSpecEntries,
            keepOrder = true,
            noSearch = true,
        },
        -- keepOrder: Profession 1, Profession 2, Cooking, Fishing and
        -- Archaeology (First Aid on WoW Forever) in the fixed order the game
        -- lists them, then the same five positions' second abilities.
        -- noSearch: ten rows.
        {
            key = "profession",
            label = "Professions",
            build = DynamicProfessionEntries,
            keepOrder = true,
            noSearch = true,
        },
        -- keepOrder: the panels run in the order the micro menu draws them,
        -- which is the row the player already reads left to right. noSearch:
        -- the whole interface is under twenty rows, and a search box over a
        -- list the user is scanning by ICON buys nothing.
        {
            key = "panel",
            label = "Interface Panels",
            build = PanelEntries,
            keepOrder = true,
            noSearch = true,
        },
        { key = "macrotext", label = "Custom Macro...", custom = true },
    }

    -- Which list the Back row goes home to, filled in here because a table
    -- literal cannot name itself. A category with no parent is at the root.
    for _, category in ipairs(PICKER_CATEGORIES) do
        for _, sub in ipairs(category.subs or {}) do
            sub.parent = category
        end
    end

    local ShowPickerCategories, ShowPickerCategory, ShowPickerCustom

    local function HidePicker()
        if pickerMenu then
            pickerMenu:Hide()
        end
    end

    -- Returns true when a slot was actually committed.
    local function AssignEntry(record)
        local pmenu = MenuTable(editingMenu)
        if not pmenu then
            return false
        end
        -- The stored slot is a COPY: the entry belongs to the cached list, and
        -- handing that one table to two entries would alias a single saved slot
        -- into both of them.
        local ent = {}
        for k, v in pairs(record.slot) do
            ent[k] = v
        end
        if pickerReplaceIndex then
            -- Opened by a right-click on an existing entry: the pick replaces
            -- that slot, the same direct write dropping an action on it
            -- performs (PreviewPlace). Guarded in case the slot is gone --
            -- every removal path closes the picker, but a guard is cheaper
            -- than the certainty.
            if not pmenu.slots[pickerReplaceIndex] then
                return false
            end
            pmenu.slots[pickerReplaceIndex] = ent
        elseif not mod.AddSlot(pmenu, ent) then
            -- ns.AddSlot refuses a full palette. Unreachable from here -- a
            -- full palette draws no "+" to click -- but the refusal must not
            -- fall through into a Refresh that has nothing to show.
            return false
        end
        HidePicker()
        Reapply()
        return true
    end

    local function EnsurePickerMenu()
        if pickerMenu then
            return pickerMenu
        end

        local FONT = (CludesUI.GetFontPath()) or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local bgR = CludesUI.DD_BG_R or 0.075
        local bgG = CludesUI.DD_BG_G or 0.113
        local bgB = CludesUI.DD_BG_B or 0.141
        local bgA = CludesUI.DD_BG_HA or 0.98
        local brdA = CludesUI.DD_BRD_A or 0.20
        local hlA = CludesUI.DD_ITEM_HL_A or 0.08
        local tR = CludesUI.TEXT_DIM_R or 0.7
        local tG = CludesUI.TEXT_DIM_G or 0.7
        local tB = CludesUI.TEXT_DIM_B or 0.7
        local tA = CludesUI.TEXT_DIM_A or 0.85
        local ACCENT = CludesUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }

        local dropMenu = CreateFrame("Frame", nil, UIParent)
        -- The options window is on DIALOG (CludesUI.lua:7126), so the menu
        -- has to sit a strata above it or the panel draws over it.
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(300)
        dropMenu:SetClampedToScreen(true)
        dropMenu:SetSize(PICK_W, 10)
        dropMenu:EnableMouse(true)
        dropMenu:Hide()

        local mbg = dropMenu:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints()
        mbg:SetColorTexture(bgR, bgG, bgB, bgA)
        CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, brdA, mbg, nil, true)

        dropMenu.title = CludesUI.MakeFont(dropMenu, 12, nil, 1, 1, 1, 0.9)
        dropMenu.title:SetPoint("TOP", dropMenu, "TOP", 0, -7)
        dropMenu.title:SetJustifyH("CENTER")

        dropMenu.back = CreateFrame("Button", nil, dropMenu)
        dropMenu.back:SetHeight(PICK_ROW_H)
        dropMenu.back:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -PICK_HEAD_H)
        dropMenu.back:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -PICK_HEAD_H)
        dropMenu.back:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local bHl = dropMenu.back:CreateTexture(nil, "ARTWORK")
        bHl:SetAllPoints()
        bHl:SetColorTexture(1, 1, 1, 0)
        local bAr = dropMenu.back:CreateTexture(nil, "OVERLAY")
        bAr:SetSize(12, 12)
        bAr:SetPoint("LEFT", dropMenu.back, "LEFT", 8, 0)
        bAr:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-left.png")
        bAr:SetVertexColor(tR, tG, tB, tA)
        if bAr.SetSnapToPixelGrid then
            bAr:SetSnapToPixelGrid(false)
            bAr:SetTexelSnappingBias(0)
        end
        local bTx = CludesUI.MakeFont(dropMenu.back, 11, nil, tR, tG, tB, tA)
        bTx:SetPoint("LEFT", bAr, "RIGHT", 6, 0)
        bTx:SetText(CludesUI.L("Categories"))
        -- Named, because a sub-category's entries go back to the sub-list
        -- rather than to the root and the row has to say which.
        dropMenu.backText = bTx
        dropMenu.back:SetScript("OnEnter", function()
            bHl:SetColorTexture(1, 1, 1, hlA)
            bTx:SetTextColor(1, 1, 1, 1)
            bAr:SetVertexColor(1, 1, 1, 1)
        end)
        dropMenu.back:SetScript("OnLeave", function()
            bHl:SetColorTexture(1, 1, 1, 0)
            bTx:SetTextColor(tR, tG, tB, tA)
            bAr:SetVertexColor(tR, tG, tB, tA)
        end)
        -- One step up from wherever we are: the entries of a sub-category go to
        -- its own list, everything else to the root. menu.cat is nil in both
        -- list views, so a sub-list's own Back lands at the root, which is the
        -- only place left to go.
        dropMenu.back:SetScript("OnClick", function()
            ShowPickerCategories(dropMenu.cat and dropMenu.cat.parent or nil)
        end)

        dropMenu.search = CreateFrame("EditBox", nil, dropMenu)
        dropMenu.search:SetHeight(22)
        dropMenu.search:SetPoint("TOPLEFT", dropMenu.back, "BOTTOMLEFT", 7, -4)
        dropMenu.search:SetPoint("TOPRIGHT", dropMenu.back, "BOTTOMRIGHT", -7, -4)
        dropMenu.search:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        dropMenu.search:SetFont(FONT, 11, "")
        dropMenu.search:SetTextColor(1, 1, 1, 0.9)
        dropMenu.search:SetAutoFocus(false)
        dropMenu.search:SetMaxLetters(40)
        dropMenu.search:SetTextInsets(6, 6, 0, 0)
        local sBg = dropMenu.search:CreateTexture(nil, "BACKGROUND")
        sBg:SetAllPoints()
        sBg:SetColorTexture(0, 0, 0, 0.4)
        CludesUI.MakeRoundedBorder(dropMenu.search, 1, 1, 1, 0.10, sBg)
        dropMenu.searchPH = dropMenu.search:CreateFontString(nil, "OVERLAY")
        dropMenu.searchPH:SetFont(FONT, 11, "")
        dropMenu.searchPH:SetTextColor(0.5, 0.5, 0.5, 0.6)
        dropMenu.searchPH:SetPoint("LEFT", dropMenu.search, "LEFT", 6, 0)
        dropMenu.searchPH:SetText(CludesUI.L("Search..."))
        dropMenu.search:SetScript("OnEscapePressed", function(sv)
            sv:ClearFocus()
        end)
        dropMenu.search:SetScript("OnEnterPressed", function(sv)
            sv:ClearFocus()
        end)
        dropMenu.search:SetScript("OnTextChanged", function(sv)
            dropMenu.searchPH:SetShown((sv:GetText() or "") == "")
            -- Re-filters the cached list; ShowPickerCategory never clears the box.
            if dropMenu.cat then
                ShowPickerCategory(dropMenu.cat)
            end
        end)

        dropMenu.scroll = CreateFrame("ScrollFrame", nil, dropMenu)
        dropMenu.scroll:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
        dropMenu.scroll:EnableMouseWheel(true)
        dropMenu.list = CreateFrame("Frame", nil, dropMenu.scroll)
        dropMenu.list:SetWidth(PICK_W - 2)
        dropMenu.scroll:SetScrollChild(dropMenu.list)
        -- Thin track and thumb, as on the CDM source picker
        -- (CUI_CooldownManager_Options.lua:16016): a capped 250px menu holding a
        -- few hundred mounts gives no other sign that it scrolls.
        dropMenu.track = dropMenu.scroll:CreateTexture(nil, "ARTWORK")
        dropMenu.track:SetWidth(3)
        dropMenu.track:SetColorTexture(1, 1, 1, 0.06)
        dropMenu.track:SetPoint("TOPRIGHT", dropMenu.scroll, "TOPRIGHT", -1, 0)
        dropMenu.track:SetPoint("BOTTOMRIGHT", dropMenu.scroll, "BOTTOMRIGHT", -1, 0)
        dropMenu.track:Hide()
        dropMenu.thumb = dropMenu.scroll:CreateTexture(nil, "OVERLAY")
        dropMenu.thumb:SetWidth(3)
        dropMenu.thumb:SetColorTexture(1, 1, 1, 0.25)
        dropMenu.thumb:Hide()

        -- Hairline under the root list's first row (the nest category),
        -- separating it from the game-owned categories below. Drawn on the
        -- boundary between rows 1 and 2 so the pooled rows' fixed pitch is
        -- untouched; only ShowPickerCategories' root view shows it.
        dropMenu.catDivider = dropMenu.list:CreateTexture(nil, "ARTWORK")
        dropMenu.catDivider:SetColorTexture(1, 1, 1, brdA)
        dropMenu.catDivider:SetHeight(1)
        dropMenu.catDivider:SetPoint("TOPLEFT", dropMenu.list, "TOPLEFT", 6, -PICK_ROW_H)
        dropMenu.catDivider:SetPoint("TOPRIGHT", dropMenu.list, "TOPRIGHT", -6, -PICK_ROW_H)
        dropMenu.catDivider:Hide()

        function dropMenu:UpdateThumb()
            local visH, fullH = self.scroll:GetHeight(), self.list:GetHeight()
            local maxScroll = math.max(0, fullH - visH)
            if maxScroll <= 0 then
                self.track:Hide()
                self.thumb:Hide()
                return
            end
            self.track:Show()
            self.thumb:Show()
            local thumbH = math.max(20, visH * visH / fullH)
            self.thumb:SetHeight(thumbH)
            local frac = (self.scroll:GetVerticalScroll() or 0) / maxScroll
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self.track, "TOPRIGHT", 0, -frac * (visH - thumbH))
        end

        dropMenu.scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxScroll = math.max(0, dropMenu.list:GetHeight() - self:GetHeight())
            if maxScroll <= 0 then
                return
            end
            self:SetVerticalScroll(
                math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * PICK_ROW_H * 2))
            )
            dropMenu:UpdateThumb()
        end)

        -- Pooled rows, re-labelled per view: switching category and every
        -- keystroke in the search box re-runs the populate.
        dropMenu.rows = {}
        function dropMenu:GetRow(i)
            local rw = self.rows[i]
            if rw then
                return rw
            end
            rw = CreateFrame("Button", nil, self.list)
            rw:SetHeight(PICK_ROW_H)
            rw:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -(i - 1) * PICK_ROW_H)
            rw:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -(i - 1) * PICK_ROW_H)
            rw:SetFrameLevel(self:GetFrameLevel() + 2)
            rw.hl = rw:CreateTexture(nil, "ARTWORK")
            rw.hl:SetAllPoints()
            rw.hl:SetColorTexture(1, 1, 1, 0)
            rw.icon = rw:CreateTexture(nil, "ARTWORK")
            rw.icon:SetSize(PICK_ROW_H - 6, PICK_ROW_H - 6)
            rw.icon:SetPoint("LEFT", rw, "LEFT", 6, 0)
            rw.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            rw.label = CludesUI.MakeFont(rw, 11, nil, tR, tG, tB, tA)
            rw.label:SetJustifyH("LEFT")
            rw.label:SetWordWrap(false)
            rw.label:SetMaxLines(1)
            rw:SetScript("OnEnter", function(sv)
                sv.hl:SetColorTexture(1, 1, 1, hlA)
                sv.label:SetTextColor(1, 1, 1, 1)
            end)
            rw:SetScript("OnLeave", function(sv)
                sv.hl:SetColorTexture(1, 1, 1, 0)
                sv.label:SetTextColor(tR, tG, tB, tA)
            end)
            self.rows[i] = rw
            return rw
        end

        -----------------------------------------------------------------------
        --  Custom Macro pane. Typed macro text, stored as a macrotext slot --
        --  the one kind that has nothing to enumerate.
        -----------------------------------------------------------------------
        local custom = CreateFrame("Frame", nil, dropMenu)
        custom:SetPoint("TOPLEFT", dropMenu.back, "BOTTOMLEFT", 7, -6)
        custom:SetPoint("TOPRIGHT", dropMenu.back, "BOTTOMRIGHT", -7, -6)
        custom:SetHeight(150)
        custom:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        custom:Hide()
        dropMenu.custom = custom

        local function MakeInput(hostFrame, height, multiline)
            local box = CreateFrame("EditBox", nil, hostFrame)
            box:SetHeight(height)
            box:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
            box:SetFont(FONT, 11, "")
            box:SetTextColor(1, 1, 1, 0.9)
            box:SetAutoFocus(false)
            box:SetTextInsets(5, 5, 3, 3)
            box:SetMultiLine(multiline == true)
            -- Newlines are part of a macro, so a multiline box must not treat
            -- Enter as "commit"; the Add button is the only commit.
            if not multiline then
                box:SetScript("OnEnterPressed", function(sv)
                    sv:ClearFocus()
                end)
            end
            box:SetScript("OnEscapePressed", function(sv)
                sv:ClearFocus()
            end)
            local backdrop = box:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0, 0, 0, 0.4)
            CludesUI.MakeRoundedBorder(box, 1, 1, 1, 0.10, backdrop)
            return box
        end

        local nameLbl = CludesUI.MakeFont(custom, 10, nil, tR, tG, tB, tA)
        nameLbl:SetPoint("TOPLEFT", custom, "TOPLEFT", 1, 0)
        nameLbl:SetText(CludesUI.L("Label"))
        local nameField = MakeInput(custom, 22, false)
        nameField:SetPoint("TOPLEFT", nameLbl, "BOTTOMLEFT", 0, -3)
        nameField:SetPoint("RIGHT", custom, "RIGHT", -1, 0)
        nameField:SetMaxLetters(24)

        local textLbl = CludesUI.MakeFont(custom, 10, nil, tR, tG, tB, tA)
        textLbl:SetPoint("TOPLEFT", nameField, "BOTTOMLEFT", 0, -8)
        textLbl:SetText(CludesUI.L("Macro Text"))
        local editField = MakeInput(custom, 62, true)
        editField:SetPoint("TOPLEFT", textLbl, "BOTTOMLEFT", 0, -3)
        editField:SetPoint("RIGHT", custom, "RIGHT", -1, 0)
        editField:SetMaxLetters(255)

        local plusBtn = CreateFrame("Button", nil, custom)
        plusBtn:SetSize(70, 22)
        plusBtn:SetPoint("TOPRIGHT", editField, "BOTTOMRIGHT", 0, -8)
        plusBtn:SetFrameLevel(custom:GetFrameLevel() + 1)
        local aBg = plusBtn:CreateTexture(nil, "BACKGROUND")
        aBg:SetAllPoints()
        aBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.20)
        CludesUI.MakeRoundedBorder(plusBtn, ACCENT.r, ACCENT.g, ACCENT.b, 0.7, aBg)
        local aTx = CludesUI.MakeFont(plusBtn, 11, nil, 1, 1, 1, 0.9)
        aTx:SetPoint("CENTER")
        aTx:SetText(CludesUI.L("Add"))
        plusBtn:SetScript("OnEnter", function()
            aBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.35)
        end)
        plusBtn:SetScript("OnLeave", function()
            aBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.20)
        end)
        plusBtn:SetScript("OnClick", function()
            local body = strtrim(editField:GetText() or "")
            if body == "" then
                return
            end
            local labelText = strtrim(nameField:GetText() or "")
            if labelText == "" then
                labelText = "Macro"
            end
            -- No icon is stored: SlotDisplay falls back to the question mark,
            -- which is what an unnamed custom macro looks like on an action bar
            -- too.
            if AssignEntry({ slot = { kind = "macrotext", macrotext = body, name = labelText } }) then
                nameField:SetText("")
                editField:SetText("")
            end
        end)
        dropMenu:SetScript("OnHide", function(menuFrame)
            menuFrame.search:ClearFocus()
            nameField:ClearFocus()
            editField:ClearFocus()
            -- Replace mode ends with the menu, however it went down --
            -- committed, dismissed, or torn down by a page rebuild.
            pickerReplaceIndex = nil
        end)

        -- Click-outside dismissal, same test the CDM picker uses. The anchor is
        -- excluded so the "+" click that toggles the menu shut is not also read
        -- as a click outside it.
        dropMenu:SetScript("OnUpdate", function(menuFrame)
            if
                IsMouseButtonDown("LeftButton")
                and not menuFrame:IsMouseOver()
                and not (pickerAnchor and pickerAnchor:IsMouseOver())
            then
                menuFrame:Hide()
            end
        end)

        pickerMenu = dropMenu
        return dropMenu
    end

    -- Anchors the list under whichever header rows the current view shows and
    -- sizes the menu to its content.
    local function PickerFit(dropMenu, total)
        -- Measured off the rows themselves rather than off menu.cat: a
        -- sub-category list shows the Back row without being an entry view,
        -- and reserving no space for it would put the first row under it.
        -- Views with no search box (category lists, noSearch categories)
        -- collapse the nav strip to the Back row alone.
        local topY = PICK_HEAD_H
        if dropMenu.back:IsShown() then
            topY = topY + (dropMenu.search:IsShown() and PICK_NAV_H or (PICK_ROW_H + 4))
        end
        dropMenu.scroll:ClearAllPoints()
        dropMenu.scroll:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -topY)
        dropMenu.scroll:SetPoint("RIGHT", dropMenu, "RIGHT", -1, 0)
        local listH = math.max(PICK_ROW_H, total * PICK_ROW_H)
        dropMenu.list:SetHeight(listH)
        local visH = math.min(listH, PICK_MAX_LIST)
        dropMenu.scroll:SetHeight(visH)
        dropMenu:SetHeight(topY + visH + 4)
        dropMenu.scroll:SetVerticalScroll(0)
        dropMenu:UpdateThumb()
    end

    -- parent = nil for the root list, or the category whose sub-list to show.
    ShowPickerCategories = function(hostFrame)
        local dropMenu = EnsurePickerMenu()
        local cats = hostFrame and hostFrame.subs or PICKER_CATEGORIES
        -- No cat: this is a list of categories, and the search box has nothing
        -- to filter. The Back row is the one thing that differs between the two
        -- levels -- the root has nowhere above it.
        dropMenu.cat = nil
        dropMenu.title:SetText(
            CludesUI.L(
                hostFrame and hostFrame.label or (pickerReplaceIndex and "Change Action" or "Add Action")
            )
        )
        dropMenu.back:SetShown(hostFrame ~= nil)
        dropMenu.backText:SetText(CludesUI.L("Categories"))
        -- Focus first: hiding a focused edit box leaves the keyboard captured by
        -- a box that is no longer on screen.
        dropMenu.search:ClearFocus()
        dropMenu.search:Hide()
        dropMenu.custom:Hide()
        dropMenu.scroll:Show()
        -- Only the root list carries the nest row, so only it draws the
        -- divider under row 1.
        dropMenu.catDivider:SetShown(hostFrame == nil)

        for i, category in ipairs(cats) do
            local rw = dropMenu:GetRow(i)
            rw.icon:Hide()
            -- Rows are shared with the entry views, which anchor the label to
            -- the icon -- so both views re-anchor it every time.
            rw.label:ClearAllPoints()
            rw.label:SetPoint("LEFT", rw, "LEFT", 8, 0)
            rw.label:SetPoint("RIGHT", rw, "RIGHT", -6, 0)
            rw.label:SetText(CludesUI.L(category.label))
            rw:SetScript("OnClick", function()
                if category.custom then
                    ShowPickerCustom()
                elseif category.subs then
                    ShowPickerCategories(category)
                else
                    dropMenu.search:SetText("")
                    ShowPickerCategory(category)
                end
            end)
            rw:Show()
        end

        -- Replace mode's root list ends with a Remove Action row: removal
        -- otherwise lives on middle-click alone, and not every mouse has a
        -- middle button. Root only -- inside a category the list is answers
        -- to "change it to what", and Back already leads out.
        local total = #cats
        if hostFrame == nil and pickerReplaceIndex then
            total = total + 1
            local rw = dropMenu:GetRow(total)
            rw.icon:Hide()
            rw.label:ClearAllPoints()
            rw.label:SetPoint("LEFT", rw, "LEFT", 8, 0)
            rw.label:SetPoint("RIGHT", rw, "RIGHT", -6, 0)
            rw.label:SetText(CludesUI.L("Remove Action"))
            rw:SetScript("OnClick", function()
                -- Before HidePicker, which clears the index on OnHide. The
                -- guard mirrors AssignEntry's: a slot already gone leaves
                -- nothing to remove and the menu stays up.
                local pmenu = MenuTable(editingMenu)
                if pmenu and pickerReplaceIndex and mod.RemoveSlot(pmenu, pickerReplaceIndex) then
                    HidePicker()
                    Reapply()
                end
            end)
            rw:Show()
        end
        for i = total + 1, #dropMenu.rows do
            dropMenu.rows[i]:Hide()
        end

        PickerFit(dropMenu, total)
        dropMenu:Show()
    end

    ShowPickerCategory = function(category)
        local dropMenu = EnsurePickerMenu()
        dropMenu.cat = category
        dropMenu.title:SetText(CludesUI.L(category.label))
        dropMenu.back:Show()
        dropMenu.backText:SetText(CludesUI.L(category.parent and category.parent.label or "Categories"))
        -- Focus first when hiding: a hidden edit box keeps the keyboard.
        if category.noSearch then
            dropMenu.search:ClearFocus()
            dropMenu.search:Hide()
        else
            dropMenu.search:Show()
            -- The placeholder names what the box searches. A list that also
            -- matches source and favorite is worth nothing if the only way to
            -- find that out is to guess it.
            dropMenu.searchPH:SetText(
                CludesUI.L(category.keywordHint and "Search name, source, favorite..." or "Search...")
            )
            dropMenu.searchPH:SetShown((dropMenu.search:GetText() or "") == "")
        end
        dropMenu.custom:Hide()
        dropMenu.scroll:Show()
        dropMenu.catDivider:Hide()

        local entries = pickerLists[category.key]
        if not entries then
            entries = category.build()
            -- Alphabetical rather than in enumeration order: the spellbook's own
            -- grouping means nothing once the tabs are gone, and a name is what
            -- the user is scanning for. A category can opt out for a list whose
            -- own order IS the one the user knows -- the markers run star to
            -- skull, the order every marker menu in the game shows.
            -- A pinned entry sorts ahead of every plain one whatever its name.
            -- Pinning is per entry rather than per category so a list that is
            -- otherwise alphabetical can still lead with the row the user came
            -- for.
            if not category.keepOrder then
                table.sort(entries, function(a, b)
                    if (a.pin or false) ~= (b.pin or false) then
                        return a.pin == true
                    end
                    -- WoW Forever's lower ranks follow their spell's row, highest first.
                    local an, bn = a.sortName or a.name, b.sortName or b.name
                    if an ~= bn then
                        return an < bn
                    end
                    return (a.rankNum or math.huge) > (b.rankNum or math.huge)
                end)
            end
            pickerLists[category.key] = entries
        end

        local filter = category.noSearch and "" or (dropMenu.search:GetText() or ""):lower()
        local num = 0
        for _, record in ipairs(entries) do
            -- The name first, then whatever else the entry knows about itself.
            -- A picker holding several hundred rows that can only be searched
            -- by name can only be searched by someone who already knows the
            -- name of the thing they want, which is the opposite of what a
            -- search is for. Keywords are built once with the list and are
            -- already lowercase; this runs on every keystroke.
            if
                filter == ""
                or record.name:lower():find(filter, 1, true)
                or (record.keywords and record.keywords:find(filter, 1, true))
            then
                num = num + 1
                local rw = dropMenu:GetRow(num)
                rw.icon:SetTexture(record.icon or QUESTION_MARK)
                -- Rows are pooled across categories, and the marker textures
                -- take the full rect where action icons take the crop.
                if mod.ApplyIconCrop then
                    mod.ApplyIconCrop(rw.icon, record.icon)
                end
                rw.icon:Show()
                rw.label:ClearAllPoints()
                rw.label:SetPoint("LEFT", rw.icon, "RIGHT", 6, 0)
                rw.label:SetPoint("RIGHT", rw, "RIGHT", -6, 0)
                rw.label:SetText(CludesUI.L(record.name))
                rw:SetScript("OnClick", function()
                    AssignEntry(record)
                end)
                rw:Show()
            end
        end

        local isShown = num
        if num == 0 then
            -- An empty menu reads as broken, so say why it is empty.
            local rw = dropMenu:GetRow(1)
            rw.icon:Hide()
            rw.label:ClearAllPoints()
            rw.label:SetPoint("LEFT", rw, "LEFT", 8, 0)
            rw.label:SetPoint("RIGHT", rw, "RIGHT", -6, 0)
            rw.label:SetText(filter == "" and CludesUI.L("Nothing to add") or CludesUI.L("No matches"))
            rw:SetScript("OnClick", nil)
            rw:Show()
            isShown = 1
        end
        for i = isShown + 1, #dropMenu.rows do
            dropMenu.rows[i]:Hide()
        end

        PickerFit(dropMenu, isShown)
        dropMenu:Show()
    end

    ShowPickerCustom = function()
        local dropMenu = EnsurePickerMenu()
        -- No cat recorded: menu.cat means "a list view is up, re-filter it on a
        -- keystroke", and there is no list here.
        dropMenu.cat = nil
        dropMenu.title:SetText(CludesUI.L("Custom Macro"))
        dropMenu.back:Show()
        -- Restated rather than left as it was: the row is shared, and the view
        -- before this one may have been a sub-category's.
        dropMenu.backText:SetText(CludesUI.L("Categories"))
        dropMenu.search:ClearFocus()
        dropMenu.search:Hide()
        -- Hiding the scroll frame takes the pooled rows with it: they are its
        -- scroll child's children.
        dropMenu.scroll:Hide()
        dropMenu.catDivider:Hide()
        dropMenu.custom:Show()
        dropMenu:SetHeight(PICK_HEAD_H + PICK_ROW_H + 6 + dropMenu.custom:GetHeight() + 4)
        dropMenu:Show()
    end

    -- replaceIndex: open in replace mode on that slot (right-click on an
    -- entry); nil is the "+" append mode.
    local function TogglePicker(wdg, replaceIndex)
        local dropMenu = EnsurePickerMenu()
        if dropMenu:IsShown() and pickerAnchor == wdg then
            HidePicker()
            return
        end
        -- Dropped per open, not per category view: bags, macros and collections
        -- all change while the game is running, and one open is the coarsest
        -- point at which a rebuild is still free (the keystroke filtering is
        -- what the cache is there to protect).
        wipe(pickerLists)
        pickerAnchor = wdg
        pickerReplaceIndex = replaceIndex
        dropMenu:ClearAllPoints()
        dropMenu:SetPoint("TOP", wdg, "BOTTOM", 0, -4)
        -- Cleared before the SetText below, which fires OnTextChanged: with the
        -- previous open's category still recorded, that would re-enumerate and
        -- briefly show the wrong view.
        dropMenu.cat = nil
        dropMenu.search:SetText("")
        ShowPickerCategories()
    end

    ---------------------------------------------------------------------------
    --  Palette presets
    --
    --  Each builder returns the slots a new palette starts with, worked out
    --  from what THIS character knows or carries at the moment the chooser
    --  opens -- a preset must never seed a slot that cannot fire. A preset
    --  whose builder comes back empty is left out of the chooser, which is
    --  also how the class-specific ones gate themselves: IsPlayerSpell answers
    --  no to every spell on the wrong class.
    ---------------------------------------------------------------------------
    local function TargetMarkerSlots()
        local result = {}
        for i = 1, 8 do
            result[#result + 1] = { kind = "raidtarget", id = i }
        end
        result[#result + 1] = { kind = "raidtarget", id = 0 }
        return result
    end

    local function WorldMarkerSlots()
        local result = {}
        for i = 1, 8 do
            result[#result + 1] = { kind = "worldmarker", id = i }
        end
        result[#result + 1] = { kind = "worldmarker", id = 0 }
        return result
    end

    -- Numeric /ping aliases (1 attack, 2 warning, 3 on my way, 4 assist, 5 look):
    -- the word forms resolve through localized PING_TYPE_* globals and only match
    -- on English clients.
    local function PingSlots()
        return {
            {
                kind = "macrotext",
                name = "Look",
                macrotext = "/ping 5",
                icon = { atlas = "Ping_Marker_Icon_NonThreat" },
            },
            {
                kind = "macrotext",
                name = "Assist",
                macrotext = "/ping 4",
                icon = { atlas = "Ping_Marker_Icon_Assist" },
            },
            {
                kind = "macrotext",
                name = "Attack",
                macrotext = "/ping 1",
                icon = { atlas = "Ping_Marker_Icon_Attack" },
            },
            {
                kind = "macrotext",
                name = "Warning",
                macrotext = "/ping 2",
                icon = { atlas = "Ping_Marker_Icon_Warning" },
            },
            {
                kind = "macrotext",
                name = "On My Way",
                macrotext = "/ping 3",
                icon = { atlas = "Ping_Marker_Icon_OnMyWay" },
            },
        }
    end

    -- The base item plus its two expansion siblings, then the toy variants.
    -- The toys all share one cooldown and one destination, so past MAX_SLOTS
    -- the tail is interchangeable with what already made it in.
    local HEARTH_ITEMS = { 6948, 140192, 110560 } -- Hearthstone, Dalaran, Garrison
    local HEARTH_TOYS = {
        54452,
        64488,
        93672,
        142542,
        162973,
        163045,
        165669,
        165670,
        165802,
        166746,
        166747,
        168907,
        172179,
        180290,
        182773,
        183716,
        184353,
        188952,
        190196,
        190237,
        193588,
        200630,
        206195,
        208704,
        209035,
        212337,
        228940,
    }
    -- A builder returns what it found and, second, how many it had to leave
    -- out. A preset that quietly stopped at the cap was the "it also seems to
    -- limit hearthstones" half of the report: the toys share a cooldown, so
    -- dropping the tail of THOSE costs nothing, but a hearthstone the player
    -- owns and cannot see is a destination they have lost. Counted here and
    -- said in the menu rather than fixed by raising a cap on its own -- some
    -- collections are simply larger than any menu.
    local function HearthstoneSlots()
        local result, spill = {}, 0
        for _, itemId in ipairs(HEARTH_ITEMS) do
            if C_Item.GetItemCount(itemId) > 0 then
                result[#result + 1] = { kind = "item", id = itemId }
            end
        end
        for _, toyID in ipairs(HEARTH_TOYS) do
            if PlayerHasToy(toyID) then
                if #result < MAX_SLOTS then
                    result[#result + 1] = { kind = "toy", id = toyID }
                else
                    spill = spill + 1
                end
            end
        end
        return result, spill
    end

    -- Keep Blizzard's order and report anything over the menu cap.
    local function OutfitSlots()
        local result = mod.OutfitSlots and mod.OutfitSlots() or {}
        local spill = math.max(0, #result - MAX_SLOTS)
        for i = #result, MAX_SLOTS + 1, -1 do
            result[i] = nil
        end
        return result, spill
    end

    local function EquipmentSetSlots()
        local result = mod.EquipmentSetSlots()
        local spill = math.max(0, #result - MAX_SLOTS)
        for i = #result, MAX_SLOTS + 1, -1 do
            result[i] = nil
        end
        return result, spill
    end

    -- Self-teleports only, keyed by class. Mage portals are deliberately not
    -- here: a palette entry fires for its owner, and the teleport is the spell
    -- an owner wants.
    local TELEPORT_SPELLS = {
        DEATHKNIGHT = { 50977 }, -- Death Gate
        DRUID = { 193753 }, -- Dreamwalk
        MONK = { 126892 }, -- Zen Pilgrimage
        SHAMAN = { 556 }, -- Astral Recall
        MAGE = {
            3561,
            3562,
            3563,
            3565,
            3566,
            3567, -- the classic capitals
            32271,
            32272,
            33690,
            35715,
            49358,
            49359, -- Outland-era cities
            53140,
            88342,
            88344,
            132621,
            132627, -- Dalaran, Tol Barad, Vale
            176248,
            176242,
            224869,
            281403,
            281404, -- Warspear era through Boralus
            344587,
            395277,
            446540, -- Oribos, Valdrakken, Dornogal
        },
    }
    local function TeleportSlots()
        local result, spill = {}, 0
        local entries = TELEPORT_SPELLS[select(2, UnitClass("player"))]
        for _, spellId in ipairs(entries or {}) do
            if IsPlayerSpell(spellId) then
                if #result < MAX_SLOTS then
                    result[#result + 1] = { kind = "spell", id = spellId }
                else
                    spill = spill + 1
                end
            end
        end
        return result, spill
    end

    -- The same bag walk ItemEntries does, narrowed to drinkable consumables.
    -- Numeric subclasses: Enum.ItemConsumableSubclass stops at Other, the
    -- finer rows exist only as these constants (ItemDocumentation.lua).
    local function PotionSlots()
        local result, seen = {}, {}
        local function ScanBag(bag)
            for ent = 1, C_Container.GetContainerNumSlots(bag) do
                local details = C_Container.GetContainerItemInfo(bag, ent)
                local itemId = details and details.itemID
                if itemId and not seen[itemId] and #result < MAX_SLOTS and C_Item.GetItemSpell(itemId) then
                    seen[itemId] = true
                    local classID, subClassID = select(6, C_Item.GetItemInfoInstant(itemId))
                    if
                        classID == Enum.ItemClass.Consumable
                        and (subClassID == 1 or subClassID == 2 or subClassID == 3)
                    then
                        result[#result + 1] = { kind = "item", id = itemId }
                    end
                end
            end
        end
        for bag = Enum.BagIndex.Backpack, NUM_BAG_SLOTS do
            ScanBag(bag)
        end
        ScanBag(Enum.BagIndex.ReagentBag)
        return result
    end

    -- Every form a druid can be in, plus the two that are really ways of
    -- moving between them. Aquatic and Flight are listed even though Travel
    -- Form has absorbed both on most builds: IsPlayerSpell is what decides,
    -- and a spell nobody has simply does not appear.
    local FORM_SPELLS = {
        5487, -- Bear Form
        768, -- Cat Form
        5215, -- Prowl
        783, -- Travel Form
        1066, -- Aquatic Form
        165962, -- Flight Form
        24858, -- Moonkin Form
        114282, -- Treant Form
    }
    local function FormSlots()
        local result, spill = {}, 0
        for _, spellId in ipairs(FORM_SPELLS) do
            if IsPlayerSpell(spellId) then
                if #result < MAX_SLOTS then
                    result[#result + 1] = { kind = "spell", id = spellId }
                else
                    spill = spill + 1
                end
            end
        end
        -- Getting OUT is the half of shapeshifting no form spell covers, and
        -- there is no spell for it at all -- /cancelform is the whole of it.
        -- Only offered once a form has been found, so the preset stays hidden
        -- on a class that has none. The clear icon the marker entries use,
        -- because it says the same thing.
        if #result > 0 and #result < MAX_SLOTS then
            result[#result + 1] = {
                kind = "macrotext",
                macrotext = "/cancelform",
                name = "Cancel Form",
                icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
            }
        end
        return result, spill
    end

    -- One-of-a-set toggles that are not forms: a warrior's stances and a
    -- paladin's auras are the same choice in two costumes, and both are
    -- ordinary spells.
    local STANCE_SPELLS = {
        WARRIOR = { 386164, 386208, 386196 }, -- Battle, Defensive, Berserker
        PALADIN = { 465, 32223, 183435, 317920 }, -- Devotion, Crusader, Retribution, Concentration
    }
    local function StanceSlots()
        local result, spill = {}, 0
        for _, spellId in ipairs(STANCE_SPELLS[select(2, UnitClass("player"))] or {}) do
            if IsPlayerSpell(spellId) then
                if #result < MAX_SLOTS then
                    result[#result + 1] = { kind = "spell", id = spellId }
                else
                    spill = spill + 1
                end
            end
        end
        return result, spill
    end

    -- By position rather than by identity. A preset is the palette a player
    -- has not built by hand, so it is the one most likely to be copied to a
    -- profile an alt shares -- and the only preset here whose slots would
    -- otherwise all go dead on arrival.
    --
    -- No dropped count: four positions against a twenty-slot menu, so unlike
    -- the collection presets this one can never be the thing that does not
    -- fit. Empty is the stale-module case, and leaves the preset unoffered.
    local function SpecSlots()
        local entryList = {}
        for _, record in ipairs(DynamicSpecEntries()) do
            entryList[#entryList + 1] = record.slot
        end
        return entryList
    end

    -- Quest items the character is carrying that DO something: the bag walk
    -- ItemEntries makes, narrowed to the quest item class and to items with a
    -- use effect. An item with no effect is a quest object being carried, not
    -- something an entry can fire.
    --
    -- The quest log's own special items are folded in as well. Those are the
    -- ones the objective tracker draws a button for, and they are not always
    -- in the quest item CLASS -- a trinket or a toy handed out for one quest
    -- reads as its own class and would be missed by the bag walk alone.
    -- GetQuestLogSpecialItemInfo is the same call the tracker makes
    -- (Blizzard_ObjectiveTrackerShared.lua:53).
    --
    -- A snapshot, like every preset here: it holds what the character carries
    -- at the moment the menu is built. See the note under QD-07a in the bug
    -- report for the self-refilling version and why it is not this.
    local function QuestItemSlots()
        local result, seen, spill = {}, {}, 0
        local function Add(itemId)
            if not itemId or seen[itemId] then
                return
            end
            if not C_Item.GetItemSpell(itemId) then
                return
            end
            seen[itemId] = true
            if #result < MAX_SLOTS then
                result[#result + 1] = { kind = "item", id = itemId }
            else
                spill = spill + 1
            end
        end
        local function ScanBag(bag)
            for ent = 1, C_Container.GetContainerNumSlots(bag) do
                local details = C_Container.GetContainerItemInfo(bag, ent)
                local itemId = details and details.itemID
                if itemId and not seen[itemId] then
                    local classID = select(6, C_Item.GetItemInfoInstant(itemId))
                    if classID == Enum.ItemClass.Questitem then
                        Add(itemId)
                    end
                end
            end
        end
        for bag = Enum.BagIndex.Backpack, NUM_BAG_SLOTS do
            ScanBag(bag)
        end
        ScanBag(Enum.BagIndex.ReagentBag)

        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local details = C_QuestLog.GetInfo(i)
            if details and not details.isHeader then
                -- The LINK, which is the first return; the second is the
                -- button's texture, not an id. GetItemInfoInstant takes a link
                -- and hands back the itemID first.
                local itemLink = GetQuestLogSpecialItemInfo(i)
                if itemLink then
                    Add((C_Item.GetItemInfoInstant(itemLink)))
                end
            end
        end
        return result, spill
    end

    -- By position rather than by identity, the same reasoning as SpecSlots
    -- above and for the same reason: a preset is the palette most likely to
    -- be copied to an alt, and only a position survives that trip. Ten
    -- positions against a twenty-slot menu, so no dropped count either --
    -- see DynamicProfessionEntries for what each position means.
    local function ProfessionSlots()
        local entryList = {}
        for _, record in ipairs(DynamicProfessionEntries()) do
            entryList[#entryList + 1] = record.slot
        end
        return entryList
    end

    -- The micro menu as a menu, which is the whole of what this preset is for:
    -- one keybind in place of the dozen the panels take between them. The
    -- module drops the panels this client has not got and holds back the two
    -- worth least in a ring -- the Shop and Customer Support -- so a full house
    -- lands on MAX_SLOTS exactly rather than reporting an overflow every time.
    -- Both are still in the picker for anyone who wants them.
    local function InterfacePanelSlots()
        return mod.PanelSlots and mod.PanelSlots(false) or {}
    end

    local PALETTE_PRESETS = {
        { label = "Interface Panels", build = InterfacePanelSlots },
        { label = "Target Markers", build = TargetMarkerSlots },
        { label = "World Markers", build = WorldMarkerSlots },
        { label = "Pings", build = PingSlots },
        { label = "Hearthstones", build = HearthstoneSlots },
        { label = "Outfits", build = OutfitSlots },
        { label = "Equipment Sets", build = EquipmentSetSlots },
        { label = "Teleports", build = TeleportSlots },
        { label = "Potions", build = PotionSlots },
        { label = "Druid Forms", build = FormSlots },
        { label = "Stances", build = StanceSlots },
        { label = "Specializations", build = SpecSlots },
        { label = "Professions", build = ProfessionSlots },
        { label = "Quest Items", build = QuestItemSlots },
    }

    ---------------------------------------------------------------------------
    --  Adding and deleting palettes
    --
    --  The palette count used to be a slider. A slider says nothing about what
    --  the new palette will hold; the Add button opens a chooser instead --
    --  empty, or seeded from one of the presets above.
    ---------------------------------------------------------------------------

    -- slots comes in already built (the chooser built it to decide whether to
    -- offer the preset at all), and each table in it is fresh from the
    -- builder, so nothing here needs copying.
    local function AddPalette(preset, entryList)
        local total = MenuCount()
        if total >= MAX_PALETTES then
            return
        end
        ProfilePut("paletteCount", total + 1)
        local pmenu = MenuTable(total + 1)
        if pmenu then
            -- The index may have been used and abandoned by the retired
            -- palette-count slider, whose decrease hid palettes without
            -- clearing them. A palette added on purpose starts empty.
            pmenu.slots = {}
            pmenu.icon = nil
            pmenu.appearance = nil
            -- Seed the name in the player's language: it is user data from the
            -- moment it exists (renameable), so store the translated label.
            pmenu.name = (preset and CludesUI.L(preset.label)) or AutoName(total + 1)
            for _, sv in ipairs(entryList or {}) do
                if not mod.AddSlot(pmenu, sv) then
                    break
                end
            end
        end
        editingMenu = total + 1
        HidePicker()
        RedrawPage()
    end

    -- One pooled row of the shared menu, filled in. Shared by the two views
    -- below that list something other than actions; the action views anchor
    -- their labels the same two ways inline.
    local function MenuRow(dropMenu, i, glyph, labelText, onClick)
        local rw = dropMenu:GetRow(i)
        if glyph then
            if type(glyph) == "table" and glyph.atlas then
                rw.icon:SetAtlas(glyph.atlas)
            else
                rw.icon:SetTexture(glyph)
            end
            rw.icon:Show()
            rw.label:ClearAllPoints()
            rw.label:SetPoint("LEFT", rw.icon, "RIGHT", 6, 0)
        else
            rw.icon:Hide()
            rw.label:ClearAllPoints()
            rw.label:SetPoint("LEFT", rw, "LEFT", 8, 0)
        end
        rw.label:SetPoint("RIGHT", rw, "RIGHT", -6, 0)
        rw.label:SetText(labelText)
        rw:SetScript("OnClick", onClick)
        rw:Show()
    end

    -- Open the shared menu as a plain list with `title` at the top, ready for
    -- MenuRow. Returns the menu, or nil when this click was the one that
    -- closes an already-open list on the same anchor.
    local function OpenListMenu(anchor, title)
        if not anchor then
            return nil
        end
        local dropMenu = EnsurePickerMenu()
        if dropMenu:IsShown() and pickerAnchor == anchor then
            HidePicker()
            return nil
        end
        pickerAnchor = anchor
        dropMenu:ClearAllPoints()
        dropMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
        dropMenu.cat = nil
        dropMenu.title:SetText(CludesUI.L(title))
        dropMenu.back:Hide()
        dropMenu.search:ClearFocus()
        dropMenu.search:Hide()
        dropMenu.custom:Hide()
        dropMenu.scroll:Show()
        dropMenu.catDivider:Hide()
        return dropMenu
    end

    -- A view on the same anchored menu the action picker uses, so the add
    -- button and the "+" entry cannot both have one open: whichever opens
    -- second takes the menu over.
    local function ShowAddPaletteMenu(anchor)
        local dropMenu = OpenListMenu(anchor, "Add Action Menu")
        if not dropMenu then
            return
        end

        MenuRow(dropMenu, 1, nil, CludesUI.L("Empty Action Menu"), function()
            AddPalette(nil)
        end)
        local num = 1
        for _, preset in ipairs(PALETTE_PRESETS) do
            local entryList, spill = preset.build()
            if #entryList > 0 then
                num = num + 1
                local glyph = mod.SlotDisplay(entryList[1])
                -- The count, and what a full menu could not take. A preset that
                -- stopped at the cap and said nothing looked like a preset that
                -- had found everything there was.
                local total = "  |cff808080(" .. #entryList .. ")|r"
                if spill and spill > 0 then
                    total = total .. " |cffd08050" .. CludesUI.Lf("%1$d did not fit", spill) .. "|r"
                end
                MenuRow(dropMenu, num, glyph or QUESTION_MARK, CludesUI.L(preset.label) .. total, function()
                    AddPalette(preset, entryList)
                end)
            end
        end
        for i = num + 1, #dropMenu.rows do
            dropMenu.rows[i]:Hide()
        end

        PickerFit(dropMenu, num)
        dropMenu:Show()
    end

    -- Deletion really removes the palette rather than hiding it the way the
    -- slider's decrease did: the palettes above it close ranks, and everything
    -- that pointed at them follows -- nested entries repoint to the shifted
    -- index, entries that opened the deleted palette are removed, and each
    -- shifted palette's keybind moves with it.
    local function DeletePalette(index)
        local p = DB()
        local total = MenuCount()
        if not p or total <= 1 or index < 1 or index > total then
            return
        end

        -- The keybind shift below runs SetBinding, so the same combat wall the
        -- keybind picker documents applies to the whole operation.
        if InCombatLockdown() then
            Complain("Action Wheel: action menus can't be deleted in combat.")
            return
        end

        -- Materialize every live palette first: the shift walks 1 .. count and
        -- table.remove stops at the first hole.
        for i = 1, total do
            MenuTable(i)
        end

        -- Keys the deleted palette shared stay with the palettes sharing them,
        -- before the indexes move.
        local handed = HandOffKeys(index, GetBindingKey(BINDING_PREFIX .. index))

        table.remove(p.palettes, index)
        ProfilePut("paletteCount", total - 1)

        -- The auto-names close ranks with everything else. A palette the user
        -- never renamed carries the number it was made under, so deleting
        -- "Action Menu 1" would otherwise leave "Action Menu 2" sitting at
        -- index 1 -- and Add, which names by index, would then hand out that
        -- same name a second time. Only the auto-name moves: a name the user
        -- typed is theirs, whatever it happens to look like.
        for i = index, total - 1 do
            local pmenu = MenuTable(i)
            if pmenu and pmenu.name == AutoName(i + 1) then
                pmenu.name = AutoName(i)
            end
        end

        for i = 1, total - 1 do
            local pmenu = MenuTable(i)
            for jdx = #pmenu.slots, 1, -1 do
                local sv = pmenu.slots[jdx]
                if sv.kind == "palette" then
                    local target = tonumber(sv.palette)
                    if target == index then
                        table.remove(pmenu.slots, jdx)
                    elseif target and target > index then
                        sv.palette = target - 1
                    end
                end
            end
            -- A shared key follows its holder down one index.
            local share = tonumber(pmenu.keyShare)
            if share == index then
                pmenu.keyShare = nil
            elseif share and share > index then
                pmenu.keyShare = share - 1
            end
        end

        -- Each action can hold TWO keys (see CommitKey), so the whole set is
        -- snapshotted, everything from the deleted index up is unbound, and
        -- then each successor's keys are rebound one action lower. Interleaving
        -- the two passes would unbind keys the previous step just moved.
        local keyList, any = {}, false
        for num = 1, MAX_PALETTES do
            keyList[num] = { GetBindingKey(BINDING_PREFIX .. num) }
            if num >= index and keyList[num][1] then
                any = true
            end
        end
        for num = index, MAX_PALETTES do
            for _, k in ipairs(keyList[num]) do
                SetBinding(k)
            end
        end
        for num = index, MAX_PALETTES - 1 do
            for _, k in ipairs(keyList[num + 1] or {}) do
                SetBinding(k, BINDING_PREFIX .. num)
            end
        end
        if any or handed then
            SaveBindings(GetCurrentBindingSet())
        end

        -- Keep the editor pointed at the palette it was on, which now sits one
        -- index lower; deleting the edited palette itself falls to whichever
        -- palette took its number.
        if editingMenu > index then
            editingMenu = editingMenu - 1
        end
        if editingMenu > total - 1 then
            editingMenu = total - 1
        end
        RedrawPage()
    end

    ---------------------------------------------------------------------------
    --  Editing Action Menu selector -- the Profiles & Presets "Active
    --  Profile" dropdown re-cut for menus: every row carries the same inline
    --  rename (pencil) and delete (X) buttons, in exactly that style, and
    --  those are where renaming and deleting live now (the page rows they
    --  replace are gone). The MENU frame and its item pool are cached across
    --  page rebuilds -- only the anchor button rebuilds with the page -- so
    --  rebuilds leak nothing.
    ---------------------------------------------------------------------------
    local mmMenu
    local mmItems = {}
    local MM_W, MM_X = 170, 14

    local function EnsureMenuMenu()
        if mmMenu then
            return mmMenu
        end
        local PPQ = CludesUI.PanelPP
        local menuFrame = CreateFrame("Frame", nil, UIParent)
        menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        menuFrame:SetFrameLevel(200)
        menuFrame:SetClampedToScreen(true)
        menuFrame:SetSize(MM_W, 4)
        menuFrame:Hide()
        local backdrop = menuFrame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, 0.98)
        CludesUI.MakeBorder(menuFrame, 1, 1, 1, CludesUI.DD_BRD_A, PPQ)
        -- Click-outside dismissal + anchor scale matching, the profile
        -- menu's own. The anchor is re-pointed per page build (m._anchor).
        menuFrame:SetScript("OnShow", function(self)
            local anchor = self._anchor
            if anchor then
                self:SetScale(anchor:GetEffectiveScale() / UIParent:GetEffectiveScale())
            end
            self:SetScript("OnUpdate", function(mm)
                local a2 = mm._anchor
                if (not a2 or not a2:IsMouseOver()) and not mm:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        mm:Hide()
                    end
                end
            end)
        end)
        menuFrame:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
        mmMenu = menuFrame
        return menuFrame
    end

    -- A row's small inline button (the pencil or the X): square, two levels
    -- above its row, unsnapped art, resting at the dim alpha. The caller
    -- anchors it.
    local function RowInlineButton(owner, iconFile)
        local b = CreateFrame("Button", nil, owner)
        b:SetSize(MM_X, MM_X)
        b:SetFrameLevel(owner:GetFrameLevel() + 2)
        local art = b:CreateTexture(nil, "OVERLAY")
        art:SetAllPoints()
        if art.SetSnapToPixelGrid then
            art:SetSnapToPixelGrid(false)
            art:SetTexelSnappingBias(0)
        end
        art:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\" .. iconFile)
        b:SetAlpha(0.4)
        return b
    end

    -- One pooled row of the selector menu: the menu's icon on the left (the
    -- class-icon dropdown look, mirrored, since rename and delete own the
    -- right edge; cropped like every action icon), its name, a highlight,
    -- and the two inline buttons. The row lights while the pointer is over
    -- it or either button, the hovered button brightest.
    local function NewMenuRow(menuFrame, font)
        local rowBtn = CreateFrame("Button", nil, menuFrame)
        rowBtn:SetHeight(26)
        rowBtn:SetFrameLevel(menuFrame:GetFrameLevel() + 1)
        local ico = rowBtn:CreateTexture(nil, "ARTWORK")
        ico:SetSize(18, 18)
        ico:SetPoint("LEFT", rowBtn, "LEFT", 8, 0)
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        rowBtn._ico = ico
        local labelFS = rowBtn:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(font, 13, CludesUI.GetFontOutlineFlag())
        labelFS:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        labelFS:SetPoint("RIGHT", rowBtn, "RIGHT", -(MM_X * 2 + 22), 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
        rowBtn._lbl = labelFS
        local highlight = rowBtn:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 1)
        highlight:SetAlpha(0)
        rowBtn._hl = highlight

        local xBtn = RowInlineButton(rowBtn, "cui-close.png")
        xBtn:SetPoint("RIGHT", rowBtn, "RIGHT", -8, 0)
        rowBtn._xBtn = xBtn
        local editBtn = RowInlineButton(rowBtn, "cui-edit.png")
        editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
        rowBtn._editBtn = editBtn

        local function Lit(on)
            if on then
                labelFS:SetTextColor(1, 1, 1, 1)
                highlight:SetAlpha(CludesUI.DD_ITEM_HL_A)
            else
                labelFS:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                highlight:SetAlpha(rowBtn._isSel and CludesUI.DD_ITEM_SEL_A or 0)
            end
            local a2 = on and 0.8 or 0.4
            xBtn:SetAlpha(a2)
            editBtn:SetAlpha(a2)
        end
        local function OverButtons()
            return xBtn:IsMouseOver() or editBtn:IsMouseOver()
        end
        rowBtn:SetScript("OnEnter", function()
            Lit(true)
        end)
        rowBtn:SetScript("OnLeave", function()
            if not OverButtons() then
                Lit(false)
            end
        end)
        for b, tip in pairs({ [xBtn] = "Delete", [editBtn] = "Rename" }) do
            b:SetScript("OnEnter", function(self2)
                Lit(true)
                self2:SetAlpha(1)
                CludesUI.ShowWidgetTooltip(self2, tip)
            end)
            b:SetScript("OnLeave", function(self2)
                if rowBtn:IsMouseOver() or OverButtons() then
                    self2:SetAlpha(0.8)
                else
                    Lit(false)
                end
                CludesUI.HideWidgetTooltip()
            end)
        end
        return rowBtn
    end

    -- Delete and rename, each behind its popup. Both close the menu first.
    local function AskDeleteMenu(position)
        mmMenu:Hide()
        local menuT = MenuTable(position)
        CludesUI:ShowConfirmPopup({
            title = "Delete Action Menu",
            message = CludesUI.Lf(
                "Delete %1$s and its contents? Entries "
                    .. "in other action menus that open it are removed "
                    .. "too, and the menus after it move up one place.",
                (menuT and menuT.name) or AutoName(position)
            ),
            confirmText = "Delete",
            cancelText = "Cancel",
            onConfirm = function()
                DeletePalette(position)
            end,
        })
    end
    local function AskRenameMenu(position)
        mmMenu:Hide()
        local menuT = MenuTable(position)
        local current = (menuT and menuT.name) or AutoName(position)
        CludesUI:ShowInputPopup({
            title = "Rename Action Menu",
            message = CludesUI.Lf('Enter a new name for "%1$s":', current),
            placeholder = current,
            confirmText = "Rename",
            cancelText = "Cancel",
            onConfirm = function(newName)
                local target = MenuTable(position)
                if not target then
                    return
                end
                -- Trimmed, and cut to 24 characters: the hub caption sits in
                -- a small arc, and anything longer runs under the entries
                -- either side. Empty goes back to the automatic name.
                newName = strtrim(newName or "")
                if #newName > 24 then
                    newName = newName:sub(1, 24)
                end
                if newName == "" then
                    newName = AutoName(position)
                end
                if newName ~= target.name then
                    target.name = newName
                    RedrawPage()
                end
            end,
        })
    end

    local function RebuildMenuRows()
        local menuFrame = EnsureMenuMenu()
        local font = (CludesUI.GetFontPath()) or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
        local count = MenuCount()
        local top = 4
        for i = 1, count do
            local rowBtn = mmItems[i] or NewMenuRow(menuFrame, font)
            mmItems[i] = rowBtn
            rowBtn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 1, -top)
            rowBtn:SetPoint("TOPRIGHT", menuFrame, "TOPRIGHT", -1, -top)
            local menuT = MenuTable(i)
            rowBtn._ico:SetTexture(PaletteListIcon(menuT))
            rowBtn._lbl:SetText((menuT and menuT.name) or AutoName(i))
            local selected = (i == editingMenu)
            rowBtn._isSel = selected
            rowBtn._hl:SetAlpha(selected and 0.04 or 0)
            rowBtn._lbl:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)

            -- Like the active profile, the menu being edited has no X (so
            -- the last menu left can never be deleted); its pencil slides
            -- over into the X's place. Deleting happens from another row.
            rowBtn._xBtn:SetShown(not selected)
            rowBtn._editBtn:ClearAllPoints()
            if selected then
                rowBtn._editBtn:SetPoint("RIGHT", rowBtn, "RIGHT", -8, 0)
            else
                rowBtn._editBtn:SetPoint("RIGHT", rowBtn._xBtn, "LEFT", -4, 0)
            end

            local position = i
            rowBtn:SetScript("OnClick", function()
                mmMenu:Hide()
                if position ~= editingMenu then
                    editingMenu = position
                    RedrawPage()
                end
            end)
            rowBtn._xBtn:SetScript("OnClick", function()
                AskDeleteMenu(position)
            end)
            rowBtn._editBtn:SetScript("OnClick", function()
                AskRenameMenu(position)
            end)
            rowBtn:Show()
            top = top + 26
        end
        for i = count + 1, #mmItems do
            mmItems[i]:Hide()
        end
        menuFrame:SetHeight(top + 4)
    end

    -- The anchor button, rebuilt with every page build (the menu above is
    -- not): the Profiles page's Active Profile dropdown look, verbatim.
    -- Nothing during the search index prebuild: its row is a stand-in with no
    -- frame to build on, and the row's own label is what the index lists.
    local function BuildMenuSelector(region)
        if CludesUI._prebuilding then
            return
        end
        local PPQ = CludesUI.PanelPP
        local btn = CreateFrame("Button", nil, region)
        -- 170x30, the exact face BuildDropdownControl gives every standard
        -- row dropdown, so this selector reads as one of them.
        PPQ.Size(btn, MM_W, 30)
        btn:SetFrameLevel(region:GetFrameLevel() + 3)
        PPQ.Point(btn, "RIGHT", region, "RIGHT", -20, 0)
        local backdrop = btn:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
        local brd = CludesUI.MakeRoundedBorder(btn, 1, 1, 1, CludesUI.DD_BRD_A, backdrop)
        -- The resting alpha is the text colour's, the channel the hover
        -- colours below write, so a hover and leave land back on it.
        local labelFS = CludesUI.MakeFont(btn, 13, nil, 1, 1, 1, CludesUI.DD_TXT_A)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetMaxLines(1)
        labelFS:SetPoint("LEFT", btn, "LEFT", 12, 0)
        local arrow = CludesUI.MakeDropdownArrow(btn, 12, PPQ)
        labelFS:SetPoint("RIGHT", arrow, "LEFT", -5, 0)
        local menuT = MenuTable(editingMenu)
        labelFS:SetText((menuT and menuT.name) or AutoName(editingMenu))
        local sv = CludesUI.RD_DD_COLOURS
        btn:SetScript("OnEnter", function()
            labelFS:SetTextColor(sv[21], sv[22], sv[23], sv[24])
            brd:SetColor(sv[13], sv[14], sv[15], sv[16])
            backdrop:SetColorTexture(sv[5], sv[6], sv[7], sv[8])
        end)
        btn:SetScript("OnLeave", function()
            labelFS:SetTextColor(sv[17], sv[18], sv[19], sv[20])
            brd:SetColor(sv[9], sv[10], sv[11], sv[12])
            backdrop:SetColorTexture(sv[1], sv[2], sv[3], sv[4])
        end)
        if ProfileGet("enabled") ~= true then
            btn:SetAlpha(0.4)
        end
        btn:SetScript("OnClick", function()
            if ProfileGet("enabled") ~= true then
                return
            end
            local menuFrame = EnsureMenuMenu()
            -- The same anchor only in the same dress: a page rebuild may dress
            -- this button again (page reuse), and an open menu then re-anchors
            -- to it as it would to a new button.
            if menuFrame:IsShown() and menuFrame._anchor == btn and menuFrame._anchorGen == Pool.Gen(btn) then
                menuFrame:Hide()
                return
            end
            menuFrame._anchor, menuFrame._anchorGen = btn, Pool.Gen(btn)
            menuFrame:ClearAllPoints()
            menuFrame:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            RebuildMenuRows()
            menuFrame:Show()
        end)
        region._lastInline = btn
        return btn
    end

    -- The shared keybind capture button, on the row's right half: left-click
    -- arms it and the next key press binds; right-click unbinds; Escape
    -- cancels; hiding the page (the options window closes on entering combat)
    -- cancels too. By default it edits the real CUI_RADIAL<n> binding through
    -- CommitKey, theft dialog and all, not a saved key of our own. The palette
    -- index is baked at build time like every other row here -- switching the
    -- edited menu rebuilds the page.
    -- spec is nil for the palette's own keybind. The Select and Cancel keys
    -- pass one:
    --
    --   read()          the chord currently held, or nil
    --   commit(chord)   store it; nil unbinds
    --   plainMouse      allow a bare left-click to bind BUTTON1
    --   intro           what the key does, shown above the how-to-bind text
    --
    -- plainMouse moves where the two gestures live rather than adding one. The
    -- palette's key refuses bare left and right clicks because they keep their
    -- widget meanings -- arm and unbind -- and the Blizzard bindings page
    -- refuses them for the same reason. A bare mouse button is precisely what
    -- a Select key is for, so there the meaning follows the STATE instead of
    -- the button:
    --
    --   resting     left arms the picker, right unbinds
    --   listening   any click is the chord, any key is the chord, Escape backs out
    --
    -- so BUTTON1 and BUTTON2 are both reachable and unbind is still one click.
    -- The wheel stays uncapturable on purpose: a tick cannot be HELD, and hold
    -- is the palette's whole input model -- key down opens, key up fires.
    local function BuildKeybindButton(region, specInfo)
        -- Nothing during the search index prebuild, as BuildMenuSelector.
        if CludesUI._prebuilding then
            return
        end
        local pmenu = editingMenu
        local bindAction = BINDING_PREFIX .. pmenu
        local plainMouse = specInfo and specInfo.plainMouse
        -- BuildPage's own Disabled() is a local of that function and out of
        -- scope here, the same reason BuildMenuSelector reads ProfileGet directly.
        -- A spec may widen the gate and name the requirement for the disabled
        -- tooltip.
        local Disabled = (specInfo and specInfo.disabled)
            or function()
                return ProfileGet("enabled") ~= true
            end

        -- Right-click means two different things on a plainMouse picker
        -- depending on whether it is armed, so it has to say which.
        local tipText = plainMouse
                and CludesUI.L(
                    "Left-click to set a keybind, then press any key or\n"
                        .. "click any mouse button to use it.\n"
                        .. "Escape cancels. Right-click here to unbind."
                )
            or CludesUI.L("Left-click to set a keybind.\nRight-click to unbind.")
        -- The palette's own keybind row sits under a heading that already says
        -- what the key is, but a spec-driven picker has only its label.
        if specInfo and specInfo.intro then
            tipText = CludesUI.L(specInfo.intro) .. "\n\n" .. tipText
        end
        -- A shared key (Assign to Spec) names the menus it is shared with.
        if not specInfo then
            local ownerFrame, nameList = mod.ShareOwner(pmenu), {}
            if ownerFrame then
                nameList[1] = MenuName(ownerFrame)
            else
                for _, sv in ipairs(Sharers(pmenu)) do
                    nameList[#nameList + 1] = MenuName(sv)
                end
            end
            if #nameList > 0 then
                tipText = CludesUI.Lf("Shared with %1$s.", table.concat(nameList, ", ")) .. "\n\n" .. tipText
            end
        end

        local kbBtn = CludesUI.BuildKeybindButton(region, {
            w = 126,
            h = 29,
            level = 4,
            mouse = true,
            plainMouse = plainMouse,
            tooltip = tipText,
            disabled = Disabled,
            disabledTip = (specInfo and specInfo.disabledReason) or "the module",
            -- A menu sharing a key shows the key it shares.
            get = (specInfo and specInfo.read) or function()
                local k1, k2 = GetBindingKey(bindAction)
                if k1 or k2 then
                    return k1, k2
                end
                local ownerFrame = mod.ShareOwner(pmenu)
                if ownerFrame then
                    return GetBindingKey(BINDING_PREFIX .. ownerFrame)
                end
                return nil
            end,
            set = (specInfo and specInfo.commit) or function(keyChord)
                CommitKey(pmenu, keyChord)
            end,
            canArm = function()
                if not InCombatLockdown() then
                    return true
                end
                Complain("Action Wheel: keybinds can't be changed in combat.")
                return false
            end,
        })
        CludesUI.PanelPP.Point(kbBtn, "RIGHT", region, "RIGHT", -20, 0)
        region._lastInline = kbBtn
        return kbBtn
    end

    -- Which slot the cursor is over, for the reorder drag. The live palette's own
    -- HitTest answers this from the angle to the hub, which only means anything
    -- on a circle -- in a fan it would report a entry the user is nowhere near.
    -- Nearest widget CENTRE is the layout-agnostic form of the same question,
    -- and it also follows the strip while it slides.
    local function PreviewDropTarget()
        if not previewWheel:IsFan() then
            return previewWheel:HitTest()
        end

        local isShown = previewWheel:ShownCount()
        if isShown < 1 then
            return nil
        end

        local mx, my = GetCursorPosition()
        local best, bestDist
        for i = 1, isShown do
            local wid = previewWheel:GetSlotWidget(i)
            -- Not folded into an `and`: that truncates to one value and would
            -- drop cy on the floor.
            local cx, cy
            if wid:IsShown() then
                cx, cy = wid:GetCenter()
            end
            if cx then
                -- GetCenter is in the widget's own scaled space; the cursor is
                -- in screen units, so the scale has to be applied to compare.
                local es = wid:GetEffectiveScale()
                local dx, dy = mx - cx * es, my - cy * es
                local d = dx * dx + dy * dy
                if not bestDist or d < bestDist then
                    best, bestDist = i, d
                end
            end
        end
        return best
    end

    -- Installed on the press and cleared on the release, so the block is idle
    -- whenever nothing is being dragged.
    local function PreviewDragUpdate()
        local es = previewWheel:GetFrame():GetEffectiveScale()
        local posX, posY = GetCursorPosition()
        posX, posY = posX / es, posY / es
        if not dragging then
            if
                math.abs(posX - dragStartX) < DRAG_THRESHOLD
                and math.abs(posY - dragStartY) < DRAG_THRESHOLD
            then
                return
            end
            dragging = true
            local wid = previewWheel:GetSlotWidget(dragFrom)
            wid:SetAlpha(0.4)
            wid:SetFrameLevel(previewWheel:GetFrame():GetFrameLevel() + 20)
            HidePreviewTooltip()
        end
        -- The entry under the cursor. The "+" entry resolves to the
        -- last real slot, so dropping there means "move to the end".
        local hit = PreviewDropTarget()
        -- n can reach 0 mid-drag -- right-click removes while the left
        -- button is still held -- and min(hit, 0) is 0, which is TRUTHY
        -- in Lua and would index widget 0.
        local num = previewWheel:SlotCount()
        dragTarget = (hit and num > 0) and math.min(hit, num) or nil
        previewWheel:SetSelection(dragTarget)
    end

    local function EndPreviewDrag()
        if dragFrom then
            local wid = previewWheel:GetSlotWidget(dragFrom)
            wid:SetAlpha(1)
            wid:SetFrameLevel(previewWheel:GetFrame():GetFrameLevel() + 1)
        end
        dragFrom, dragging = nil, false
        if previewHost then
            previewHost:SetScript("OnUpdate", nil)
        end
        previewWheel:SetSelection(nil)
    end

    local function InstallPreviewScripts()
        for i = 1, (mod.MAX_SLOTS or 12) do
            local wid = previewWheel:GetSlotWidget(i)
            wid:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")

            wid:SetScript("OnEnter", function(self)
                if dragging then
                    return
                end
                -- Reuse the selection paint: hovering an entry in the panel looks
                -- exactly like steering onto it in play.
                previewWheel:SetSelection(self.index)
                PreviewTooltip(self)
            end)
            wid:SetScript("OnLeave", function()
                if dragging then
                    return
                end
                previewWheel:SetSelection(nil)
                HidePreviewTooltip()
            end)

            wid:SetScript("OnClick", function(self, btnFrame)
                if btnFrame == "MiddleButton" then
                    if self.isPlaceholder then
                        return
                    end
                    local pmenu = MenuTable(editingMenu)
                    if pmenu and mod.RemoveSlot(pmenu, self.index) then
                        Reapply()
                    end
                    return
                end
                if btnFrame == "RightButton" then
                    -- The picker in replace mode: the pick lands on THIS slot
                    -- (AssignEntry). Nothing to change on the "+" -- its
                    -- left-click already opens the append picker.
                    if self.isPlaceholder then
                        return
                    end
                    TogglePicker(self, self.index)
                    return
                end
                -- A loaded cursor still means "place this here" on every entry;
                -- the picker is the empty-cursor path on the "+" only.
                if self.isPlaceholder and not GetCursorInfo() then
                    TogglePicker(self)
                    return
                end
                PreviewPlace(self)
            end)
            wid:SetScript("OnReceiveDrag", function(self)
                PreviewPlace(self)
            end)

            wid:SetScript("OnMouseDown", function(self, btnFrame)
                if btnFrame ~= "LeftButton" or self.isPlaceholder then
                    return
                end
                -- A loaded cursor means "place this here", not "reorder".
                if GetCursorInfo() then
                    return
                end
                local es = previewWheel:GetFrame():GetEffectiveScale()
                local posX, posY = GetCursorPosition()
                dragStartX, dragStartY = posX / es, posY / es
                dragFrom, dragTarget = self.index, nil
                previewHost:SetScript("OnUpdate", PreviewDragUpdate)
            end)

            -- OnMouseUp is delivered to the frame that got OnMouseDown even when
            -- the cursor has left it, which is what makes the drop work at all.
            wid:SetScript("OnMouseUp", function(self, btnFrame)
                if btnFrame ~= "LeftButton" or dragFrom ~= self.index then
                    return
                end
                local from, to, moved = dragFrom, dragTarget, dragging
                EndPreviewDrag()
                if not moved or not to then
                    return
                end
                local pmenu = MenuTable(editingMenu)
                if pmenu and mod.MoveSlot(pmenu, from, to) then
                    Reapply()
                end
            end)
        end
    end

    -- yPos is the running page offset; returns the height consumed. The
    -- search index prebuild only takes the height: the preview lists nothing.
    local function BuildPreview(hostFrame, yPos)
        if CludesUI._prebuilding then
            return PREVIEW_H
        end
        -- PanelPP, not PP: panel-context geometry snaps to the options window's
        -- own pixel grid, which is what every other options page uses.
        local Pix = CludesUI.PanelPP
        local CONTENT_PAD = CludesUI.CONTENT_PAD or 45

        -- A rebuild re-fans the palette, so the entry the picker is anchored to may
        -- not be the "+" any more -- and an already-open menu would then be
        -- pointing at an unrelated slot.
        HidePicker()

        if not previewHost then
            previewHost = CreateFrame("Frame", nil, hostFrame)
            -- Held by this file across builds: out of its page's frame pool, so
            -- no later dress of the page hands it out for another use, and the
            -- live palette view built on it below stays as it is.
            Pool.Keep(previewHost)
            -- Opted out of the inline search (the RaidFrames overlays'
            -- _searchIgnore, same reason): the search re-anchors collected
            -- children with a single saved point against the WRAPPER it first
            -- saw them in. This block is cached across wrappers and anchored
            -- on BOTH sides with no explicit width, so that restore pins it
            -- to a dead wrapper and collapses it to zero width -- the preview
            -- then stays invisible on every cache-restore path (reopening
            -- after unlock mode, /cqd) until something rebuilds the page.
            previewHost._searchIgnore = true

            local backdrop = previewHost:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            previewHost._bg = backdrop

            previewWheel = mod.CreatePaletteView(previewHost, {
                interactive = true,
                geom = PreviewGeom,
                -- Arrangement is what this preview is for; a live cooldown swipe
                -- on a settings page is only noise.
                showCooldowns = false,
                -- And so is a red icon reporting that the dummy you are not
                -- targeting is out of range of a spell you are only filing.
                showUsability = false,
            })
            previewWheel:GetFrame():SetPoint("CENTER", previewHost, "CENTER", 0, 0)
            InstallPreviewScripts()

            -- The editor strip windows and scrolls exactly like play: the
            -- wheel walks the centre one entry per tick. A plain jump through
            -- SetFanCenter -- the preview is insecure, and the fold in
            -- ApplyFanGeometry does the rest. Direction matches the live
            -- wheel snippet, Invert Scroll included.
            previewHost:EnableMouseWheel(true)
            previewHost:SetScript("OnMouseWheel", function(_, delta)
                -- Shift is the strip's modifier: the block eats the wheel
                -- event either way, so a plain tick is handed to the panel's
                -- own scroll frame and the page keeps scrolling over the
                -- preview. Only Shift+Scroll walks the strip.
                if not IsShiftKeyDown() then
                    local scrollFrame = CludesUI._scrollFrame
                    local handler = scrollFrame and scrollFrame:GetScript("OnMouseWheel")
                    if handler then
                        handler(scrollFrame, delta)
                    end
                    return
                end
                if ProfileGet("enabled") ~= true then
                    return
                end
                if
                    not (previewWheel:IsFan() and not previewWheel:IsGrid() and not previewWheel:IsHoverFan())
                then
                    return
                end
                local isShown = previewWheel.shownCount or 0
                if isShown < 2 then
                    return
                end
                local step = (delta > 0) and -1 or 1
                if MenuGet("fanInvert") == true then
                    step = -step
                end
                previewWheel:SetFanCenter((((previewWheel.fanTarget or 1) - 1 + step) % isShown) + 1)
            end)

            local hint = CludesUI.MakeFont(previewHost, 12, nil, 0.5, 0.5, 0.5)
            hint:SetPoint("BOTTOM", previewHost, "BOTTOM", 0, 7)
            hint:SetText(CludesUI.L("Shift+Scroll to see more"))
            previewHost._scrollHint = hint

            -- A press held while the panel closes under it (Esc, or the combat
            -- auto-hide) would otherwise resume as a phantom drag on reshow.
            previewHost:SetScript("OnHide", function()
                if dragFrom then
                    EndPreviewDrag()
                end
                -- The picker is parented to UIParent, so it does not follow the
                -- panel down by itself. OnHide propagates from the wrapper, so
                -- this covers closing the window and switching page alike.
                HidePicker()
            end)

            -- Blocks the preview outright while the module is off, matching the
            -- disabled overlay the standard rows draw over themselves.
            local size = CreateFrame("Frame", nil, previewHost)
            size:SetAllPoints()
            size:EnableMouse(true)
            local dimTex = size:CreateTexture(nil, "OVERLAY")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0.062, 0.070, 0.082, 0.70)
            size:SetScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, "Enable the module to edit action menus.")
            end)
            size:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            previewHost._dim = size
        end

        previewHost:SetParent(hostFrame)
        -- The block reads as one row of its section's alternation: tick the
        -- same per-parent counter the widget rows use and take whatever shade
        -- this position lands on. A fixed shade only matches until the row
        -- count above changes -- which is not hypothetical, it is how the
        -- icon row's removal left this block the same color as its neighbor.
        local rc = CludesUI._rowCounters
        rc[hostFrame] = (rc[hostFrame] or 0) + 1
        previewHost._bg:SetColorTexture(
            0,
            0,
            0,
            (rc[hostFrame] % 2 == 0) and CludesUI.ROW_BG_EVEN or CludesUI.ROW_BG_ODD
        )
        previewHost:ClearAllPoints()
        -- Anchored on both sides rather than sized from parent:GetWidth(): the
        -- wrapper's own width is not resolved yet on the first build, and this
        -- block is cached, so a zero read would stick for the panel's lifetime.
        Pix.Point(previewHost, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yPos)
        Pix.Point(previewHost, "TOPRIGHT", hostFrame, "TOPRIGHT", -CONTENT_PAD, yPos)
        Pix.Height(previewHost, PREVIEW_H)
        -- Re-asserted per build: an explicit frame level is absolute, and the
        -- block's own level moves when it is re-parented to a fresh wrapper.
        previewHost._dim:SetFrameLevel(previewHost:GetFrameLevel() + 30)
        previewHost._dim:SetShown(ProfileGet("enabled") ~= true)
        previewHost:Show()
        previewWheel:Layout(editingMenu)
        -- A freshly laid out strip sits at its default centre, which is a
        -- position between entries rather than on one. Park it on the first
        -- slot so the preview opens looking like the strip in play does. Only a
        -- SCROLLED strip has a centre at all: the grid and the pointer-steered
        -- fan draw every entry at a fixed position and select by proximity.
        if previewWheel:IsFan() and not previewWheel:IsGrid() and not previewWheel:IsHoverFan() then
            previewWheel:SetFanCenter(1)
        end

        -- Only when there is actually more to scroll to: a palette that fits
        -- inside the window entirely draws every entry already, and the hint
        -- would promise something the wheel cannot deliver.
        local menuT = MenuTable(editingMenu)
        previewHost._scrollHint:SetShown(
            (MenuGet("layout") or "ARC") == "FAN"
                and (menuT and #menuT.slots or 0) > ((MenuGet("fanVisible") or 2) * 2 + 1)
        )

        return PREVIEW_H
    end

    ---------------------------------------------------------------------------
    --  "Apply All Settings From" -- bulk copy between action menus, the Unit
    --  Frames main-frames row re-cut for menus.
    ---------------------------------------------------------------------------
    -- Every appearance key's EFFECTIVE value on the source menu (its own
    -- override, or the shared fallback under it) is written onto the target
    -- as an explicit override, tables deep-copied, so the target draws
    -- exactly what the source draws right now. A menu's actions, name, icon
    -- and keybind are not settings and are never touched.
    local function CopyAllMenuSettings(srcIdx, dstIdx)
        local from = mod.PaletteProfile and mod.PaletteProfile(srcIdx)
        local into = MenuTable(dstIdx)
        local wanted = mod.APPEARANCE_KEYS
        if not (from and into and wanted) then
            return
        end
        local over = into.appearance or {}
        into.appearance = over
        for key in pairs(wanted) do
            local v = from[key]
            over[key] = (type(v) == "table") and CludesUI.Lite.DeepCopy(v) or v
        end
        Reapply()
        CludesUI:RefreshPage(true)
    end

    -- The dim caption in front of each dropdown on the row below the preview.
    local function PairCaption(parent, text)
        local fs = CludesUI.MakeFont(parent, 14, nil, 1, 1, 1)
        fs:SetText(CludesUI.L(text))
        fs:SetTextColor(1, 1, 1, 0.6)
        return fs
    end

    -- "Assign to Spec": the specs the edited menu loads in (palette.specs, a
    -- set of retail spec IDs; none is every spec), on the shared spec list
    -- (CludesUI.SpecPickItems, the Resource Bars picker's rows: one per
    -- class on WoW Forever, whose rows stand for every spec of the class).
    -- Every pick writes at once, then CheckShares and Refresh. A pick that
    -- breaks a share changes keybind buttons the page refresh leaves alone,
    -- so the page rebuilds -- once the menu has closed (a rebuild closes it).
    local function BuildSpecPair(row, ddW)
        local menuIdx = editingMenu
        local ALL = CludesUI.SPEC_PICK_ALL
        local itemList, roles = CludesUI.SpecPickItems({ roles = true })
        local specDD, refreshSpecDD
        -- A pick that broke a share while the list was open rebuilds the
        -- page once the list closes, not under the pointer.
        local rebuildOnClose = false

        -- On WoW Forever a list row stands for a whole class: its spec IDs.
        local function ClassSpecs(key)
            return CludesUI.IS_FOREVER and CludesUI.ForeverClassSpecIDs(key)
        end

        local function IsTicked(key)
            local specs = mod.PaletteSpecs(menuIdx)
            if key == ALL then
                return specs == nil
            end
            if roles[key] then
                return false
            end
            local ids = ClassSpecs(key)
            if not ids then
                return specs ~= nil and specs[key] == true
            end
            if not specs then
                return false
            end
            for n = 1, #ids do
                if not specs[ids[n]] then
                    return false
                end
            end
            return true
        end

        local function OnPick(key, val)
            local menuT = MenuTable(menuIdx)
            if not menuT then
                return
            end
            local role = roles[key]
            if key == ALL or role then
                -- All clears the list (no list is every spec); a role row
                -- sets exactly that role's specs. Either closes the list.
                local chosen = nil
                if role then
                    chosen = {}
                    for n = 1, #role do
                        chosen[role[n]] = true
                    end
                end
                menuT.specs = chosen
                specDD:Click() -- close, as the Resource Bars picker does
            else
                local chosen = menuT.specs or {}
                local mark = val and true or nil
                local ids = ClassSpecs(key)
                if ids then
                    for n = 1, #ids do
                        chosen[ids[n]] = mark
                    end
                else
                    chosen[key] = mark
                end
                menuT.specs = next(chosen) and chosen or nil
            end
            local broke = CheckShares()
            Reapply()
            if refreshSpecDD then
                refreshSpecDD()
            end
            if broke then
                local openList = CludesUI._openDropdownMenu
                if openList and openList:IsShown() then
                    rebuildOnClose = true
                else
                    RedrawPage()
                end
            end
        end

        local function OnListClosed()
            if rebuildOnClose then
                rebuildOnClose = false
                RedrawPage()
            end
        end

        specDD, refreshSpecDD = CludesUI.BuildVisOptsCBDropdown(
            row,
            ddW,
            row:GetFrameLevel() + 2,
            itemList,
            IsTicked,
            OnPick,
            nil,
            10,
            true,
            nil,
            OnListClosed,
            {
                disabled = function()
                    return ProfileGet("enabled") ~= true
                end,
                disabledTooltip = "the module",
            }
        )
        local hint = CludesUI.L("Choose the specs this action menu works in.")
        specDD:HookScript("OnEnter", function()
            local openList = CludesUI._openDropdownMenu
            if not (openList and openList:IsShown()) then
                CludesUI.ShowWidgetTooltip(specDD, hint)
            end
        end)
        specDD:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        CludesUI.RegisterWidgetRefresh(refreshSpecDD)

        return PairCaption(row, "Assign to Spec"), specDD
    end

    -- The row below the preview: Assign to Spec, and with another menu to copy
    -- from (withCopy) the Apply All Settings From pair beside it, both pairs
    -- centred as one line (the mini frames' Apply All Settings From + Copy Look
    -- From row). Apply All Settings From lists the other menus and copies FROM
    -- the chosen one onto the edited menu after a confirm popup; its getValue
    -- always returns the placeholder so the dropdown stores nothing, and the
    -- registered widget refresh snaps the label back after each pick.
    local function BuildApplyRow(hostFrame, posY, withCopy)
        local ROW_HEIGHT = 50
        -- Bespoke controls the search index does not list: its prebuild only
        -- takes the height.
        if CludesUI._prebuilding then
            return ROW_HEIGHT
        end
        local Pix = CludesUI.PanelPP
        local target = editingMenu
        local pad = CludesUI.CONTENT_PAD or 45
        local strip = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(strip, hostFrame:GetWidth() - pad * 2, ROW_HEIGHT)
        Pix.Point(strip, "TOPLEFT", hostFrame, "TOPLEFT", pad, posY)

        local DROP_W, LABEL_GAP, BETWEEN = 180, 12, 40
        -- Each pair is { caption, dropdown }.
        local pairList = { { BuildSpecPair(strip, DROP_W) } }

        if withCopy then
            local names, order = { [""] = "Choose Menu..." }, {}
            for i = 1, MenuCount() do
                if i ~= target then
                    names[i] = MenuName(i)
                    order[#order + 1] = i
                end
            end
            local caption = PairCaption(strip, "Apply All Settings From")
            local fromDD = CludesUI.BuildDropdownControl(
                strip,
                DROP_W,
                strip:GetFrameLevel() + 2,
                names,
                order,
                -- Always the placeholder, so the dropdown itself stores nothing.
                function()
                    return ""
                end,
                function(srcIdx)
                    if srcIdx ~= "" then
                        CludesUI:ShowConfirmPopup({
                            title = "Apply All Settings",
                            message = CludesUI.Lf(
                                "Copy all settings from %1$s to %2$s?",
                                MenuName(srcIdx),
                                MenuName(target)
                            ),
                            disclaimer = "This overwrites this action menu's current settings. Its actions, name, and keybind are not changed.",
                            confirmText = "Apply",
                            cancelText = "Cancel",
                            onConfirm = function()
                                CopyAllMenuSettings(srcIdx, target)
                            end,
                        })
                    end
                end
            )
            fromDD._ttText = "Copy every setting from another action menu to this one."
            -- Snaps the label back to the placeholder after each pick.
            CludesUI.RegisterWidgetRefresh(function()
                fromDD._refreshLabel()
            end)
            pairList[2] = { caption, fromDD }
        end

        -- The pairs centred on the row as one line.
        local width = 0
        for n, pr in ipairs(pairList) do
            width = width + (n > 1 and BETWEEN or 0) + pr[1]:GetStringWidth() + LABEL_GAP + DROP_W
        end
        local prevDD
        for _, pr in ipairs(pairList) do
            if prevDD then
                pr[1]:SetPoint("LEFT", prevDD, "RIGHT", BETWEEN, 0)
            else
                pr[1]:SetPoint("LEFT", strip, "CENTER", -width / 2, 0)
            end
            pr[2]:SetPoint("LEFT", pr[1], "RIGHT", LABEL_GAP, 0)
            prevDD = pr[2]
        end

        return ROW_HEIGHT
    end

    ---------------------------------------------------------------------------
    --  Build Page
    ---------------------------------------------------------------------------
    local function BuildPage(page, hostFrame, yOffset)
        -- The search index prebuild leaves no page behind for the watcher to
        -- keep current, so the watcher waits for the first live build.
        if not CludesUI._prebuilding then
            EnsureBindWatcher()
        end

        local W = CludesUI.Widgets
        local posY = yOffset
        local _, row, hgt

        if CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        -- Not `== false`: the master switch is opt-in, so an absent key counts
        -- as off. The appearance sub-settings below stay nil-means-on.
        local function Disabled()
            return ProfileGet("enabled") ~= true
        end

        -- What this build assumed about nest presence; Refresh compares
        -- against it and escalates to a rebuild when it flips.
        builtWithNest = HasAnyNest()

        -- Which palette is being edited is panel-session state, but the profile
        -- under it can change without one: switching to a profile that holds
        -- fewer palettes repoints the data with no reload, and the module reset
        -- leaves a single palette behind. Clamped here rather than at each
        -- reader because MenuTable, MenuGet and MenuPut all go through
        -- ns.EnsurePalette, which would CREATE the out-of-range palette and
        -- bank that junk in the profile the user has just moved to.
        local paletteCount = MenuCount()
        if editingMenu > paletteCount then
            editingMenu = paletteCount
        end

        local centerValues = { CURSOR = "Cursor", SCREEN = "Fixed Position" }
        local centerOrder = { "CURSOR", "SCREEN" }

        local layoutValues = { ARC = "Arc", FAN = "Fan", GRID = "Grid" }
        local layoutOrder = { "ARC", "FAN", "GRID" }

        local orientValues = { HORIZONTAL = "Horizontal", VERTICAL = "Vertical" }
        local orientOrder = { "HORIZONTAL", "VERTICAL" }

        -----------------------------------------------------------------------
        --  GENERAL
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "GENERAL", posY)
        posY = posY - hgt

        local addPaletteBtn
        row, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "toggle",
                text = "Enable Action Wheel",
                getValue = function()
                    return ProfileGet("enabled") == true
                end,
                setValue = function(v)
                    ProfilePut("enabled", v)
                    RedrawPage()
                end,
            },
            -- The chooser it opens offers an empty palette or a preset. The new
            -- palette takes a key of its own from the keybind row in PALETTE
            -- SETUP, whatever its number.
            {
                type = "labeledButton",
                text = "Add Action Menu",
                disabled = function()
                    return Disabled() or MenuCount() >= MAX_PALETTES
                end,
                disabledTooltip = function()
                    if MenuCount() >= MAX_PALETTES then
                        return "This profile already holds " .. MAX_PALETTES .. " action menus"
                    end
                    return "This option requires the module to be enabled"
                end,
                rawTooltip = true,
                buttonText = "Empty or Preset...",
                -- An upvalue filled in below, not an onClick parameter: the
                -- styled button invokes its handler with no arguments
                -- (CludesUI_Widgets.lua:399), so the chooser has to reach the
                -- frame it anchors under some other way.
                onClick = function()
                    ShowAddPaletteMenu(addPaletteBtn)
                end,
            }
        )
        addPaletteBtn = row._rightRegion and row._rightRegion._control
        posY = posY - hgt

        -----------------------------------------------------------------------
        --  ACTION MENU SETUP
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "ACTION MENU SETUP", posY)
        posY = posY - hgt

        row, hgt = W:DualRow(
            hostFrame,
            posY,
            -- Two label halves: the selector and the keybind button are both
            -- bespoke controls attached below. The selector is the custom
            -- Profiles-style dropdown whose rows carry the inline rename and
            -- delete buttons (panel-session state, never captured); the
            -- keybind button is the shared capture button, which does its
            -- own listening and edits the real CUI_RADIAL<n> binding.
            { type = "label", text = "Editing Action Menu" },
            { type = "label", text = "Action Menu Keybind" }
        )
        BuildMenuSelector(row._leftRegion)
        BuildKeybindButton(row._rightRegion)
        posY = posY - hgt

        -- The Select Key, then the switch that needs it: the key is the
        -- PREREQUISITE (a latched menu nothing can answer would be a trap), so
        -- it binds first and is never gated, and Toggle Menu Open stays
        -- disabled until a key exists. Together on one row because neither
        -- does anything without the other.
        --
        -- The key is one for the profile (ProfilePut) and the switch is per menu
        -- (MenuPut): the gesture that picks an entry should mean the same thing
        -- whichever menu is up.
        local function HasSelectKey()
            local key = ProfileGet("confirmKey")
            return type(key) == "string" and key ~= ""
        end
        row, hgt = W:DualRow(
            hostFrame,
            posY,
            -- A label half, like the keybind row above: the control underneath
            -- is the same bespoke listening button, attached after the row.
            { type = "label", text = "Toggled Menu Select Action" },
            {
                type = "toggle",
                text = "Toggle Menu Open",
                disabled = function()
                    return Disabled() or not HasSelectKey()
                end,
                disabledTooltip = "a Toggled Menu Select Action keybind",
                tooltip = "Keep this menu open when you let go of its keybind.\n"
                    .. "Point at an entry and press the Select Action key to use it.\n"
                    .. "Press the menu's own keybind again, or Escape, to close it.",
                getValue = function()
                    return MenuGet("toggleMode") == true
                end,
                setValue = function(v)
                    MenuPut("toggleMode", v)
                    Reapply()
                end,
            }
        )
        BuildKeybindButton(row._leftRegion, {
            intro = "Uses the entry you are pointing at while a menu is kept "
                .. "open with Toggle Menu Open. One key shared by every menu, "
                .. "claimed only while a menu is up -- a mouse button keeps "
                .. "its normal use the rest of the time.",
            read = function()
                local key = ProfileGet("confirmKey")
                if type(key) ~= "string" or key == "" then
                    return nil
                end
                return key
            end,
            -- "" rather than nil for an unbind: the profile default is a string,
            -- and a nil would simply be re-merged from the defaults table.
            -- RefreshPage as well as Refresh: Toggle Menu Open beside this
            -- takes its disabled state from whether a key is bound.
            commit = function(keyChord)
                ProfilePut("confirmKey", keyChord or "")
                Reapply()
                CludesUI:RefreshPage()
            end,
            -- A bare mouse button is the point of this one. See BuildKeybindButton.
            plainMouse = true,
        })
        posY = posY - hgt

        -- Its opposite, and on a row of its own: nothing else belongs beside a
        -- cancel key. Escape already backs out of any menu and stays that way;
        -- this is a second key for the hand that is holding the menu open and
        -- is nowhere near Escape, which is the whole of the request behind it.
        -- Shown only once the Select key exists: cancelling is a gesture of
        -- the kept-open flow that key unlocks, so before it the row is noise.
        -- The Select commit above already RefreshPage()s on bind/unbind, which
        -- is what brings this row in and out. A cancelKey bound earlier stays
        -- stored while hidden and returns with the row.
        if HasSelectKey() then
            row, hgt = W:DualRow(
                hostFrame,
                posY,
                { type = "label", text = "Menu Cancel Action" },
                { type = "label", text = "" }
            )
            BuildKeybindButton(row._leftRegion, {
                intro = "Closes an open menu without using anything. Escape always "
                    .. "does this as well. One key shared by every menu, claimed "
                    .. "only while a menu is up -- a mouse button keeps its normal "
                    .. "use the rest of the time.",
                read = function()
                    local key = ProfileGet("cancelKey")
                    if type(key) ~= "string" or key == "" then
                        return nil
                    end
                    return key
                end,
                commit = function(keyChord)
                    -- A menu's own key would be taken over for as long as that menu
                    -- was up, which is exactly the moment its release has to reach
                    -- the menu -- so the menu could be opened and never closed. The
                    -- Select key is refused for the reason the module gives at the
                    -- binding itself: one chord, two meanings, and the wrong one
                    -- wins.
                    if keyChord then
                        if keyChord == ProfileGet("confirmKey") then
                            Complain("Action Wheel: that key is already the Toggled Menu Select Action.")
                            return
                        end
                        for i = 1, (ProfileGet("paletteCount") or 1) do
                            if GetBindingKey(BINDING_PREFIX .. i) == keyChord then
                                Complain("Action Wheel: that key opens a menu, so it cannot also close one.")
                                return
                            end
                        end
                    end
                    ProfilePut("cancelKey", keyChord or "")
                    Reapply()
                end,
                -- The same reason as the Select key: a bare mouse button is what
                -- this is for.
                plainMouse = true,
            })
            posY = posY - hgt
        end

        posY = posY - BuildPreview(hostFrame, posY)

        -- Assign to Spec, and beside it Apply All Settings From while there is
        -- another menu to copy from.
        posY = posY - BuildApplyRow(hostFrame, posY, paletteCount > 1)

        -----------------------------------------------------------------------
        --  Row helpers for the two sections below
        --
        --  Nearly every control from here down edits one per-menu value: it
        --  reads through MenuGet with a fallback rule, writes through MenuPut and
        --  then refreshes. PerMenu fills that pair in (a cog row names it
        --  get/set, a page row getValue/setValue, told apart by whether the
        --  spec carries a label) and Gated adds the module switch most of
        --  them dim behind. Put lays a two-half row and moves posY past it.
        -----------------------------------------------------------------------
        local function PerMenu(spec, key, read)
            local function fetch()
                return read(MenuGet(key))
            end
            local function store(v)
                MenuPut(key, v)
                Reapply()
            end
            if spec.label then
                spec.get, spec.set = fetch, store
            else
                spec.getValue, spec.setValue = fetch, store
            end
            return spec
        end
        local function Gated(spec, key, read)
            spec.disabled = spec.disabled or Disabled
            spec.disabledTooltip = spec.disabledTooltip or "the module"
            return PerMenu(spec, key, read)
        end
        local function Or(fallback)
            return function(v)
                return v or fallback
            end
        end
        local function OnUnlessOff(v)
            return v ~= false
        end
        local function OffUnlessOn(v)
            return v == true
        end
        local function Put(left, right)
            local made, height = W:DualRow(hostFrame, posY, left, right)
            posY = posY - height
            return made
        end

        -----------------------------------------------------------------------
        --  LAYOUT
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "LAYOUT", posY)
        posY = posY - hgt

        -- The page keeps the two decisions every menu needs (which layout it
        -- draws as, and where it opens) and the two sizes people reach for
        -- most. Each layout then gets a dial row of its own below: radius
        -- and span for the arc (rotation on the span's cog), direction and
        -- window for the fan (the rest of the strip on the direction's cog),
        -- and the column pair for the grid. The grid alone still puts a cog
        -- on Layout, for its spacing. Picking a layout is a click outside
        -- that cog, which closes it, so its rows never go stale.
        local layoutMode = MenuGet("layout") or "ARC"

        -- In cursor mode the menu opens under the mouse, so the offsets
        -- (the only way to place it: there is no drag editor and no Unlock
        -- Mode entry) sit dead until Fixed Position is picked. Their cog
        -- dims with them, so the row still says they exist.
        local function fixedOnly()
            return Disabled() or (MenuGet("centerMode") or "CURSOR") ~= "SCREEN"
        end
        local function Offset(lbl, key, reach)
            return Gated({
                type = "slider",
                label = lbl,
                min = -reach,
                max = reach,
                step = 1,
                disabled = fixedOnly,
                disabledTooltip = "Fixed Position mode",
            }, key, Or(0))
        end

        row = Put(
            -- Rebuild, not Refresh: the grid's cog beside this dropdown only
            -- exists for the layout picked here.
            {
                type = "dropdown",
                text = "Layout",
                disabled = Disabled,
                disabledTooltip = "the module",
                values = layoutValues,
                order = layoutOrder,
                getValue = function()
                    return MenuGet("layout") or "ARC"
                end,
                setValue = function(v)
                    MenuPut("layout", v)
                    RedrawPage()
                end,
            },
            Gated(
                { type = "dropdown", text = "Open At", values = centerValues, order = centerOrder },
                "centerMode",
                Or("CURSOR")
            )
        )
        if layoutMode == "GRID" then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Grid Settings",
                rows = {
                    Gated(
                        { type = "slider", label = "Spacing", min = 0, max = 40, step = 1 },
                        "fanGap",
                        Or(10)
                    ),
                },
            })
        end
        CludesUI.BuildInlineCog(row._rightRegion, {
            title = "Fixed Position",
            disabled = fixedOnly,
            disabledTooltip = function()
                return Disabled() and "the module" or "Fixed Position mode"
            end,
            rows = {
                Offset("X Offset", "posX", 800),
                Offset("Y Offset", "posY", 600),
            },
        })

        -- The per-layout dial rows. The Layout dropdown rebuilds the page, so
        -- whichever one shows always matches the edited menu.
        if layoutMode == "GRID" then
            Put(
                Gated({ type = "toggle", text = "Auto Columns" }, "gridAutoColumns", OnUnlessOff),
                -- The slider tops out at the slot cap: a grid never draws
                -- more columns than it has entries, so the cap means "one
                -- row" and stays one row as entries are added, while 1 is a
                -- single column. Both single-file shapes live on the one
                -- slider and neither needs a special value.
                Gated({
                    type = "slider",
                    text = "Grid Columns",
                    min = 1,
                    max = MAX_SLOTS,
                    step = 1,
                    disabled = function()
                        return Disabled() or MenuGet("gridAutoColumns") ~= false
                    end,
                    requireState = "disabled",
                    disabledTooltip = "Auto Columns",
                    tooltip = CludesUI.Lf(
                        "How many entries a row of the grid holds. 1 stacks "
                            .. "them into a single column; %1$s -- the most slots an "
                            .. "action menu can hold -- lays them out in a single row.",
                        MAX_SLOTS
                    ),
                }, "gridColumns", Or(4))
            )
        elseif layoutMode == "ARC" then
            local arcRow = Put(
                Gated(
                    { type = "slider", text = "Distance from Center", min = 50, max = 220, step = 1 },
                    "radius",
                    Or(100)
                ),
                Gated(
                    { type = "slider", text = "Arc Span", min = 30, max = 360, step = 5 },
                    "arcSpan",
                    Or(360)
                )
            )
            -- A full circle has nowhere to point, so rotation only comes live
            -- once the span is narrowed. A span edit is a click outside this
            -- popup and closes it, so the check is fresh on every open.
            CludesUI.BuildInlineCog(arcRow._rightRegion, {
                title = "Arc Rotation",
                rows = {
                    Gated({
                        type = "slider",
                        label = "Arc Rotation",
                        min = -180,
                        max = 180,
                        step = 5,
                        disabled = function()
                            return Disabled() or (MenuGet("arcSpan") or 360) >= 360
                        end,
                        disabledTooltip = "an Arc Span below 360",
                    }, "arcRotation", Or(0)),
                },
            })
        elseif layoutMode == "FAN" then
            local fanRow = Put(
                Gated({
                    type = "dropdown",
                    text = "Fan Direction",
                    values = orientValues,
                    order = orientOrder,
                }, "fanOrientation", Or("HORIZONTAL")),
                -- How much of the strip is drawn at all, shown as the whole
                -- odd count (the centre and as many again each side) but
                -- stored as the each-side window, (total - 1) / 2, which is
                -- what every window, hover and snippet test works from.
                {
                    type = "slider",
                    text = "Visible Icons",
                    min = 1,
                    max = 9,
                    step = 2,
                    disabled = Disabled,
                    disabledTooltip = "the module",
                    getValue = function()
                        return ((MenuGet("fanVisible") or 2) * 2) + 1
                    end,
                    setValue = function(v)
                        MenuPut("fanVisible", (v - 1) * 0.5)
                        Reapply()
                    end,
                }
            )
            -- Select Action with Mouse is the strip's hover channel: the entry
            -- under the pointer is what a release fires, and pointing at none
            -- picks nothing. The wheel scrolls the strip either way.
            CludesUI.BuildInlineCog(fanRow._leftRegion, {
                title = "Fan Settings",
                rows = {
                    Gated(
                        { type = "toggle", label = "Select Action with Mouse" },
                        "fanMouseSelect",
                        OnUnlessOff
                    ),
                    Gated(
                        { type = "slider", label = "Spacing", min = 0, max = 40, step = 1 },
                        "fanGap",
                        Or(10)
                    ),
                    Gated({ type = "toggle", label = "Invert Scroll" }, "fanInvert", OffUnlessOn),
                },
            })
        end

        -- Nest geometry, only while some menu really nests another (Refresh
        -- turns into a rebuild when that changes). The cog on Nest Distance
        -- belongs to the edited menu's layout: the arc's shape pair or the
        -- grid's nest style. A fan nest has neither, so it gets no cog.
        if builtWithNest then
            local nestRow = Put(
                Gated({
                    type = "slider",
                    text = "Nest Distance",
                    tooltip = "The gap between a nested menu's icons and the entry " .. "that opens it.",
                    min = 0,
                    max = 160,
                    step = 1,
                }, "nestBand", Or(40)),
                Gated(
                    { type = "slider", text = "Nest Icon Size", min = 0.4, max = 1.0, step = 0.05 },
                    "nestScale",
                    Or(0.8)
                )
            )
            if layoutMode == "ARC" then
                CludesUI.BuildInlineCog(nestRow._leftRegion, {
                    title = "Arc Nest Shape",
                    rows = {
                        Gated({
                            type = "dropdown",
                            label = "Nest Width",
                            tooltip = "How far along the arc a nest may spread its entries."
                                .. " Contained keeps it clear of the next nest either side,"
                                .. " so two of them are never drawn on top of one another."
                                .. " Overflowing lets it use the whole of Max Nest Span."
                                .. " A nest reaches over the plain entries it passes, and"
                                .. " they only give up their angles while it is open.",
                            values = { NONE = "Contained", MIDPOINT = "Overflowing" },
                            order = { "NONE", "MIDPOINT" },
                        }, "arcChildOverflow", Or("NONE")),
                        Gated({
                            type = "slider",
                            label = "Max Nest Span",
                            min = 30,
                            max = 180,
                            step = 5,
                            tooltip = "The widest angle a nest's entries may spread over."
                                .. " They stay on one ring for as long as they fit inside"
                                .. " it; the rest go onto a second ring further out.",
                        }, "arcChildMaxSpan", Or(90)),
                    },
                })
            elseif layoutMode == "GRID" then
                -- Lane hugs the block as a halo centred on the point nearest
                -- the entry that opens it, wrapping corners on a long run;
                -- Halo uses the eight places around the entry itself with
                -- the block faded behind. A value saved from the retired
                -- Popout style reads as Lane, here and in the module.
                CludesUI.BuildInlineCog(nestRow._leftRegion, {
                    title = "Grid Nest Style",
                    rows = {
                        Gated(
                            {
                                type = "dropdown",
                                label = "Grid Nest Style",
                                values = { PERIMETER = "Lane", HALO = "Halo" },
                                order = { "PERIMETER", "HALO" },
                            },
                            "gridNestStyle",
                            function(v)
                                return (v == "HALO") and "HALO" or "PERIMETER"
                            end
                        ),
                    },
                })
            end
        end

        Put(
            Gated({ type = "slider", text = "Icon Size", min = 24, max = 72, step = 1 }, "iconSize", Or(40)),
            Gated({ type = "slider", text = "Scale", min = 0.5, max = 2.0, step = 0.01 }, "scale", Or(1.0))
        )

        -----------------------------------------------------------------------
        --  APPEARANCE
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "APPEARANCE", posY)
        posY = posY - hgt

        Put(
            Gated({ type = "toggle", text = "Show Cooldowns" }, "showCooldowns", OnUnlessOff),
            Gated({
                type = "toggle",
                text = "Dim Unusable Actions",
                tooltip = "Dims any actions you can't use right now.",
            }, "showUsability", OnUnlessOff)
        )

        -- Selection Color is three swatches, accent, custom and class, one
        -- more than the usual look pair: accent by default and read live,
        -- custom holding a colour of its own, class read live from the
        -- player. One is lit at a time and class beats custom, the same
        -- order the module's SelectColor resolves them in. The left half is
        -- a label because the custom swatch is the picker; the search index
        -- prebuild gets the stand-in row only, with nothing to build on.
        row = Put(
            { type = "label", text = "Selection Color" },
            Gated({
                type = "toggle",
                text = "Show Action Text Label",
                tooltip = "Show the selected action's name next to the selected icon.",
            }, "showActionText", OffUnlessOn)
        )
        if not CludesUI._prebuilding then
            local region = row._leftRegion
            local PPQ = CludesUI.PanelPP
            local level = row:GetFrameLevel() + 3

            local function Swatch(read, pick, tip)
                local sw, update = CludesUI.BuildColorSwatch(region, level, read, pick, false, 20)
                sw:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(sw, tip)
                end)
                sw:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                return sw, update
            end
            local function pickAccent()
                MenuPut("selectColorCustom", false)
                MenuPut("useClassColor", false)
                Reapply()
            end
            local function pickClass()
                MenuPut("useClassColor", true)
                Reapply()
            end
            local function guarded(pick)
                return function()
                    if not Disabled() then
                        pick()
                    end
                end
            end

            local customSwatch, updateCustom = Swatch(function()
                local c = MenuGet("selectColor") or {}
                return c[1] or 0.298, c[2] or 0.788, c[3] or 0.941
            end, function(r2, g2, b2)
                MenuPut("selectColor", { r2, g2, b2 })
                MenuPut("selectColorCustom", true)
                MenuPut("useClassColor", false)
                Reapply()
            end, "Custom Color")
            PPQ.Point(customSwatch, "RIGHT", region, "RIGHT", -20, 0)
            -- Until custom is the lit mode, a click only switches to it; the
            -- next click opens the picker, as the window-skin pairs do.
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self2, ...)
                if Disabled() then
                    return
                end
                if MenuGet("selectColorCustom") == true and MenuGet("useClassColor") ~= true then
                    if openPicker then
                        openPicker(self2, ...)
                    end
                    return
                end
                MenuPut("selectColorCustom", true)
                MenuPut("useClassColor", false)
                Reapply()
            end)

            local accentSwatch, updateAccent = Swatch(function()
                return CludesUI.ResolveActiveAccent()
            end, pickAccent, "Accent Color")
            PPQ.Point(accentSwatch, "RIGHT", customSwatch, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", guarded(pickAccent))

            -- The player's class colour, read live like the accent. A click
            -- only picks the mode: the class decides the colour, so there
            -- is no picker behind it.
            local classSwatch, updateClass = Swatch(function()
                local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
                if c then
                    return c.r, c.g, c.b
                end
                return 1, 1, 1
            end, pickClass, "Class Color")
            PPQ.Point(classSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
            classSwatch:SetScript("OnClick", guarded(pickClass))
            region._lastInline = classSwatch

            local function refreshSwatches()
                updateCustom()
                updateAccent()
                updateClass()
                local lit
                if not Disabled() then
                    if MenuGet("useClassColor") == true then
                        lit = classSwatch
                    elseif MenuGet("selectColorCustom") == true then
                        lit = customSwatch
                    else
                        lit = accentSwatch
                    end
                end
                for _, sw in ipairs({ customSwatch, accentSwatch, classSwatch }) do
                    sw:SetAlpha(sw == lit and 1 or 0.3)
                end
            end
            CludesUI.RegisterWidgetRefresh(refreshSwatches)
            refreshSwatches()
        end
        -- There is no Selection Effects cog: the zoom and both falloffs are
        -- switched off in the module (FalloffRatios / SelectedZoom) until the
        -- user's own animation pass.

        -- Toggle World Markers sits beside the filter rather than in ACTION
        -- MENU SETUP because both change what an entry does once the menu is
        -- drawn and both are per menu; it also leaves no half row empty.
        local wmRow = Put(
            Gated({
                type = "toggle",
                text = "Hide Unavailable Actions",
                tooltip = "Hides any actions not available to this character.",
            }, "hideUnusable", OnUnlessOff),
            Gated({
                type = "toggle",
                text = "Toggle World Markers",
                tooltip = "Use a world marker entry again to pick that marker "
                    .. "back up. Off places the marker again, at the new "
                    .. "position.\n"
                    .. "This does not change the entry that clears all world "
                    .. "markers, or the cycling entry.",
            }, "worldMarkerToggle", OnUnlessOff)
        )
        -- Its cog holds the one opt-out: the pip on a placed marker.
        CludesUI.BuildInlineCog(wmRow._rightRegion, {
            title = "World Marker Entries",
            rows = {
                PerMenu({
                    type = "toggle",
                    label = "Show Placed-Marker Pips",
                    tooltip = "Mark a world marker entry whose marker is on the ground with a small corner square, so you can see whether pressing it places or picks up.",
                }, "worldMarkerPip", OnUnlessOff),
            },
        })

        _, hgt = W:Spacer(hostFrame, posY, 10)
        posY = posY - hgt

        return math.abs(posY)
    end

    ---------------------------------------------------------------------------
    --  Slash command
    ---------------------------------------------------------------------------
    SLASH_CUIQUICKDRAW1 = "/cqd"
    SLASH_CUIQUICKDRAW2 = "/quickdraw"
    SlashCmdList.CUIQUICKDRAW = function()
        if InCombatLockdown and InCombatLockdown() then
            print("Cannot open options in combat")
            return
        end
        CludesUI:ShowModule("CludesUIQuickdraw")
    end

    ---------------------------------------------------------------------------
    --  Register the module
    ---------------------------------------------------------------------------
    CludesUI:RegisterModule("CludesUIQuickdraw", {
        title = "Action Wheel",
        description = "Hold a keybind to open a menu of actions; point or scroll to choose, release to fire.",
        pages = { PAGE_DISPLAY },
        buildPage = BuildPage,
        onReset = function()
            -- Lite DB stores data at
            -- CludesUIDB.profiles[X].addons.CludesUIQuickdraw
            if CludesUIDB and CludesUIDB.profiles then
                local profile = CludesUIDB.activeProfile or "Default"
                local p = CludesUIDB.profiles[profile]
                if p and p.addons and p.addons.CludesUIQuickdraw then
                    wipe(p.addons.CludesUIQuickdraw)
                end
            end
            local target = _G._CUQD_AceDB
            if target and target.profile and mod.DB_DEFAULTS then
                CludesUI.Lite.DeepMergeDefaults(target.profile, mod.DB_DEFAULTS.profile)
            end
            if _G._CUQD_Apply then
                _G._CUQD_Apply()
            end
            -- The reset leaves one palette, so the editor cannot stay pointed
            -- at whichever one it was on.
            editingMenu = 1
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
