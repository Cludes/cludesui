if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Rebuild.lua
--
--  Ghost bars, bar visibility, the keybind cache, BuildAllCDMBars and
--  FullCDMRebuild.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ALL_RACIAL_SPELLS, ECME = Inner.ALL_RACIAL_SPELLS, Inner.ECME
local EffectiveBarAlpha, FC = Inner.EffectiveBarAlpha, Inner.FC
local IsPlaceholderRenderHidden = Inner.IsPlaceholderRenderHidden
local ResolveActiveRacial, _cdmKeybindCache = Inner.ResolveActiveRacial, Inner._cdmKeybindCache
local _cdmKeybindRank, _cdmViewerNames = Inner._cdmKeybindRank, Inner._cdmViewerNames
local _ecmeFC, _getFD, GHOST_CD_BAR_KEY = Inner._ecmeFC, Inner._getFD, Inner.GHOST_CD_BAR_KEY
local MAIN_BAR_KEYS, ResolveChildSpellID = Inner.MAIN_BAR_KEYS, Inner.ResolveChildSpellID
local ResolveInfoSpellID, barDataByKey = Inner.ResolveInfoSpellID, Inner.barDataByKey
local cdmBarFrames, cdmBarIcons = Inner.cdmBarFrames, Inner.cdmBarIcons
local BLIZZ_CDM_FRAMES, CDM_BAR_CATEGORIES = Inner.BLIZZ_CDM_FRAMES, Inner.CDM_BAR_CATEGORIES
local EnforceCooldownViewerEditModeSettings = Inner.EnforceCooldownViewerEditModeSettings
local GetCDMFont, HideBlizzardCDM = Inner.GetCDMFont, Inner.HideBlizzardCDM
local MAX_CUSTOM_BARS, RestoreBlizzardBuffFrame = Inner.MAX_CUSTOM_BARS, Inner.RestoreBlizzardBuffFrame
local RestoreBlizzardCDM = Inner.RestoreBlizzardCDM
local ApplyBarPositionCentered = Inner.ApplyBarPositionCentered
local ApplyCDMTooltipState, BuildCDMBar = Inner.ApplyCDMTooltipState, Inner.BuildCDMBar
local ComputeTopRowStride, LayoutCDMBar = Inner.ComputeTopRowStride, Inner.LayoutCDMBar
local SaveCDMBarPosition = Inner.SaveCDMBarPosition
local RefreshCDMIconAppearance = Inner.RefreshCDMIconAppearance
local EnsureFocusKickBar, FOCUSKICK_BAR_KEY = Inner.EnsureFocusKickBar, Inner.FOCUSKICK_BAR_KEY

local BuildAllCDMBars
local _CDMApplyVisibility

local _cdmInVehicle = false
Inner.SetCdmInVehicle = function(val)
    _cdmInVehicle = val
end
local _inCombat = false
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val)
    _inCombat = val
end

-- Ghost bars: ensure both buff and CD ghost bars exist in the bars array. Called from BuildAllCDMBars before iterating bars.
mod.GHOST_CD_BAR_KEY = GHOST_CD_BAR_KEY
local function EnsureGhostBars()
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then
        return
    end
    local hasCD = false
    for _, b in ipairs(p.cdmBars.bars) do
        if b.key == GHOST_CD_BAR_KEY then
            hasCD = true
        end
    end
    if not hasCD then
        p.cdmBars.bars[#p.cdmBars.bars + 1] = {
            key = GHOST_CD_BAR_KEY,
            name = "Hidden CDs",
            barType = "cooldowns",
            isGhostBar = true,
            enabled = true,
            barVisibility = "never",
            iconSize = 1,
            spacing = 0,
            numRows = 1,
            growDirection = "RIGHT",
        }
    end
end
mod.EnsureGhostBars = EnsureGhostBars

-- Exports for extracted files (CludesUICdmHooks.lua and CUI_CDM_Hook*.lua, CludesUICdmSpellPicker.lua)
mod.MAIN_BAR_KEYS = MAIN_BAR_KEYS
mod.GetCDMFont = GetCDMFont
mod.ResolveInfoSpellID = ResolveInfoSpellID
mod.ResolveChildSpellID = ResolveChildSpellID
mod.ComputeTopRowStride = ComputeTopRowStride
-- Side-effect caches are now owned by CUI_CDM_HookIconStyle.lua. The hook files write to ns._tick*
-- tables directly; these locals are populated from ns after the hook files load (in CDMFinishSetup). The ns._ecmeFC external frame cache is still owned by this file.
mod._ecmeFC = _ecmeFC
mod.FC = FC

-- Hook-based CDM Backend loaded from CludesUICdmHooks.lua and the CUI_CDM_Hook*.lua files
local BuildCustomBarSpellSet -- forward declare (defined below)

-------------------------------------------------------------------------------
--  Build a set of all spellIDs assigned to custom bars.
--  Used to prevent custom bar spells from leaking onto main bars during
--  snapshot or reconcile.
-------------------------------------------------------------------------------
BuildCustomBarSpellSet = function()
    local set = {}
    local p = ECME.db and ECME.db.profile
    if not p or not p.cdmBars or not p.cdmBars.bars then
        return set
    end
    for _, edge in ipairs(p.cdmBars.bars) do
        if not MAIN_BAR_KEYS[edge.key] then
            local sd = mod.GetBarSpellData(edge.key)
            if sd and sd.assignedSpells then
                for _, spellRef in ipairs(sd.assignedSpells) do
                    if spellRef and spellRef > 0 then
                        set[spellRef] = true
                    end
                end
            end
        end
    end
    return set
end
mod.BuildCustomBarSpellSet = BuildCustomBarSpellSet

-- (SnapshotBlizzardCDM / UpdateTrackedBarIcons removed -- replaced by hook-based CollectAndReanchor)

-- UpdateAllCDMBars: REMOVED. All recurring work is event-driven via hooks in CUI_CDM_HookViewers.lua
-- -- CollectAndReanchor runs only when Blizzard fires OnCooldownIDSet, OnActiveStateChanged, Layout, or pool events. The stub exists only so any stale references don't error.
local function UpdateAllCDMBars(dt) end

-------------------------------------------------------------------------------
--  Bar Visibility (always / in combat / never) + Housing
-------------------------------------------------------------------------------

-- Does this cd/utility bar draw any frame out of the BuffIcon viewer? True for a
-- hosted buff (spellID-keyed) and for a cd-claimed collided buff slot. Called
-- only for the BuffIcon viewer's vote below, so bars pay nothing in the common
-- case where nothing is hosted. On ns, not a file local: this file sits at
-- Lua's 200-local cap.
function mod.BarUsesBuffViewer(barId)
    -- "Replace with Buff" frames come out of the BuffIcon pool too (route map
    -- Pass 3c records the bars); gated so non-users pay one boolean.
    if mod._cdmAnyBuffReplace and mod._buffReplaceBars and mod._buffReplaceBars[barId] then
        return true
    end
    local sd = mod.GetBarSpellData and mod.GetBarSpellData(barId)
    if not sd then
        return false
    end
    if sd.hostedBuffSpellIDs and next(sd.hostedBuffSpellIDs) then
        return true
    end
    return (mod.CollectCdClaimSet and mod.CollectCdClaimSet(sd)) and true or false
end

_CDMApplyVisibility = function()
    local p = ECME.db and ECME.db.profile
    if not p then
        return
    end
    local inCombat = _inCombat
    -- Full vehicle UI: hide all bars
    local inVehicle = _cdmInVehicle
    -- Group state for mode checks
    local inRaid = IsInRaid and IsInRaid() or false
    local inParty = not inRaid and (IsInGroup and IsInGroup() or false)

    -- One state table per pass for the multi-select visibility engine
    local visState = { inCombat = inCombat, inRaid = inRaid, inParty = inParty }

    local unlockActive = CludesUI._unlockActive

    for _, barInfo in ipairs(p.cdmBars.bars) do
        local widget = cdmBarFrames[barInfo.key]
        if widget then
            -- FocusKick is owned exclusively by ApplyFocusKickAnchor. Don't touch its alpha or
            -- icons here -- the visibility check runs on unrelated events (combat enter/exit, vehicle, etc.) and would clobber the nameplate-driven show/hide state.
            if barInfo.key == FOCUSKICK_BAR_KEY then
                -- intentionally skipped
                -- Unlock mode: bars must stay visible for dragging
                -- Ghost bar stays hidden even in unlock mode
            elseif unlockActive and not barInfo.isGhostBar then
                widget:SetAlpha(1)
                -- Container stays motion-through even in unlock mode; drag handling lives on the unlock overlay frames, not the bar.
                if widget.EnableMouseMotion and not InCombatLockdown() then
                    widget:EnableMouseMotion(false)
                end
                widget._visHidden = false
            else
                local vis = barInfo.barVisibility or "always"
                local shouldHide = false

                -- Multi-select/dragonriding path: non-nil owns the mode step (priority 3); the legacy single-mode chain below is untouched.
                local visExt = CludesUI.EvalVisibilityExtended(
                    barInfo,
                    "barVisibility",
                    visState,
                    CludesUI.VIS_CAPS_DEFAULT
                )

                -- Priority 1: vehicle always hides
                if inVehicle then
                    shouldHide = true
                -- Priority 2: visibility options (checkbox dropdown)
                elseif CludesUI.CheckVisibilityOptions(barInfo) then
                    shouldHide = true
                -- Priority 3: visibility mode (multi-select or dragonriding scalar)
                elseif visExt ~= nil then
                    shouldHide = not visExt
                elseif vis == "never" then
                    shouldHide = true
                elseif vis == "in_combat" then
                    shouldHide = not inCombat
                elseif vis == "out_of_combat" then
                    shouldHide = inCombat
                elseif vis == "in_raid" then
                    shouldHide = not inRaid
                elseif vis == "in_party" then
                    shouldHide = not inParty
                elseif vis == "solo" then
                    shouldHide = inRaid or inParty
                end

                if shouldHide then
                    widget:SetAlpha(0)
                    if widget.EnableMouseMotion and not InCombatLockdown() then
                        widget:EnableMouseMotion(false)
                    end
                    widget._visHidden = true
                    -- Cursor bars: park immediately on the hide edge. The glue shell self-sleeps on its next frame, so this is the one guaranteed park before it stops watching.
                    if widget._mouseTrack and (widget:GetLeft() or 0) > -9000 then
                        widget._mouseParked = true
                        widget:ClearAllPoints()
                        widget:SetPoint(widget._mousePoint or "LEFT", UIParent, "BOTTOMLEFT", -10000, -10000)
                    end
                    -- Hide this bar's icons individually. The viewer may stay at alpha 1 (other bars
                    -- need it), so icon alpha must be managed per-bar. EnableMouse is protected on Blizzard CDM frames; gate on combat lockdown to avoid ADDON_ACTION_BLOCKED.
                    local icons = cdmBarIcons[barInfo.key]
                    local icCombat = InCombatLockdown()
                    if icons then
                        for ii = 1, #icons do
                            local ic = icons[ii]
                            if ic then
                                ic:SetAlpha(0)
                                if not icCombat then
                                    ic:EnableMouse(false)
                                end
                            end
                        end
                    end
                else
                    local wasHidden = widget._visHidden
                    -- Bar opacity is applied to icons only, not the frame. Custom injected icons are parented to the bar frame, so frame alpha would double-apply with icon alpha.
                    widget:SetAlpha(1)
                    -- The container never captures mouse motion: its rect spans the bar's full layout
                    -- area, and a motion-enabled frame with no unit steals mouseover focus from unit frames underneath (hover highlights + [@mouseover] casts die under the bar). Icon hover is per-icon below, gated on the tooltip setting.
                    if widget.EnableMouseMotion and not InCombatLockdown() then
                        widget:EnableMouseMotion(false)
                    end
                    widget._visHidden = false
                    -- Cursor bars: resume the glue subscription the vis-hidden watch released; the resume snaps to the cursor immediately instead of waiting for the next 0.15s watch fire.
                    if widget._mouseTrack and widget._mouseResume then
                        widget._mouseResume()
                    end
                    -- Apply opacity to icons every pass (idempotent, handles fresh loads where wasHidden is false). EffectiveBarAlpha folds in the out-of-combat fade when that option is on.
                    local visAlpha = EffectiveBarAlpha(barInfo)
                    local icons = cdmBarIcons[barInfo.key]
                    local icCombat2 = InCombatLockdown()
                    if icons then
                        for ii = 1, #icons do
                            local ic = icons[ii]
                            if ic then
                                local phHidden = IsPlaceholderRenderHidden(ic, barInfo)
                                -- EnableMouse/EnableMouseMotion are protected on Blizzard CDM frames; skip during combat to avoid ADDON_ACTION_BLOCKED when dismounting mid-combat.
                                if not icCombat2 then
                                    ic:EnableMouse(false)
                                    -- Same mouseover-stealing rule as the container above: icons may only
                                    -- capture mouse motion when this bar's tooltips are on, and never on cursor-tracked bars (those must stay fully click-AND-motion-through).
                                    -- An invisible placeholder never captures: there is nothing drawn to hover.
                                    if ic.EnableMouseMotion then
                                        ic:EnableMouseMotion(
                                            (barInfo.showTooltip and not widget._mouseTrack and not phHidden)
                                                    and true
                                                or false
                                        )
                                    end
                                end
                                local icfc = _ecmeFC[ic]
                                if phHidden then
                                    -- Hide Icon: an Always-Show placeholder keeps its reserved layout slot but stays fully invisible (icon, border, bg).
                                    ic:SetAlpha(0)
                                elseif not (icfc and (icfc._cdStateHidden or icfc._missingActiveHidden)) then
                                    ic:SetAlpha(visAlpha)
                                end
                            end
                        end
                    end
                    if wasHidden then
                        -- Defer to a clean execution context: event handlers (PLAYER_TARGET_CHANGED, mount
                        -- events, etc.) can carry taint from the Blizzard dispatch chain. LayoutCDMBar calls SetSize/SetPoint which propagates the taint and triggers ADDON_ACTION_BLOCKED.
                        local bk = barInfo.key
                        C_Timer.After(0, function()
                            LayoutCDMBar(bk)
                        end)
                    end
                end
            end -- unlockActive else
            -- Aura-tracked custom buffs render on a UIParent holder that mirrors
            -- the bar's alpha in its anchor pass; alpha edges fire no frame
            -- hooks, so poke it (no-op for bars without such buffs).
            if mod._AuraCustomPoke then
                mod._AuraCustomPoke(barInfo.key)
            end
        end
    end

    -- Viewer alpha: icons are parented to Blizzard viewers and inherit their alpha. Only hide a
    -- viewer if ALL bars that use its icons are hidden. Otherwise a hidden default bar (e.g. "buffs" set to "never") would kill icons on visible custom bars that share the same viewer.
    for viewerBarKey, viewerName in pairs(BLIZZ_CDM_FRAMES) do
        local viewer = _G[viewerName]
        if viewer then
            -- The viewer must stay visible if ANY bar that uses its icons is visible (each bar has
            -- independent visibility). Mapping: cooldowns/utility bars use the Essential/Utility viewers; buff bars use the BuffIcon viewer; custom_buff (aura timer) bars use their own frames, not a viewer.
            local anyVisible = false
            for _, barInfo in ipairs(p.cdmBars.bars) do
                if barInfo.enabled then
                    local widget = cdmBarFrames[barInfo.key]
                    if widget and not widget._visHidden then
                        local bk = barInfo.key
                        if bk == viewerBarKey then
                            anyVisible = true
                            break
                        end
                        local bt = barInfo.barType
                        if bt ~= "custom_buff" then
                            if bt == "buffs" and viewerBarKey == "buffs" then
                                anyVisible = true
                                break
                            elseif
                                bt ~= "buffs" and (viewerBarKey == "cooldowns" or viewerBarKey == "utility")
                            then
                                anyVisible = true
                                break
                            -- A HOSTED buff renders on a cd/utility bar but its frame
                            -- still comes out of the BuffIcon viewer pool and is never
                            -- reparented, so it inherits that viewer's alpha. Without
                            -- this vote a visible cd/utility bar hosting a buff went
                            -- dark the moment the buffs bar was hidden: the aura-down
                            -- placeholder (our own frame, parented to UIParent) kept
                            -- rendering while the live buff did not.
                            elseif
                                bt ~= "buffs"
                                and viewerBarKey == "buffs"
                                and mod.BarUsesBuffViewer(barInfo.key)
                            then
                                anyVisible = true
                                break
                            end
                        end
                    end
                end
            end
            viewer:SetAlpha(anyVisible and 1 or 0)
        end
    end
end
mod.CDMApplyVisibility = _CDMApplyVisibility
_G._CUCME_ApplyVisibility = _CDMApplyVisibility

-- Live-apply bar opacity to a bar's frame + icons. Skips hidden bars so visibility state is never overridden (hidden stays at alpha 0).
local function ApplyBarOpacity(barId)
    local widget = cdmBarFrames[barId]
    if not widget or widget._visHidden then
        return
    end
    local barInfo = barDataByKey[barId]
    if not barInfo then
        return
    end
    if barId == FOCUSKICK_BAR_KEY then
        return
    end
    local a = EffectiveBarAlpha(barInfo)
    local icons = cdmBarIcons[barId]
    if icons then
        for idx = 1, #icons do
            local ic = icons[idx]
            if ic then
                local icfc = _ecmeFC[ic]
                if IsPlaceholderRenderHidden(ic, barInfo) then
                    -- Hide Icon: an Always-Show placeholder keeps its reserved
                    -- layout slot but stays fully invisible (icon, border, bg).
                    ic:SetAlpha(0)
                elseif not (icfc and (icfc._cdStateHidden or icfc._missingActiveHidden)) then
                    ic:SetAlpha(a)
                end
            end
        end
    end
    -- The aura-tracked custom buff holder mirrors this opacity in its anchor pass.
    if mod._AuraCustomPoke then
        mod._AuraCustomPoke(barId)
    end
end
mod.ApplyBarOpacity = ApplyBarOpacity

-- Helper to get barData by key
local function GetBarData(barId)
    return barDataByKey[barId]
end
mod.GetBarData = GetBarData

-------------------------------------------------------------------------------
--  Keybind cache for CDM icons
--  Resolves binding keys per action slot. In Stable mode, the main bar is
--  scanned across home page + bonus pages (forms/stealth/skyriding), so the
--  cache does not follow bar swaps and a key only changes when the player
--  moves the ability or rebinds it. Manually-paged pages 2-6 are excluded --
--  their contents aren't reliably something the player set up on purpose.
--  Read-only + text writes on our own frames, so it is safe to run in combat
--  (debounced upstream).
-------------------------------------------------------------------------------

-- Forward-declared: everything else in this section lives inside the do-block
-- below so its locals are freed again. This file is at the Lua 5.1 200-local
-- ceiling for the main chunk, and the multi-page scan needs several helpers.
local UpdateCDMKeybinds
do
    -- Action bar slot -> binding name map, with the priority tier each source
    -- feeds into _SetKeybind (lower wins). Tiers ascend with bar number, so a
    -- spell bound on multiple bars shows the lowest-numbered bar's key -- the one
    -- most players expect.
    -- The main bar (ACTIONBUTTON1-12) is not listed here -- it needs per-page slot
    -- math and is scanned separately below.
    local _barBindingDefs = {
        { prefix = "MULTIACTIONBAR1BUTTON", startSlot = 61, tier = 2 }, -- bar 2 bottom left
        { prefix = "MULTIACTIONBAR2BUTTON", startSlot = 49, tier = 3 }, -- bar 3 bottom right
        { prefix = "MULTIACTIONBAR3BUTTON", startSlot = 25, tier = 4 }, -- bar 4 right
        { prefix = "MULTIACTIONBAR4BUTTON", startSlot = 37, tier = 5 }, -- bar 5 left
        { prefix = "MULTIACTIONBAR5BUTTON", startSlot = 145, tier = 6 }, -- bar 6
        { prefix = "MULTIACTIONBAR6BUTTON", startSlot = 157, tier = 7 }, -- bar 7
        { prefix = "MULTIACTIONBAR7BUTTON", startSlot = 169, tier = 8 }, -- bar 8
        -- CUI bars 9/10 have no native binding command: their keys are routed
        -- through the button with SetOverrideBindingClick against the custom
        -- commands declared in the Action Bars module's Bindings.xml. Because that
        -- route always reads the button's live "action" attr, resolve the slot from
        -- the button when it exists and only fall back to the base page slot when
        -- the Action Bars module is not loaded (handled where this def is consumed).
        { prefix = "CUI_BAR9_BUTTON", startSlot = 13, tier = 9, eabButton = true }, -- bar 9  (action page 2)
        { prefix = "CUI_BAR10_BUTTON", startSlot = 109, tier = 10, eabButton = true }, -- bar 10 (action page 10)
    }

    -- Main-bar tiers. Page 1 is bar 1 -- tier 1, ahead of every other bar (see
    -- above). Bonus pages (form/stealth/skyriding) rank last: they're situational,
    -- not an explicit per-bar assignment like the tiers above.
    -- RULING (2026-09-17): lowest bar number wins, deliberately over the earlier
    -- "dedicated bar first" order. Accepted cost: in stable mode a spell that sits
    -- on page 1 AND a dedicated bar labels page 1's key even while a bonus page is
    -- active, when only the dedicated bar's key would fire. Do not flip it back.
    --
    -- Pages 2-6 (manual paging, e.g. Shift+MouseWheel -- a stock WoW binding, not
    -- an EAB-specific feature) are deliberately NOT scanned. Unlike page 1 and the
    -- bonus pages, nothing guarantees their contents are something the player
    -- actually curated: WoW keeps whatever was last placed there (leftovers from
    -- a previous bar addon, a default-populated slot, an accidental scroll) and
    -- GetActionInfo returns it regardless. Root-caused 2026-08-07: a tracked,
    -- genuinely unbound Utility spell showed a phantom "CR" key because slot 11
    -- of page 6 -- never intentionally used -- happened to hold something under
    -- the ACTIONBUTTON11 binding. Since the tracked spell had no other entry,
    -- that stray page-6 read became its only (wrong) answer. Multibars and bonus
    -- pages don't have this problem: multibars are explicit EAB bar assignments,
    -- and bonus pages are gated by real, meaningful game state (stealth/form/
    -- skyriding), not "whatever a stray scroll last revealed."
    local _TIER_MAINBAR_HOME = 1 -- page 1        -> slots 1-12
    local _TIER_MAINBAR_BONUS = 11 -- pages 7-11    -> slots 73-132  (+ pg - 7)
    -- A macro-sourced bind is always outranked by a direct one, whatever the bar.
    local _RANK_MACRO_PENALTY = 100

    -- Whether this rebuild runs in stable mode. Latched once per rebuild rather
    -- than re-read per slot, and gates BOTH halves of the feature: the multi-page
    -- main bar scan and the macro body scan. With the option off, every path below
    -- must behave exactly as it did before the feature existed.
    local _stableMode = false

    local function FormatKeybindKey(key)
        if not key or key == "" then
            return nil
        end
        -- Gamepad binds resolve to glyph markup (no atlas name matches a substitution
        -- below); keyboard binds keep the raw tokens the substitutions are written against.
        local resolved = GetBindingText(key, 1)
        if resolved and resolved:find("|A:", 1, true) then
            key = resolved
        end
        key = key:gsub("SHIFT%-", "S")
        key = key:gsub("CTRL%-", "C")
        key = key:gsub("ALT%-", "A")
        key = key:gsub("META%-", "M") -- Mac Command key (CMD-E -> ME)
        key = key:gsub("Mouse Button ", "M")
        key = key:gsub("MOUSEWHEELUP", "MwU")
        key = key:gsub("MOUSEWHEELDOWN", "MwD")
        key = key:gsub("CAPSLOCK", "Caps")
        key = key:gsub("NUMPADDECIMAL", "N.")
        key = key:gsub("NUMPADPLUS", "N+")
        key = key:gsub("NUMPADMINUS", "N-")
        key = key:gsub("NUMPADMULTIPLY", "N*")
        key = key:gsub("NUMPADDIVIDE", "N/")
        key = key:gsub("NUMPAD", "N")
        key = key:gsub("BUTTON", "M")
        return key ~= "" and key or nil
    end

    -- Store a keybind under a cache key, best-rank-wins. The rank encodes both
    -- which bar/page the bind came from (see the tier constants above) and
    -- macro-deprioritization: a direct (non-macro) bind always beats a macro one,
    -- whatever bar each sits on, so a user who has both a macro and the real spell
    -- bound sees the real spell's key. Equal rank keeps the first writer, which
    -- preserves scan order within a single bar.
    local function _SetKeybind(cacheKey, formatted, rank)
        if not formatted then
            return
        end
        local current = _cdmKeybindRank[cacheKey]
        if current == nil or rank < current then
            _cdmKeybindCache[cacheKey] = formatted
            _cdmKeybindRank[cacheKey] = rank
        end
    end

    -- Cache a spell under every id an icon might present it as: the id itself,
    -- its name, and its override/base partners. A nil id is a no-op -- callers
    -- hand through whatever GetActionInfo/GetMacroSpell returned, and writing a
    -- nil cache key would be a hard error.
    local function _SetSpellKeybind(spellId, formatted, rank)
        if not spellId then
            return
        end
        _SetKeybind(spellId, formatted, rank)
        local name = C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
        if name then
            _SetKeybind(name, formatted, rank)
        end
        local ovr = C_Spell.GetOverrideSpell and C_Spell.GetOverrideSpell(spellId)
        if ovr and ovr ~= spellId then
            _SetKeybind(ovr, formatted, rank)
        end
        local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellId)
        if base and base ~= spellId then
            _SetKeybind(base, formatted, rank)
        end
    end

    -- Macro commands whose arguments are a list of cast/use targets. English only:
    -- localized aliases (/zauber, ...) exist but the English commands work on every
    -- client and are what the overwhelming majority of macros use.
    local _MACRO_CAST_CMDS = {
        cast = true,
        castsequence = true,
        castrandom = true,
        use = true,
        userandom = true,
    }

    -- One target token out of a macro's cast list.
    local function _RegisterMacroTarget(token, formatted, rank)
        -- Drop a leading castsequence reset clause ("reset=combat/5 Spell").
        token = token:gsub("^reset=%S*%s*", "")
        if token == "" then
            return
        end
        -- "item:NNNN" is macro-only shorthand for targeting an itemID directly. It
        -- is NOT a valid GetItemInfoInstant input (that wants a bare itemID, item
        -- name, or a full item link) -- pull the numeric ID out ourselves instead
        -- of handing the literal "item:NNNN" string to it.
        local itemId = token:match("^item:(%d+)")
        if itemId then
            _SetKeybind(-tonumber(itemId), formatted, rank)
            return
        end
        local spellRef = token:match("^spell:(%d+)")
        if spellRef then
            _SetSpellKeybind(tonumber(spellRef), formatted, rank)
            return
        end
        -- A bare number is ambiguous in macro syntax (inventory slot vs itemID). The
        -- equipment slots are 1..19 and no usable item carries an id that low, so a
        -- number in that range is the slot form ("/use 13"): bind the item equipped
        -- there (the cache rebuilds with the bars on every equipment change). Any
        -- other number is left alone rather than guessed at.
        local slotNum = token:match("^(%d+)$")
        if slotNum then
            slotNum = tonumber(slotNum)
            if slotNum >= 1 and slotNum <= 19 then
                local slotItem = GetInventoryItemID("player", slotNum)
                if slotItem then
                    _SetKeybind(-slotItem, formatted, rank)
                end
            end
            return
        end
        if tonumber(token) then
            return
        end
        -- Leftover bracket means the body had an unbalanced [condition] that the
        -- %b[] strip could not remove. Whatever is left is not a usable name.
        if token:find("[%[%]]") then
            return
        end
        -- Store the raw name too: ApplyCachedKeybinds falls back to a name lookup,
        -- which still hits when the spell itself cannot be resolved right now.
        _SetKeybind(token, formatted, rank)
        local ident = C_Spell.GetSpellIDForSpellIdentifier and C_Spell.GetSpellIDForSpellIdentifier(token)
        if ident then
            _SetSpellKeybind(ident, formatted, rank)
        else
            local iid = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(token)
            if iid then
                _SetKeybind(-iid, formatted, rank)
            end
        end
    end

    -- Register every branch of a macro body, not just the one that is live now.
    --
    -- This is the second half of the bar-swap problem, and it is independent of
    -- paging: Blizzard's own resolution (GetMacroSpell, and the "smart" macro
    -- subType) evaluates the macro's conditionals against the CURRENT state. So
    --     #showtooltip Shadow Dance
    --     /cast [bonusbar:1] Backstab; Shadow Dance
    -- reports Shadow Dance while unstealthed and Backstab while stealthed -- and
    -- Shadow Dance loses its key the moment the rogue stealths, with the action
    -- slot itself never changing. Parsing the body registers both branches, so
    -- the key sticks to whichever one the CDM icon happens to show.
    local function _RegisterMacroTargets(body, formatted, rank)
        for line in body:gmatch("[^\r\n]+") do
            local cmd, args = line:match("^%s*/(%a+)!?%s*(.*)$")
            if cmd and args ~= "" and _MACRO_CAST_CMDS[cmd:lower()] then
                -- Each ";"-separated clause is one conditional branch; a
                -- castsequence packs several targets into one clause via ",".
                for clause in args:gmatch("[^;]+") do
                    -- Drop the [condition] groups -- every branch counts here.
                    clause = clause:gsub("%b[]", "")
                    for token in clause:gmatch("[^,]+") do
                        token = token:match("^%s*!?%s*(.-)%s*$")
                        if token and token ~= "" then
                            _RegisterMacroTarget(token, formatted, rank)
                        end
                    end
                end
            end
        end
    end

    -- Legacy fallback for a macro that GetMacroSpell could not resolve: pull the
    -- first /use target out of the body and register it as an item. Kept verbatim
    -- so the option-off path stays byte-for-byte the pre-feature behaviour; the
    -- stable path uses the full body scan above instead.
    local function _RegisterLegacyMacroItem(macroIndex, formatted, rank)
        local body = GetMacroBody and GetMacroBody(macroIndex)
        local target = body and body:match("/use!?%s+([^\r\n]+)")
        if not target then
            return
        end
        target = target:gsub("^%[.-%]%s*", ""):match("^%s*(.-)%s*$")
        local itemId = target:match("^item:(%d+)")
        itemId = itemId and tonumber(itemId)
        if not itemId and not tonumber(target) then
            itemId = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(target)
        end
        -- Bare 1..19 is the equipment-slot form (see _RegisterMacroTarget).
        if not itemId then
            local slotNum = target:match("^(%d+)$")
            slotNum = slotNum and tonumber(slotNum)
            if slotNum and slotNum >= 1 and slotNum <= 19 then
                itemId = GetInventoryItemID("player", slotNum)
            end
        end
        if itemId then
            _SetKeybind(-itemId, formatted, rank)
        end
    end

    -- Resolve one action slot under one binding key into cache entries, at the
    -- given priority tier. Pure lookups plus writes into the two cache tables.
    local function _ResolveSlotBinding(slot, key, tier)
        local formatted = FormatKeybindKey(key)
        if not formatted then
            return
        end
        local macroRank = tier + _RANK_MACRO_PENALTY
        local slotType, ident, subType = GetActionInfo(slot)
        if slotType == "spell" then
            _SetSpellKeybind(ident, formatted, tier)
        elseif slotType == "macro" then
            -- "Smart" single-spell macro: Blizzard already resolved it, and `id`
            -- here IS the spellID, not a macro index -- passing it to
            -- GetMacroSpell would look up the wrong thing.
            if subType == "spell" then
                _SetSpellKeybind(ident, formatted, macroRank)
                -- Legacy took Blizzard's single answer as final. Stable mode falls
                -- through to the body scan, which is the whole point: that answer
                -- is state-dependent and hides the other branches.
                if not _stableMode then
                    return
                end
            elseif subType == "item" and ident then
                -- Same contract, item side (e.g. "/use 13" trinket macros): `id`
                -- is the actual itemID, straight from Blizzard, not the body scan.
                _SetKeybind(-ident, formatted, macroRank)
                if not _stableMode then
                    return
                end
            end
            -- For everything else `id` from GetActionInfo is NOT a reliable
            -- identifier -- resolve the real macro index via its name instead
            -- (same workaround CUI_CDM_HookPressMirror.lua's SlotSpellID already uses).
            local macroName = GetActionText(slot)
            local macroIndex = macroName and GetMacroIndexByName(macroName)
            if macroIndex and macroIndex > 0 then
                local live = GetMacroSpell(macroIndex)
                if live then
                    _SetSpellKeybind(live, formatted, macroRank)
                end
                if _stableMode then
                    local body = GetMacroBody and GetMacroBody(macroIndex)
                    if body then
                        _RegisterMacroTargets(body, formatted, macroRank)
                    end
                elseif not live then
                    _RegisterLegacyMacroItem(macroIndex, formatted, macroRank)
                end
            end
        elseif slotType == "item" and ident then
            -- Store under negated itemID (-id) to match the FC convention for
            -- item presets/trinkets.
            _SetKeybind(-ident, formatted, tier)
        end
    end

    -- Stable scan: resolve ACTIONBUTTONn against the pages that reliably reflect
    -- something the player actually set up -- home page plus the bonus pages
    -- (forms, stealth, stances, skyriding), not the page that happens to be
    -- active right now. That makes the cache independent of bar swaps, so a
    -- keybind only ever changes when the player actually moves the ability or
    -- rebinds the key.
    --
    -- Deliberately excluded: manually-paged pages 2-6 (see the tier comment
    -- above) and the vehicle/override/temp-shapeshift pages. The latter's
    -- contents are server-pushed and transient rather than a layout the player
    -- configured, and their page indices can overlap the slot ranges of action
    -- bars 6-8 (145-180), which are already scanned via _barBindingDefs.
    local function _ScanMainBarStable(idx, key)
        _ResolveSlotBinding(idx, key, _TIER_MAINBAR_HOME)
        -- Bonus bars 1-5 (forms, stealth, stances, skyriding) = pages 7-11.
        for pg = 7, 11 do
            _ResolveSlotBinding(idx + (pg - 1) * 12, key, _TIER_MAINBAR_BONUS + pg - 7)
        end
    end

    -- Legacy scan: resolve ACTIONBUTTONn against the currently active page only.
    -- Prefer the EAB main bar's actionpage attribute (set by its secure page
    -- handler, covers override/vehicle pages too). Without it (Action Bars module
    -- disabled), derive the page from the client: bonus bars (forms) map to pages
    -- 7+, but only when page 1 is otherwise active -- a manual page beats the
    -- form/skyriding swap, same priority order the engine itself uses.
    local function _ScanMainBarLive(idx, key)
        local mbf = _G["EABBar_MainBar"]
        local pg = mbf and tonumber(mbf:GetAttribute("actionpage"))
        if not pg then
            local bonus = GetBonusBarOffset and GetBonusBarOffset() or 0
            local page = (GetActionBarPage and GetActionBarPage()) or 1
            if bonus > 0 and page == 1 then
                pg = 6 + bonus
            else
                pg = page
            end
        end
        _ResolveSlotBinding(idx + (pg - 1) * 12, key, _TIER_MAINBAR_HOME)
    end

    -- Global toggle for the stable scan. Default ON via DEFAULTS; the strict
    -- == true read means a pre-merge call (key not seeded yet) falls back to
    -- the legacy live-page scan for that pass.
    local function StableKeybindsEnabled()
        local p = ECME.db and ECME.db.profile
        return (p and p.cdmBars and p.cdmBars.stableKeybinds) == true
    end
    mod.CDMStableKeybindsEnabled = StableKeybindsEnabled

    -- A page swap in live mode. The live scan reads the page from the Action Bars
    -- frames, whose state driver applies it a frame after the page event fires, so
    -- with Action Bars loaded the bars' own page edge (their "state-page" write,
    -- after _onstate-page has set actionpage) rebuilds the cache, on the next
    -- frame; without them the event does (GetBonusBarOffset reads the new bonus
    -- bar at once). A swap never waits for the slot-storm debounce: the spells the
    -- new page brings would show no key until it ran. The hooks go in at the first
    -- live rebuild that finds each bar; stable mode ignores them.
    local _PAGE_EDGE_BARS = { "EABBar_MainBar", "EABBar_Bar9", "EABBar_Bar10" }
    local _pageEdgeHooked = {}
    local _pageFlush = CreateFrame("Frame")
    _pageFlush:Hide()
    _pageFlush:SetScript("OnUpdate", function(self)
        self:Hide()
        if not StableKeybindsEnabled() then
            UpdateCDMKeybinds()
        end
    end)
    local function OnBarAttributeChanged(_, name)
        -- Runs inside the state driver's secure pass: only queue the rebuild (the
        -- flush reads the setting itself, so a mode changed since the last rebuild
        -- cannot drop or add one).
        if name == "state-page" then
            _pageFlush:Show()
        end
    end
    local function HookBarPageEdges()
        for idx = 1, #_PAGE_EDGE_BARS do
            local barName = _PAGE_EDGE_BARS[idx]
            if not _pageEdgeHooked[barName] then
                local f = _G[barName]
                if f then
                    _pageEdgeHooked[barName] = true
                    f:HookScript("OnAttributeChanged", OnBarAttributeChanged)
                end
            end
        end
    end
    -- The page events' route in live mode (CUI_CDM_Events.lua). A bar built since
    -- the last rebuild is hooked here, at the event, ahead of the page edge the
    -- state driver writes on its next update.
    function mod.CDMKeybindPageSwap()
        HookBarPageEdges()
        if _pageEdgeHooked.EABBar_MainBar then
            return
        end
        _pageFlush:Show()
    end

    local function RebuildKeybindCache()
        wipe(_cdmKeybindCache)
        wipe(_cdmKeybindRank)
        -- Latch the mode for this whole rebuild so the multi-page scan and the
        -- macro body scan can never disagree about it mid-pass.
        _stableMode = StableKeybindsEnabled()
        if not _stableMode then
            HookBarPageEdges()
        end
        for _, def in ipairs(_barBindingDefs) do
            for idx = 1, 12 do
                local key = GetBindingKey(def.prefix .. idx)
                if key then
                    local slot = def.startSlot + idx - 1
                    if def.eabButton then
                        -- CUI bars 9/10 have no native binding command: their keys
                        -- are routed through the button with SetOverrideBindingClick
                        -- against the custom commands declared in the Action Bars
                        -- module's Bindings.xml. That route always reads the
                        -- button's live "action" attr, so resolve the slot from the
                        -- button when it exists (custom paging) and only fall back
                        -- to the base page slot when the Action Bars module isn't
                        -- loaded.
                        local button = _G["EABButton" .. slot]
                        local live = button and tonumber(button:GetAttribute("action"))
                        if live then
                            slot = live
                        end
                    end
                    _ResolveSlotBinding(slot, key, def.tier)
                end
            end
        end
        local scanMainBar = _stableMode and _ScanMainBarStable or _ScanMainBarLive
        for idx = 1, 12 do
            local key = GetBindingKey("ACTIONBUTTON" .. idx)
            if key then
                scanMainBar(idx, key)
            end
        end
    end

    -- Spell half of the keybind lookup, shared by the CDM icons and the Rotation
    -- Assist Icon: the id itself, then its override, its base, then its name.
    -- The item and trinket fallbacks stay with the CDM icons below.
    local function ResolveCDMKeybind(spellRef)
        local key = _cdmKeybindCache[spellRef]
        if key then
            return key
        end
        local ovr = C_Spell.GetOverrideSpell(spellRef)
        if ovr and not issecretvalue(ovr) and ovr ~= spellRef then
            key = _cdmKeybindCache[ovr]
            if key then
                return key
            end
        end
        local base = C_Spell.GetBaseSpell(spellRef)
        if base and not issecretvalue(base) and base ~= spellRef then
            key = _cdmKeybindCache[base]
            if key then
                return key
            end
        end
        if spellRef > 0 then
            local name = C_Spell.GetSpellName(spellRef)
            if name and not issecretvalue(name) then
                return _cdmKeybindCache[name]
            end
        end
    end
    mod.ResolveCDMKeybind = ResolveCDMKeybind

    -- Apply the current cache to all visible CDM icon keybind texts
    local function ApplyCachedKeybinds()
        for barId, icons in pairs(cdmBarIcons) do
            local edge = barDataByKey[barId]
            for _, icon in ipairs(icons) do
                local ifd = _getFD(icon)
                local kbText = ifd and ifd.keybindText or icon._keybindText
                local ifc = _ecmeFC[icon]
                local spellRef = ifc and ifc.spellID
                if ifc then
                    ifc.keybindSid = spellRef
                end
                if kbText then
                    if edge and edge.showKeybind and spellRef then
                        local key = ResolveCDMKeybind(spellRef)
                        -- Item presets: the resolved display variant first (pot presets may be showing another rank/Fleeting/the swapped-in partner pot), then the static alt ids.
                        if not key and icon._isItemPresetFrame and icon._displayItemID then
                            key = _cdmKeybindCache[-icon._displayItemID]
                        end
                        -- Item presets: check alt item IDs (user may have a different rank of the same potion on their bar).
                        -- Blizzard's own row rendering under a preset key (a frame with
                        -- no preset data of its own) walks that preset's ranks the same way.
                        local pdK = icon._presetData
                        if not key and not pdK and type(spellRef) == "number" and spellRef < 0 then
                            pdK = mod.ItemPresetForKey(spellRef)
                        end
                        if not key and pdK and pdK.altItemIDs then
                            for _, altID in ipairs(pdK.altItemIDs) do
                                key = _cdmKeybindCache[-altID]
                                if key then
                                    break
                                end
                            end
                        end
                        -- Trinkets: check by equipped item's action slot
                        if not key and icon._isTrinketFrame and icon._trinketSlot then
                            local itemId = GetInventoryItemID("player", icon._trinketSlot)
                            if itemId then
                                key = _cdmKeybindCache[-itemId]
                            end
                        end
                        if key then
                            kbText:SetText(key)
                            kbText:Show()
                        else
                            kbText:Hide()
                        end
                    else
                        kbText:Hide()
                    end
                    -- Visibility pass only: settings edges restyle the badge
                    -- through StyleCDMKeybind.
                    mod.ShowCDMKeybindBadge(kbText, edge)
                end
            end
        end
        if mod.UpdateRotationAssistIconKeybind then
            mod.UpdateRotationAssistIconKeybind()
        end
    end

    UpdateCDMKeybinds = function()
        RebuildKeybindCache()
        -- Defer apply by one frame so the Blizzard tick has populated FC(icon).spellID
        C_Timer.After(0, ApplyCachedKeybinds)
    end
    mod.UpdateCDMKeybinds = UpdateCDMKeybinds
    -- Expose apply-only for the tick loop (new spellID assigned to an icon mid-session)
    mod.ApplyCachedKeybinds = ApplyCachedKeybinds
    -- Reanchor edge: Blizzard reuses viewer frames, so an icon can come back
    -- holding another spell with no binding or slot event behind it. Compare-only
    -- unless an icon's spell differs from the one its text was resolved for.
    mod.RefreshStaleCDMKeybinds = function()
        for _, icons in pairs(cdmBarIcons) do
            for idx = 1, #icons do
                local ifc = _ecmeFC[icons[idx]]
                if ifc and ifc.spellID ~= ifc.keybindSid then
                    ApplyCachedKeybinds()
                    return
                end
            end
        end
    end
    mod.CDMKeybindCache = _cdmKeybindCache
end -- keybind cache block

BuildAllCDMBars = function()
    mod._spellOrderDirty = true -- force spell order cache rebuild
    -- Belt for the active-store cache: every profile apply, import, layout switch and options rebuild passes through here.
    mod._cachedSpecProfiles = nil
    mod._cdmStoreMemo = nil
    -- Structural edges: claims and resolution inputs both change across a rebuild, so retire the proc-alert claim map and cdID resolution memo.
    mod._cdmClaimGen = mod._cdmClaimGen + 1
    mod._cdmResGen = mod._cdmResGen + 1
    -- Hard guard: never build with an unknown spec. CDMFinishSetup is gated on GetActiveSpecKey() at OnEnable, so this is a defense in depth for any other path that calls BuildAllCDMBars too early.
    if not mod.GetActiveSpecKey() then
        return
    end

    -- Mark CDM as rebuilding so width/height match propagation gates off (it would otherwise read
    -- transient bar widths sized for the previous spec's icon count and bake them into
    -- _matchPhysWidth on dependent bars). Cleared at the end of CollectAndReanchor when _pendingApplyOnReanchor fires the authoritative ApplyAllWidthHeightMatches pass.
    if CludesUI then
        CludesUI._cdmRebuilding = true
    end

    -- Ensure ghost bars exist before iterating bars
    EnsureGhostBars()
    EnsureFocusKickBar()
    mod.RescanMaxStacksGlowFlag() -- set the Max Stacks Glow gate (once) before refresh
    mod.RescanChargeCdTextFlag() -- set the Hide CD Text (Charges) gate (once) before refresh
    mod.RescanSpellDurationTextFlag() -- and the per-spell Duration Text gate
    mod.RescanHideChargeTextFlag() -- set the Hide Charge Text gate (once) before refresh
    mod.RescanSuppressGcdFlag() -- set the per-spell Suppress GCD gate (once) before refresh
    mod.RescanChargeStyleFlag() -- set the Hide Swipe (Charges) gate (once) before refresh
    mod.RescanBuffSoundFlag() -- set the Audio on Buff Gain/Loss gate (once) before refresh
    mod.RescanCdReadySoundFlag() -- set the Audio Effect on CD Ready gate (once) before refresh
    mod.RescanBuffReplaceFlag() -- set the Replace with Buff gate (once) before the route map
    mod.RescanCustomItemFlag() -- set the custom-item buff-injection gate (once)
    mod.RescanCustomForceCountFlag() -- set the "Show Charges" custom-spell gate (once)
    mod.RescanCustomRangeColorFlag() -- set the "Out of Range Coloring" custom-spell gate (once)
    mod.RescanReverseSwipeFlag() -- set the Reverse Swipe gate (once) before refresh
    mod.RescanThresholdTextFlag() -- set the Threshold Text gate (once) before refresh
    mod.RescanCustomIconFlag() -- set the per-spell Custom Icon gate (once) before refresh
    mod.RescanActiveGlowFlag() -- set the Active State Glow gate (once) before refresh
    mod.RescanTalentCondFlag() -- set the Talent Conditions gate (once) before refresh
    mod.RescanStanceBarFlag() -- set the Stance Bar gate (once) before refresh

    local p = ECME.db.profile

    -- Heal ghost bar entries: an override write to a numeric bar path whose bar no longer existed
    -- (profile import, or a deleted bar with a stored override still referencing its index) used to
    -- auto-create a skeleton table (e.g. { barVisibility = "always" }) with no key. Every keyed
    -- consumer (spell data, racial normalize, unlock snapshots) then errors on the nil key. The override writer no longer fabricates numeric containers; this prunes profiles that already carry ghosts.
    if type(p.cdmBars.bars) == "table" then
        for idx = #p.cdmBars.bars, 1, -1 do
            local edge = p.cdmBars.bars[idx]
            if type(edge) ~= "table" or not edge.key then
                table.remove(p.cdmBars.bars, idx)
            end
        end
    end

    if not p.cdmBars.enabled then
        -- Restore Blizzard CDM if we're disabled
        RestoreBlizzardCDM()
        for key, widget in pairs(cdmBarFrames) do
            CludesUI.SetElementVisibility(widget, false)
        end
        return
    end

    -- Migrate the old global Always Show Buffs settings to per-bar before anything reads them (placeholder injection/desaturate ticker).
    if mod.MigrateAlwaysShowBuffsToPerBar then
        mod.MigrateAlwaysShowBuffsToPerBar()
    end
    -- Then merge legacy custom_buff (Auras) bars into the buff-family bars.
    if mod.MigrateCustomBuffBarsToBuffBars then
        mod.MigrateCustomBuffBarsToBuffBars()
    end

    -- Force Blizzard's EditMode CooldownViewer to "Always Visible" so hideWhenInactive and other viewer settings don't fight with CDM.
    EnforceCooldownViewerEditModeSettings()

    -- Hide Blizzard CDM
    if p.cdmBars.hideBlizzard then
        HideBlizzardCDM()
    end

    -- If user wants Blizzard's tracking bars instead of TBB, restore the secondary
    -- BuffBarCooldownViewer that HideBlizzardCDM moved offscreen. This only affects the bar-style buff viewer; CDM icon bars are untouched.
    if p.cdmBars.useBlizzardBuffBars and p.cdmBars.hideBlizzard then
        RestoreBlizzardBuffFrame()
    end

    -- Build each bar and populate fast lookup
    local hookActive = mod.IsViewerHooked and mod.IsViewerHooked()
    wipe(barDataByKey)
    mod._cdmAnyOverflowCfg = nil
    for idx, barInfo in ipairs(p.cdmBars.bars) do
        barDataByKey[barInfo.key] = barInfo
        -- Live migration: buffGlowMode replaced buffGlowClassColor + "buffGlowR set" nil checks
        if not barInfo.buffGlowMode then
            if barInfo.buffGlowClassColor then
                barInfo.buffGlowMode = "class"
            elseif barInfo.buffGlowR ~= nil then
                barInfo.buffGlowMode = "custom"
            else
                barInfo.buffGlowMode = "default"
            end
        end
        -- Live migration: pandemicGlowMode replaced pandemicGlowColor always being set
        if not barInfo.pandemicGlowMode then
            local c = barInfo.pandemicGlowColor
            if c and not (c.r == 1 and c.g == 1 and c.b == 0) then
                barInfo.pandemicGlowMode = "custom"
            else
                barInfo.pandemicGlowMode = "default"
            end
        end
        -- Max Icons overflow: cheap session gate. Validity of the target is checked at reanchor time (Phase 3b); this only answers "is it worth looking" so the feature is two nil-checks when unused.
        if
            not mod._cdmAnyOverflowCfg
            and barInfo.enabled
            and barInfo.maxIcons
            and barInfo.maxIcons > 0
            and barInfo.overflowTarget
        then
            mod._cdmAnyOverflowCfg = true
        end
        BuildCDMBar(idx)
        local widget = cdmBarFrames[barInfo.key]
        if widget then
            widget._prevVisibleCount = nil
        end
        if hookActive and BLIZZ_CDM_FRAMES[barInfo.key] then
            -- Hooked default bar: skip icon state reset and layout. CollectAndReanchor will repopulate from viewer pools.
        else
            RefreshCDMIconAppearance(barInfo.key)
            -- Reset cached icon state so textures re-evaluate after a character switch
            local icons = cdmBarIcons[barInfo.key]
            if icons then
                for _, icon in ipairs(icons) do
                    local iifc = FC(icon)
                    iifc.lastTex = nil
                    iifc.lastDesat = nil
                    iifc.blizzChild = nil
                    iifc.spellID = nil
                end
            end
            LayoutCDMBar(barInfo.key)
            ApplyCDMTooltipState(barInfo.key)
        end
    end
    -- Resync the key-press-mirror fast enable-flag with the rebuilt bar list, so OnPress O(1)-gates instead of looping every bar per press (covers profile and spec swaps, not just the options toggle).
    if mod.RefreshCdmPressMirrorFlag then
        mod.RefreshCdmPressMirrorFlag()
    end
    -- Custom-aura containers re-evaluate here: icon size, shape, spacing and
    -- growth change the engine flow, which needs a rebuild rather than a
    -- restyle, and a hooked default bar skips RefreshCDMIconAppearance above.
    if mod.UpdateCustomBuffAuraTracking then
        mod.UpdateCustomBuffAuraTracking()
    end
    -- When hooks are active, queue a reanchor to repopulate default bars. The queued
    -- CollectAndReanchor will lift _cdmRebuilding when it finishes; if no reanchor is queued (hooks not yet installed) we must clear the flag here ourselves so width matching can run again.
    if hookActive and mod.QueueReanchor then
        mod.QueueReanchor()
    else
        if CludesUI then
            CludesUI._cdmRebuilding = nil
        end
    end
    -- Re-apply saved positions now that LayoutCDMBar has set correct frame sizes. Positions are
    -- stored using the edge anchor directly (LEFT for RIGHT-grow, etc.), so SetPoint places the frame at its fixed edge and subsequent SetSize calls grow naturally from that edge.
    for _, barInfo in ipairs(p.cdmBars.bars) do
        if barInfo.enabled then
            local ak = barInfo.anchorTo
            if not ak or ak == "none" then
                local widget = cdmBarFrames[barInfo.key]
                local place = p.cdmBarPositions[barInfo.key]
                if widget and place and place.point then
                    local unlockKey = "CDM_" .. barInfo.key
                    local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not widget:GetLeft() then
                        ApplyBarPositionCentered(widget, place, barInfo.key)
                    end
                end
            end
        end
    end
    -- Second pass: reapply unlock-mode anchors now that ALL bars are positioned and sized. The
    -- first pass (inside LayoutCDMBar) may have run ReapplyOwnAnchor before the target bar was repositioned (e.g. cooldowns processed before utility). This corrects that.
    if CludesUI.ReapplyOwnAnchor then
        for _, barInfo in ipairs(p.cdmBars.bars) do
            CludesUI.ReapplyOwnAnchor("CDM_" .. barInfo.key)
        end
    end
    UpdateCDMKeybinds()

    -- Apply visibility (hides bars set to "in combat only", "never", etc; handles unlock-mode override and viewer alpha sync). Single authority.
    _CDMApplyVisibility()

    -- Every full rebuild re-evaluates the FocusKick demand gate, so assigning the first kick spell (or removing the last) flips the feature family on/off live.
    if mod.RefreshFocusKickProxies then
        mod.RefreshFocusKickProxies()
    end

    -- WoW Forever: the anti-clip glow (a bar's Pandemic Glow there) listens to
    -- your casts only while a bar uses it (CUI_CDM_ForeverAntiClip.lua).
    if mod.CDM_AntiClipSync then
        mod.CDM_AntiClipSync()
    end

    -- Match pads follow each bar's border settings: a bar whose pad changed is
    -- re-pushed through its matches once, deferred (compare-only here).
    if CludesUI.MatchPadChanged then
        for _, edge in ipairs(p.cdmBars.bars) do
            if edge.key then
                CludesUI.MatchPadChanged(mod._cdmUKey[edge.key])
            end
        end
    end
end

-- Expose for options
mod.BuildAllCDMBars = BuildAllCDMBars
mod.cdmBarFrames = cdmBarFrames
mod.cdmBarIcons = cdmBarIcons
mod.barDataByKey = barDataByKey
mod.SaveCDMBarPosition = SaveCDMBarPosition
mod.LayoutCDMBar = LayoutCDMBar
mod.BLIZZ_CDM_FRAMES = BLIZZ_CDM_FRAMES
mod.CDM_BAR_CATEGORIES = CDM_BAR_CATEGORIES
mod.MAX_CUSTOM_BARS = MAX_CUSTOM_BARS
mod.FindPlayerPartyFrame = CludesUI.FindPlayerPartyFrame

-- Expose LayoutCDMBar globally so unlock mode can trigger rebuilds
CludesUI.LayoutCDMBar = LayoutCDMBar
mod.FindPlayerUnitFrame = CludesUI.FindPlayerUnitFrame
mod.RestoreBlizzardCDM = RestoreBlizzardCDM
mod.HideBlizzardCDM = HideBlizzardCDM

-------------------------------------------------------------------------------
--  FullCDMRebuild
--  The ONE function for "something changed". Treats every call the same:
--  wipe all caches, clear stale frames, rebuild bars, rebuild TBB,
--  reanchor, reapply visibility, update keybinds. Identical result to
--  a fresh login. Use this for spec switch, talent change, zone
--  transition, profile import, equipment change, etc.
--  For cosmetic-only changes (icon size, fonts, glows) call
--  BuildAllCDMBars() directly.
-------------------------------------------------------------------------------

-- Rewrite stored racial spell IDs on CD/utility bars to this character's active racial: a shared
-- profile keeps whichever race's racial each character added, so collapse them to a single
-- "Racial" slot that follows each character's race without re-adding. Operates on the active
-- spec's lists (other specs normalize when they next become active). No-op on buff bars and when
-- no active racial resolves. Family-global: across ALL non-buff bars the racial ends up on at most
-- ONE bar. If the active racial is already placed, keep it where it sits and strip every other racial (foreign leftovers AND stray duplicates); if no active racial is present, promote the first foreign racial in place so the slot still appears for this character.
function mod.NormalizeRacialAssignments()
    -- Re-resolve now: at build time the spellbook is reliably populated, so the variant pick (Blood Fury/Arcane Torrent/Gift of the Naaru) is correct even if OnEnable ran before the spellbook loaded.
    local isActive = ResolveActiveRacial()
    if not isActive or isActive <= 0 then
        return
    end
    local p = ECME.db and ECME.db.profile
    if not (p and p.cdmBars and p.cdmBars.bars) then
        return
    end

    -- Gather the non-buff bars' assigned lists once (in bar order), keeping
    -- each list's bar key so the keeper choice below can tell default bars
    -- from explicit custom placements.
    local lists, listBarKeys = {}, {}
    for _, b in ipairs(p.cdmBars.bars) do
        local isBuff = (b.barType == "custom_buff") or (mod.IsBarBuffFamily and mod.IsBarBuffFamily(b))
        -- b.key guard: a ghost bar (keyless skeleton from a stale override write) would index barSpells with nil and error.
        if not isBuff and b.key then
            local sd = mod.GetBarSpellData(b.key)
            if sd and sd.assignedSpells then
                lists[#lists + 1] = sd.assignedSpells
                listBarKeys[#lists] = b.key
            end
        end
    end

    -- Is the active racial already placed on a bar (this character's pick)?
    local activePresent = false
    for _, entries in ipairs(lists) do
        for _, spellRef in ipairs(entries) do
            if spellRef == isActive then
                activePresent = true
                break
            end
        end
        if activePresent then
            break
        end
    end

    -- Keeper choice: prefer the copy on a CUSTOM bar. Lists iterate in bar
    -- order with the default bars first, so the old first-found-wins rule kept
    -- the Essential/Utility copy of a dual-state and DELETED the user's custom
    -- placement -- the 12.1 native-racial "reset to Essential/Utility" report
    -- (Blizzard's CDM now tracks racials, so a materialized default-bar copy
    -- can coexist with the user's). A custom-bar copy is always an explicit
    -- act; a default-bar copy can be a materialized spillover.
    local keeperList
    if activePresent then
        for li, entries in ipairs(lists) do
            local bk = listBarKeys[li]
            if bk ~= "cooldowns" and bk ~= "utility" then
                for _, spellRef in ipairs(entries) do
                    if spellRef == isActive then
                        keeperList = entries
                        break
                    end
                end
            end
            if keeperList then
                break
            end
        end
    end

    -- Single pass across every bar: keep exactly one racial slot total.
    local kept = false
    for _, entries in ipairs(lists) do
        for idx = #entries, 1, -1 do
            local spellRef = entries[idx]
            if spellRef and spellRef > 0 and ALL_RACIAL_SPELLS[spellRef] then
                if
                    spellRef == isActive
                    and activePresent
                    and not kept
                    and (not keeperList or entries == keeperList)
                then
                    -- Keep the current character's own racial where it sits
                    -- (the custom-bar copy when one exists, see keeperList).
                    kept = true
                elseif not activePresent and not kept then
                    -- No active racial anywhere: promote this foreign one.
                    entries[idx] = isActive
                    kept = true
                    mod._spellOrderDirty = true
                else
                    -- Any further racial (foreign or duplicate) is removed.
                    table.remove(entries, idx)
                    mod._spellOrderDirty = true
                end
            end
        end
    end
end

function mod.FullCDMRebuild(reason)
    mod._spellOrderDirty = true -- force spell order cache rebuild
    -- Full-wipe reasons: clear per-frame caches and run a direct reanchor.
    -- Used for talent change and any path where spell IDs behind
    -- cooldownIDs may have changed (so cached resolvedSid is stale).
    local isFullWipe = (reason == "talent_reconcile")

    -- 1. Wipe all caches
    if mod.MarkCDMSpellCacheDirty then
        mod.MarkCDMSpellCacheDirty()
    end
    if mod.InvalidateTBBFrameCache then
        mod.InvalidateTBBFrameCache()
    end

    -- 2. Clear old preset frames (trinkets, racials, custom spells)
    if mod._presetFrames then
        for _, f in pairs(mod._presetFrames) do
            f:Hide()
            f:ClearAllPoints()
        end
        -- Deliberately NOT wiped: this map is the identity/REUSE registry the
        -- create-only frame sites key by. Wiping it orphaned every preset frame OBJECT
        -- (WoW frames are unreclaimable) and rebuilt the whole population on the next
        -- inject -- a frame-object leak on EVERY talent/spec/profile rebuild. Stale
        -- keys are harmless: the drain iterates the shown-set (_pcActive in CdmHooks),
        -- not this map, and re-injected keys REUSE their frame with a full re-arm on
        -- the Show edge -- the same reuse path every reanchor already runs.
    end

    -- Default bars need no assignedSpells pre-population: the route map's
    -- diversion-set model routes everything in the viewer category to the
    -- default bar by spillover, so empty assignedSpells just means "show
    -- whatever Blizzard's viewer has" -- exactly the desired behavior.

    -- 2b. Normalize racial slots to this character's race BEFORE the route
    -- map and bar build read assignedSpells.
    if mod.NormalizeRacialAssignments then
        mod.NormalizeRacialAssignments()
    end

    -- 3. Rebuild route maps (must happen before BuildAllCDMBars)
    if mod.RebuildSpellRouteMap then
        mod.RebuildSpellRouteMap()
    end

    -- 4. Rebuild all bar frames
    BuildAllCDMBars()

    -- 5. Rebuild tracked buff bars
    if mod.BuildTrackedBuffBars then
        mod.BuildTrackedBuffBars()
    end

    -- 6. Full-wipe path: wipe per-frame caches + icon arrays + anchor
    -- state, then reanchor directly. Used by talent_reconcile when spell
    -- IDs behind cooldownIDs may have changed.
    --
    -- Non-full-wipe reasons don't need an explicit reanchor here: the
    -- BuildAllCDMBars call above already queued a reanchor when hooks
    -- are active. The throttled queue dedupes naturally.
    if isFullWipe then
        -- Wipe all icon arrays
        for bk, icons in pairs(cdmBarIcons) do
            for idx = 1, #icons do
                icons[idx] = nil
            end
        end
        -- Clear change detection so layout runs fresh
        for bk, widget in pairs(cdmBarFrames) do
            if widget then
                widget._prevIconRefs = nil
                widget._prevVisibleCount = nil
            end
        end
        -- Clear all stale anchors so SetPoint hook doesn't fight
        if mod._hookFrameData then
            for _, efd in pairs(mod._hookFrameData) do
                efd._cdmAnchor = nil
            end
        end
        -- Clear all FC caches so ResolveFrameSpellID re-reads from API.
        -- Spells behind cooldownIDs change on spec swap; stale caches
        -- would return the old spec's spell IDs.
        for _, vname in ipairs(_cdmViewerNames) do
            local vf = _G[vname]
            if vf and vf.itemFramePool and vf.itemFramePool.EnumerateActive then
                for ch in vf.itemFramePool:EnumerateActive() do
                    local chfc = _ecmeFC[ch]
                    if chfc then
                        chfc.resolvedSid = nil
                        chfc.baseSpellID = nil
                        chfc.overrideSid = nil
                        chfc.cachedCdID = nil
                        chfc.isChargeSpell = nil
                        chfc.maxCharges = nil
                        chfc.sortOrder = nil
                        -- NOT chfc.barKey: CollectAndReanchor reads it as
                        -- "we have claimed this frame before" and refuses to
                        -- park it while identification is transiently failing.
                        -- Clearing it here would hand the next pass a frame it
                        -- cannot identify AND cannot vouch for.
                    end
                end
            end
        end
        -- A memo wipe is the START of a fresh transient-failure window, so
        -- hand the reanchor below a full retry budget instead of whatever an
        -- earlier transition left behind. Matters for cooldowns that are new
        -- to the spec being swapped TO: those have no barKey to vouch for
        -- them, so the budget is all they have.
        mod._cdmUnresolvedRetries = 0
        -- Cancel the reanchor BuildAllCDMBars queued -- we run our own direct one
        -- immediately below. Without this, the queued reanchor would fire ~200ms later
        -- and run the entire reanchor pipeline a second time.
        if mod.ClearQueuedReanchor then
            mod.ClearQueuedReanchor()
        end
        -- Direct reanchor for the freshly-wiped state
        if mod.CollectAndReanchor then
            mod.CollectAndReanchor()
        end
    end

    -- 7. Glows
    if mod.RequestBarGlowUpdate then
        mod.RequestBarGlowUpdate()
    end
    -- Re-evaluate CD ready glow state now that all frames are fully decorated.
    -- Decoration paths may have started glows during the loading-screen settle
    -- window (login/reload); this queued pass corrects them once the API is
    -- trustworthy again. No-ops instantly when no icon uses a ready-glow effect.
    if mod.QueueCDGlowResourceCheck then
        mod.QueueCDGlowResourceCheck()
    end
end

-- Interactive Preview Helpers loaded from CludesUICdmSpellPicker.lua

Inner._CDMApplyVisibility, Inner.BuildAllCDMBars = _CDMApplyVisibility, BuildAllCDMBars
Inner.UpdateCDMKeybinds = UpdateCDMKeybinds
Inner.SetCDMApplyVisibility(_CDMApplyVisibility)
Inner.broken = false
