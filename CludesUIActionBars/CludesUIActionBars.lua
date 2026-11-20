if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIActionBars.lua  Custom Action Bars
--  Own secure action bar frames AND buttons (EABButton/ActionBarButtonTemplate),
--  eliminating the taint surface from reusing Blizzard's protected buttons.
--  Stance/Pet bars still reuse Blizzard buttons (own secure handling).
--  Keybinds: SetOverrideBindingClick for all bars. Paging: RegisterStateDriver
--  + _childupdate-eab-page with explicit action attrs.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewInternals
        and CludesUI.NewCombatQueue
        and CludesUI.SetFramePoint
        and CludesUI.HideFrame
        and CludesUI._Pool
        and CludesUI.PadGamepadUI
        and CludesUI.PadModeOn
        and CludesUI.RequestTimePlayed
        and CludesUI.FormatDuration
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the extra bars move Edit Mode systems through the parent's SetFramePoint, and Blizzard's main bar hides through its HideFrame; WoW Forever's Gamepad interface style is read through its PadGamepadUI, and Hide Bar When Using Gamepad follows its PadModeOn; the XP bar's Time This Level asks /played through RequestTimePlayed and its time texts read FormatDuration)
CludesUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry
local ABAR = CludesUI.Lite.NewAddon(ADDON_NAME)
mod.EAB = ABAR

local Pix = CludesUI.PP

-- CPU-attribution shell pool: the engine bills a handler's whole call tree to the addon
-- whose context CREATED the frame it entered through, so frames born in build/enable
-- code bill the PARENT forever (probe-verified, see CludesUI_Ticker.lua). Shells
-- born in this main chunk stamp to ActionBars; runtime code should call ns.TakeShell()
-- instead of CreateFrame for persistent hosts carrying events/scripts. No release, so
-- transient throwaway frames keep using CreateFrame.
do
    local pool = {}
    local num = 40
    for index = 1, num do
        pool[index] = CreateFrame("Frame")
    end
    mod.TakeShell = function()
        if num > 0 then
            local frame = pool[num]
            pool[num] = nil
            num = num - 1
            return frame
        end
        -- Pool exhausted (not expected): frame just bills the parent; bump n if it happens.
        return CreateFrame("Frame")
    end
end

-- "Run once after combat" for every combat-gated deferral in this file. The shell is
-- taken in the main chunk, so drained work bills ActionBars. Keys are per purpose, and
-- sites that defer the same work share a key (e.g. "UpdateKeybinds").
mod.CombatQueue = CludesUI.NewCombatQueue(mod.TakeShell())

-- Count text visibility through the count fontstring's ALPHA, never its text
-- -- text is co-owned: Blizzard's mixin keeps SPELL_UPDATE_CHARGES registered
-- and rewrites Count with the raw value every charge event, but nothing
-- engine-side touches alpha (same as the CDM twin). Two settings decide it:
--   Charge Numbers (per bar hideChargeCount / hideStackCount / hideItemCount,
--   true = hidden, unset = shown): a hidden kind hides the count outright.
--   "Hide Count at 0" (profile hideZeroCount): hides a zero charge/stack count.
-- A hidden kind wins; otherwise the zero rule decides. Memoized in
-- fd._zeroCountAlpha (0 hidden, 1 shown, false = written from a secret, so
-- what shows is unknown); fails open on SECRET values (combat) so the count
-- shows rather than risk a tainted compare. Neither set = a few table reads +
-- a memo compare, no API call. (On ns, not a chunk local.)
do -- Count text visibility
    -- How the bar's Charge Numbers settings take the count this action shows,
    -- with no secret compared or tested: "hide" when its kind is hidden;
    -- "gate" plus the action's secret use count, which as an alpha hides the
    -- count exactly while it reads 0 (the charges show then); nil when the
    -- count is left to the zero rule. The kinds follow Blizzard's count
    -- (C_ActionBar.GetActionDisplayCount): an item, consumable or stackable
    -- action shows its item count (Item Count); any other action its use
    -- count while that is above 0 (Stacks), else its charges while it has
    -- more than one (Charges). A third return hands the zero rule the
    -- action's charge info once it was read here.
    local function HiddenKind(cfg, actionSlot)
        local CA = C_ActionBar
        -- Never secret (none of the three carries a secrecy flag).
        if CA.IsItemAction(actionSlot) or CA.IsConsumableAction(actionSlot) or CA.IsStackableAction(actionSlot) then
            if cfg.hideItemCount then
                return "hide"
            end
            return nil
        end
        local hideCharges, hideStacks = cfg.hideChargeCount, cfg.hideStackCount
        if hideCharges and hideStacks then
            return "hide"
        end
        if not (hideCharges or hideStacks) then
            return nil
        end
        -- maxCharges is never secret; the use count is while cooldowns are
        -- restricted.
        local chargeInfo = CA.GetActionCharges(actionSlot)
        -- Only a plain table is handed on (the caller tests it for nil).
        if not (type(chargeInfo) == "table" and not (issecretvalue and issecretvalue(chargeInfo))) then
            chargeInfo = nil
        end
        local macroText = chargeInfo and chargeInfo.maxCharges
        if not (type(macroText) == "number" and not (issecretvalue and issecretvalue(macroText)) and macroText > 1) then
            if hideStacks then
                return "hide"
            end
            return nil, nil, chargeInfo
        end
        local uc = CA.GetActionUseCount(actionSlot)
        if issecretvalue and issecretvalue(uc) then
            -- Telling the stacks from the charges needs the secret: Charges
            -- hidden rides it as the alpha, Stacks hidden fails open.
            if hideCharges then
                return "gate", uc
            end
            return nil, nil, chargeInfo
        end
        if type(uc) == "number" and uc > 0 then
            if hideStacks then
                return "hide"
            end
            return nil, nil, chargeInfo
        end
        if hideCharges then
            return "hide"
        end
        return nil, nil, chargeInfo
    end

    mod._EABZeroCountAlpha = function(frameData, fontStr, val, actionSlot)
        local pdb = ABAR.db and ABAR.db.profile
        -- The charge info HiddenKind read, reused by the zero rule below.
        local chargeInfo
        -- Charge Numbers: the profile read IS the gate (a cached flag would go
        -- stale across profiles and overrides); unset on every kind = no API call.
        if actionSlot and pdb then
            local barList, key = pdb.bars, frameData.barKey
            local cfg = barList and key and barList[key]
            if cfg and (cfg.hideChargeCount or cfg.hideStackCount or cfg.hideItemCount) then
                local how, gate
                how, gate, chargeInfo = HiddenKind(cfg, actionSlot)
                if how == "hide" then
                    if frameData._zeroCountAlpha ~= 0 then
                        frameData._zeroCountAlpha = 0
                        fontStr:SetAlpha(0)
                    end
                    return
                elseif how == "gate" then
                    frameData._zeroCountAlpha = false
                    fontStr:SetAlpha(gate)
                    return
                end
            end
        end
        if not (pdb and pdb.hideZeroCount) then
            -- OFF fast path: reads + memo compare only, except healing a leftover hidden
            -- or secret-written stamp so a button can't stay stuck invisible after a
            -- toggle/profile switch.
            local z = frameData._zeroCountAlpha
            if z == 0 or z == false then
                frameData._zeroCountAlpha = 1
                fontStr:SetAlpha(1)
            end
            return
        end
        local a = 1
        if actionSlot then
            -- Charge spells route EXCLUSIVELY through the count: SetAlpha clamps
            -- to [0,1], so alpha := currentCharges hides at exactly 0 and shows
            -- at 1+ with no comparison needed. Never infer zero charges from an active
            -- cooldown record -- charges banked while the main cooldown runs (e.g. Feint)
            -- would hide a real count. SetAlpha accepts secret numbers
            -- (AllowedWhenTainted), so the same write runs in and out of instanced combat;
            -- a secret count writes through with the memo dirtied, never stored/compared.
            local chargeInfo = chargeInfo or (C_ActionBar.GetActionCharges and C_ActionBar.GetActionCharges(actionSlot))
            local macroText = chargeInfo and chargeInfo.maxCharges
            if macroText ~= nil and not (issecretvalue and issecretvalue(macroText)) and macroText > 1 then
                local cooldownCount = chargeInfo.currentCharges
                -- issecretvalue FIRST, and type() rather than == nil for the missing
                -- case. The count is secret whenever cooldowns are restricted, and
                -- comparing a secret to nil is the operation our own secret rules
                -- forbid -- so ordering the nil "belt" ahead of the guard made the
                -- belt the hazard, and a throw strands the count HIDDEN rather than
                -- protecting it. Same defect and same fix as the CDM counterpart in
                -- CludesUICdmHooks (EvalZeroChargeTextFrame).
                if issecretvalue and issecretvalue(cooldownCount) then
                    frameData._zeroCountAlpha = false
                    fontStr:SetAlpha(cooldownCount)
                elseif type(cooldownCount) ~= "number" then
                    if frameData._zeroCountAlpha ~= 1 then
                        frameData._zeroCountAlpha = 1
                        fontStr:SetAlpha(1)
                    end
                else
                    a = cooldownCount > 1 and 1 or cooldownCount
                    if frameData._zeroCountAlpha ~= a then
                        frameData._zeroCountAlpha = a
                        fontStr:SetAlpha(a)
                    end
                end
                return
            end
            -- Non-charge: mixin shows GetActionCount for consumables/stackables
            -- (including 0); display string is only the cheap first check.
            -- issecretvalue FIRST: v is GetActionDisplayCount's return, which the
            -- API documents as secret whenever cooldowns are restricted, and
            -- comparing a secret to nil is the operation our own rules forbid --
            -- the same ordering defect this function's charge branch above already
            -- carries a comment about. The nil case needs no test of its own:
            -- nil == 0 is simply false.
            if not (issecretvalue and issecretvalue(val)) and (val == 0 or val == "0") then
                a = 0
            elseif
                (IsConsumableAction and IsConsumableAction(actionSlot))
                or (IsStackableAction and IsStackableAction(actionSlot))
            then
                local c = GetActionCount and GetActionCount(actionSlot)
                if c ~= nil and not (issecretvalue and issecretvalue(c)) and c == 0 then
                    a = 0
                end
            end
        end
        if frameData._zeroCountAlpha ~= a then
            frameData._zeroCountAlpha = a
            fontStr:SetAlpha(a)
        end
    end
end -- Count text visibility

-- Cold-path helper table for module-level behavior that benefits from a
-- shared dispatch surface without adding more direct top-level helpers.
local EAB_VTABLE = {
    ExtraBars = {},
    CooldownFonts = {},
    Hover = {},
    MainBarPageSync = {},
}
mod.EAB_VTABLE = EAB_VTABLE

ABAR.VisibilityCompat = ABAR.VisibilityCompat or {}

-------------------------------------------------------------------------------
--  Upvalues
-------------------------------------------------------------------------------
local _G = _G
local ipairs, pairs, type, pcall = ipairs, pairs, type, pcall
local abs, ceil, floor, min, max = math.abs, math.ceil, math.floor, math.min, math.max
local wipe, tinsert = wipe, table.insert
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After

-- External weak-keyed lookup for per-frame state (avoids writing custom
-- properties onto Blizzard-owned frame tables, which causes taint).
-- Stored on ns, not in a file-scope local.
mod._eabFD = setmetatable({}, { __mode = "k" })
function mod.EFD(widget)
    local skinData = mod._eabFD[widget]
    if not skinData then
        skinData = {}
        mod._eabFD[widget] = skinData
    end
    return skinData
end

-- Local alias for hot-path EFD access
local EFD = mod.EFD

-- Empty-slot parks live in EFD(btn).parkA0, so no decision reads a button's
-- alpha (another addon may write a secret one there). nil = our last write was
-- alpha 1, or there was none (default 1). 1 = we wrote alpha 0. 2 = we wrote
-- alpha 0 on a button the secure un-park code can reveal; that code sets alpha 1
-- on every hidden->shown edge, so the button is parked only while hidden. Our
-- own Show() keeps alpha, so each Lua Show site turns a surfaced 2 into 1.
function mod._eabParked(button)
    local skinData = mod._eabFD[button]
    local p = skinData and skinData.parkA0
    if p == 2 then
        return not button:IsShown()
    end
    return p == 1
end

-- Record an alpha-0 park on btn, right after the write. afterOwnHide: our
-- out-of-combat Hide() came after the 0, and the secure OnHide re-check can
-- re-show the button at alpha 1 inside that Hide; 2 covers both outcomes.
function mod._eabMarkParked(button, details, afterOwnHide)
    local revealable = not details.isStance and not details.isPetBar
    EFD(button).parkA0 = (revealable and (afterOwnHide or not button:IsShown())) and 2 or 1
end

-- The style Action Bars render: "cui" | "blizzard" | "classic". A LIVE
-- profile read, no latch: the Style page reloads the UI on every change, so
-- build-time gating is safe. "cui" without a profile; both flags set resolves
-- classic. Stock-mode sites ask `~= "cui"`, kit sites ask `== "classic"`.
function mod.AB_Style()
    local profile = ABAR.db and ABAR.db.profile
    if not profile then
        return "cui"
    end
    return (profile.useClassicStyle and "classic") or (profile.useBlizzardStyle and "blizzard") or "cui"
end

-- The WoW Forever variant of Blizzard Style (the Forever client only): the
-- bars render Blizzard Style (AB_Style() stays "blizzard", every stock site
-- is unchanged) and the profile's sibling useForeverStyle flag, set together
-- with the Blizzard flag, adds the Forever-only pieces. A LIVE read like
-- AB_Style; false on every other client.
function mod.AB_Forever()
    if CludesUI.IS_FOREVER ~= true then
        return false
    end
    local profile = ABAR.db and ABAR.db.profile
    if not (profile and profile.useForeverStyle == true) then
        return false
    end
    return mod.AB_Style() == "blizzard"
end

-- WoW Forever's frame and dividers behind a bar (Bar Frame), under
-- the variant only: the bar's own foreverBarBg. nil reads the bar's default:
-- Action Bar 1 follows the profile-wide foreverHideBarBg (shown unless it is
-- set), every other bar is off.
function mod.AB_ForeverBg(key)
    if not mod.AB_Forever() then
        return false
    end
    local profile = ABAR.db.profile
    local cfg = profile.bars and profile.bars[key]
    local val = cfg and cfg.foreverBarBg
    if val == nil then
        val = key == "MainBar" and profile.foreverHideBarBg ~= true
    end
    return val and true or false
end

-- SetAtlas for a stock-look texture: CludesUI.StockAtlas (retail art
-- where the Forever client swaps the name), native under the WoW Forever
-- look. Plain SetAtlas on retail.
function mod.AB_StockAtlas(texture, label, ...)
    if mod.AB_Forever() then
        return texture:SetAtlas(label, ...)
    end
    return CludesUI.StockAtlas(texture, label, ...)
end

-- The button shape the bar LAYOUT sizes for. Stock styles draw no custom
-- shape (ApplyShapesForBar and the options preview skip it), so their
-- buttons take neither the shape expansion nor the Cropped squash, whatever
-- the CludesUI-style setting holds. Icon Size itself applies in every
-- style (stock buttons scale their native art to it).
function mod.AB_LayoutShape(cfg)
    if mod.AB_Style() ~= "cui" then
        return "none"
    end
    return (cfg and cfg.buttonShape) or "none"
end
local RegisterStateDriver = RegisterStateDriver
local RegisterAttributeDriver = RegisterAttributeDriver
local GetBindingKey = GetBindingKey
local NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS or 12

-------------------------------------------------------------------------------
--  Bar configuration
-------------------------------------------------------------------------------
local BAR_CONFIG = {
    -- nativeMainBar: MainBar buttons keep native IDs (1-12), action via
    -- CalculateAction path 1; the bar's _onstate-page handler sets actionpage
    -- from the restricted env for form/vehicle/override paging. Keys flow via
    -- Blizzard's native ActionButtonDown/Up -> GetActionButtonForID -> _G["ActionButton"..id].
    {
        key = "MainBar",
        label = "Action Bar 1 (Main)",
        barID = 1,
        count = 12,
        blizzBtnPrefix = "ActionButton",
        blizzFrame = "MainMenuBar",
        nativeMainBar = true,
    },
    -- nativeActionPage: the Blizzard actionpage for this bar's slot range.
    -- Buttons keep native IDs; action = ID + (page-1)*12 (CalculateAction path
    -- 1). Keys flow via native MultiActionButtonDown/Up so UseAction gets
    -- isKeyPress=true (required for press-and-hold casting).
    {
        key = "Bar2",
        label = "Action Bar 2",
        barID = 2,
        count = 12,
        blizzBtnPrefix = "MultiBarBottomLeftButton",
        blizzFrame = "MultiBarBottomLeft",
        nativeActionPage = 6,
    },
    {
        key = "Bar3",
        label = "Action Bar 3",
        barID = 3,
        count = 12,
        blizzBtnPrefix = "MultiBarBottomRightButton",
        blizzFrame = "MultiBarBottomRight",
        nativeActionPage = 5,
    },
    {
        key = "Bar4",
        label = "Action Bar 4",
        barID = 4,
        count = 12,
        blizzBtnPrefix = "MultiBarRightButton",
        blizzFrame = "MultiBarRight",
        nativeActionPage = 3,
    },
    {
        key = "Bar5",
        label = "Action Bar 5",
        barID = 5,
        count = 12,
        blizzBtnPrefix = "MultiBarLeftButton",
        blizzFrame = "MultiBarLeft",
        nativeActionPage = 4,
    },
    {
        key = "Bar6",
        label = "Action Bar 6",
        barID = 6,
        count = 12,
        blizzBtnPrefix = "MultiBar5Button",
        blizzFrame = "MultiBar5",
        nativeActionPage = 13,
    },
    {
        key = "Bar7",
        label = "Action Bar 7",
        barID = 7,
        count = 12,
        blizzBtnPrefix = "MultiBar6Button",
        blizzFrame = "MultiBar6",
        nativeActionPage = 14,
    },
    {
        key = "Bar8",
        label = "Action Bar 8",
        barID = 8,
        count = 12,
        blizzBtnPrefix = "MultiBar7Button",
        blizzFrame = "MultiBar7",
        nativeActionPage = 15,
    },
    -- Bar9/Bar10: extra bars with NO native Blizzard frame; our own
    -- EABButton<slot> buttons, paged like Bars 2-8 via explicit-action +
    -- _childupdate-eab-page. customPage = the action page the slots live on:
    -- Bar9 = page 2 (slots 13-24, so converts' existing spells stay placed),
    -- Bar10 = page 10 (slots 109-120). Neither page has a Blizzard binding
    -- command, so keys route via SetOverrideBindingClick through the
    -- CUI_BAR9/10_BUTTON commands in Bindings.xml.
    { key = "Bar9", label = "Action Bar 9", barID = 0, count = 12, customPage = 2 },
    { key = "Bar10", label = "Action Bar 10", barID = 0, count = 12, customPage = 10 },
    {
        key = "StanceBar",
        label = "Stance Bar",
        barID = 0,
        count = 10,
        blizzBtnPrefix = "StanceButton",
        blizzFrame = "StanceBar",
        isStance = true,
    },
    {
        key = "PetBar",
        label = "Pet Bar",
        barID = 0,
        count = 10,
        blizzBtnPrefix = "PetActionButton",
        blizzFrame = "PetActionBar",
        isPetBar = true,
    },
}

-- Aliases for the options file (which references these field names)
for _, details in ipairs(BAR_CONFIG) do
    details.buttonPrefix = details.blizzBtnPrefix
    details.frameName = details.blizzFrame
    details.fallbackFrame = nil
end

local EXTRA_BARS = {
    {
        key = "MicroBar",
        label = "Micro Menu Bar",
        frameName = "MicroMenuContainer",
        hoverFrame = "MicroMenu",
        visibilityOnly = true,
        blizzOwnedVisibility = true,
    },
    {
        key = "BagBar",
        label = "Bag Bar",
        frameName = "BagsBar",
        visibilityOnly = true,
        blizzOwnedVisibility = true,
    },
    {
        key = "QueueStatus",
        label = "Queue Status",
        frameName = "QueueStatusButton",
        visibilityOnly = true,
        blizzOwnedVisibility = true,
        noManagedVisibility = true,
    },
    { key = "XPBar", label = "XP Bar", visibilityOnly = true, isDataBar = true },
    { key = "RepBar", label = "Reputation Bar", visibilityOnly = true, isDataBar = true },
    { key = "FavorBar", label = "House Favor Bar", visibilityOnly = true, isDataBar = true },
    {
        key = "ExtraActionButton",
        label = "Extra Action Button",
        visibilityOnly = true,
        isBlizzardMovable = true,
    },
    {
        key = "EncounterBar",
        label = "Encounter Bar",
        visibilityOnly = true,
        isBlizzardMovable = true,
    },
}
-- WoW Forever has no extra action bar (no binding, no Edit Mode system for
-- it): no holder, mover or visibility row there, and its container is left
-- to Blizzard.
if CludesUI.IS_FOREVER then
    for index = #EXTRA_BARS, 1, -1 do
        if EXTRA_BARS[index].key == "ExtraActionButton" then
            table.remove(EXTRA_BARS, index)
        end
    end
end

local ALL_BARS = {}
for _, details in ipairs(BAR_CONFIG) do
    ALL_BARS[#ALL_BARS + 1] = details
end
for _, details in ipairs(EXTRA_BARS) do
    ALL_BARS[#ALL_BARS + 1] = details
end

local BAR_LOOKUP = {}
for _, details in ipairs(BAR_CONFIG) do
    BAR_LOOKUP[details.key] = details
end
for _, details in ipairs(EXTRA_BARS) do
    BAR_LOOKUP[details.key] = details
end

-- Expose AB bar keys immediately so unlock mode's ApplyAnchorPosition can gate
-- edge logic to CDM/AB without waiting for deferred RegisterWithUnlockMode.
if not CludesUI._abBarKeys then
    CludesUI._abBarKeys = {}
end
for _, details in ipairs(BAR_CONFIG) do
    CludesUI._abBarKeys[details.key] = true
end

local BAR_DROPDOWN_VALUES = {}
local BAR_DROPDOWN_ORDER = {}
do
    local _DROPDOWN_EXCLUDE = { ExtraActionButton = true, EncounterBar = true, QueueStatus = true }
    for _, details in ipairs(ALL_BARS) do
        if not _DROPDOWN_EXCLUDE[details.key] then
            BAR_DROPDOWN_VALUES[details.key] = details.label
            BAR_DROPDOWN_ORDER[#BAR_DROPDOWN_ORDER + 1] = details.key
        end
    end
end

local VISIBILITY_ONLY = {}
for _, details in ipairs(EXTRA_BARS) do
    VISIBILITY_ONLY[details.key] = true
end

local DATA_BAR = {}
for _, details in ipairs(EXTRA_BARS) do
    if details.isDataBar then
        DATA_BAR[details.key] = true
    end
end

mod.BAR_DROPDOWN_VALUES = BAR_DROPDOWN_VALUES
mod.BAR_DROPDOWN_ORDER = BAR_DROPDOWN_ORDER
mod.VISIBILITY_ONLY = VISIBILITY_ONLY
mod.DATA_BAR = DATA_BAR
mod.BAR_LOOKUP = BAR_LOOKUP
mod.ALL_BARS = ALL_BARS
mod.EXTRA_BARS = EXTRA_BARS

function ABAR.VisibilityCompat.ApplyMode(prefs, modeName)
    if not prefs then
        return "always"
    end

    modeName = modeName or "always"
    prefs.barVisibility = modeName
    prefs.alwaysHidden = (modeName == "never")

    local wasMouseover = prefs.mouseoverEnabled
    prefs.mouseoverEnabled = (modeName == "mouseover")
    if modeName == "mouseover" then
        if not prefs._savedBarAlpha then
            prefs._savedBarAlpha = prefs.mouseoverAlpha or 1
        end
        prefs.mouseoverAlpha = 0
    elseif wasMouseover and prefs._savedBarAlpha then
        prefs.mouseoverAlpha = prefs._savedBarAlpha
        prefs._savedBarAlpha = nil
    end

    prefs.combatHideEnabled = (modeName == "out_of_combat")
    prefs.combatShowEnabled = (modeName == "in_combat")
    return modeName
end

function ABAR.VisibilityCompat.Normalize(prefs)
    if not prefs then
        return "always"
    end
    if prefs.barVisibility then
        return ABAR.VisibilityCompat.ApplyMode(prefs, prefs.barVisibility)
    end
    if prefs.alwaysHidden then
        return ABAR.VisibilityCompat.ApplyMode(prefs, "never")
    end
    if prefs.mouseoverEnabled then
        return ABAR.VisibilityCompat.ApplyMode(prefs, "mouseover")
    end
    if prefs.combatShowEnabled then
        return ABAR.VisibilityCompat.ApplyMode(prefs, "in_combat")
    end
    if prefs.combatHideEnabled then
        return ABAR.VisibilityCompat.ApplyMode(prefs, "out_of_combat")
    end
    return ABAR.VisibilityCompat.ApplyMode(prefs, "always")
end

-- Effective Never for runtime gates: an applied Visibility override replaces the
-- saved mode, so a Never bar with an Always override is NOT hidden, and
-- an Always bar with a Never override is. Raw alwaysHidden/barVisibility reads stay
-- correct only where the SHARED value is meant (sync copies, the setter itself).
function ABAR.VisibilityCompat.IsNever(cfg)
    if not cfg then
        return false
    end
    local shade = CludesUI.VisOverrideValue(cfg)
    if shade then
        return shade == "never"
    end
    return (cfg.alwaysHidden or cfg.barVisibility == "never") and true or false
end

function ABAR.VisibilityCompat.Copy(dst, source, dstNoGroupModes)
    if not dst or not source then
        return
    end

    local modeName = ABAR.VisibilityCompat.Normalize(source)
    ABAR.VisibilityCompat.ApplyMode(dst, modeName)

    if modeName == "mouseover" then
        dst._savedBarAlpha = source._savedBarAlpha or source.mouseoverAlpha or 1
        dst.mouseoverAlpha = 0
    else
        dst.mouseoverAlpha = source.mouseoverAlpha
        dst._savedBarAlpha = nil
    end

    -- Show During Drag / Show When Spellbook Is Open travel with the copy
    -- (inert unless target mode is Never).
    dst.dragShow = source.dragShow
    dst.spellbookShow = source.spellbookShow

    -- Multi-select set travels with the copy (after ApplyMode, so scalar/set stay
    -- consistent). Group-axis items are stripped for targets that can't express them
    -- (Pet Bar); the stripped selection re-normalizes through the shared setter,
    -- routing the scalar back through ApplyMode to keep the legacy booleans synced.
    if CludesUI and CludesUI.VisCopySelection then
        CludesUI.VisCopySelection(
            dst,
            source,
            "barVisibility",
            dstNoGroupModes and CludesUI.VIS_CAPS_NO_GROUP or nil,
            ABAR.VisibilityCompat.ApplyMode
        )
    else
        dst.visibilityModes = nil
        dst.visibilityMatch = source.visibilityMatch or nil
    end
end

-------------------------------------------------------------------------------
--  Media paths
-------------------------------------------------------------------------------
local MEDIA_DIR = "Interface\\AddOns\\CludesUIActionBars\\Media\\"
local FONT_PATH = (CludesUI.GetFontPath("actionBars"))
    or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
local HIGHLIGHT_TEXTURES = {
    MEDIA_DIR .. "highlight-2.png",
    MEDIA_DIR .. "highlight-3.png",
    MEDIA_DIR .. "highlight-4.png",
}
mod.HIGHLIGHT_TEXTURES = HIGHLIGHT_TEXTURES

local SHAPE_MASKS = CludesUI.SHAPE_MASKS
local SHAPE_BORDERS = CludesUI.SHAPE_BORDERS
local SHAPE_INSETS = CludesUI.SHAPE_INSETS
local SHAPE_ZOOM_DEFAULTS = {
    none = 5.5,
    cropped = 2,
    square = 6.0,
    circle = 6.0,
    csquare = 6.0,
    diamond = 6.0,
    hexagon = 6.0,
    portrait = 6.0,
    shield = 6.0,
}
mod.SHAPE_ZOOM_DEFAULTS = SHAPE_ZOOM_DEFAULTS
mod.SHAPE_MASKS = SHAPE_MASKS
mod.SHAPE_BORDERS = SHAPE_BORDERS

local SHAPE_BTN_EXPAND = 10
local SHAPE_ICON_EXPAND = 7
mod.SHAPE_BTN_EXPAND = SHAPE_BTN_EXPAND
mod.SHAPE_ICON_EXPAND = SHAPE_ICON_EXPAND

local SHAPE_ICON_EXPAND_OFFSETS = {
    circle = 2,
    csquare = 4,
    diamond = 2,
    hexagon = 4,
    portrait = 2,
    shield = 2,
    square = 4,
}
mod.SHAPE_ICON_EXPAND_OFFSETS = SHAPE_ICON_EXPAND_OFFSETS
mod.SHAPE_INSETS = SHAPE_INSETS

-- Per-shape edge scale so the circular edge path stays inside the mask.
local SHAPE_EDGE_SCALES = {
    circle = 0.75,
    csquare = 0.75,
    diamond = 0.70,
    hexagon = 0.65,
    portrait = 0.70,
    shield = 0.65,
    square = 0.75,
}

-- Border thickness mapping
mod.BORDER_THICKNESS = {
    none = { regular = 0, shape = 0 },
    thin = { regular = 1, shape = 0 },
    normal = { regular = 2, shape = 0 },
    heavy = { regular = 3, shape = 0 },
    strong = { regular = 4, shape = 7 },
}
mod.BORDER_THICKNESS_ORDER = { "none", "thin", "normal", "heavy", "strong" }
mod.BORDER_THICKNESS_LABELS =
    { none = "None", thin = "Thin", normal = "Normal", heavy = "Heavy", strong = "Strong" }
mod.BORDER_THICKNESS_DEFAULT_REGULAR = "thin"
mod.BORDER_THICKNESS_DEFAULT_SHAPE = "strong"

-- Per-addon border texture defaults (central registry)
CludesUI.RegisterBorderDefaults("actionbars", CludesUI.BORDER_DEFAULTS_BUTTONS)

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
local defaultSet = {
    profile = {
        squareIcons = true,
        iconZoom = 5.5,
        selectedBar = "MainBar",
        cooldownEdgeSize = 2.1,
        cooldownEdgeColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        cooldownEdgeUseClassColor = false,
        pushedTextureType = 2,
        pushedUseClassColor = false,
        pushedCustomColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        pushedBorderSize = 4,
        highlightTextureType = 2,
        highlightUseClassColor = false,
        highlightCustomColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        highlightBorderSize = 4,
        -- Match Bar Border: on bars with a textured Border Style, a press
        -- (pushed Border type), a hover (highlight Border type) or the active
        -- spell lights up a tinted copy of the button's own border instead of
        -- the flat lines or the checked fill. Off = today's look.
        pushedBorderMatchBar = false,
        highlightBorderMatchBar = false,
        castHighlightBorder = false,
        showCastHighlight = true,
        -- Show the recharge countdown on charge spells while a charge is
        -- still banked (mirrors "Show numbers for cooldowns" CVar onto the
        -- recharge timer). Off = Blizzard default (number only at 0 charges).
        showChargeRechargeNumbers = true,
        desaturateOnCooldown = false,
        -- 100 = disabled (zero cost); below 100 dims the icon to that opacity
        -- while on a real cooldown, same detection as Desaturate on Cooldown.
        alphaWhenOnCD = 100,
        -- Cooldown swipe colour+opacity; defaults mirror Blizzard (black, 80%)
        -- so applying them is a no-op until customized.
        cdSwipeColor = { r = 0, g = 0, b = 0 },
        cdSwipeAlpha = 80,
        procGlowType = 1,
        procGlowColor = { r = 1, g = 0.776, b = 0.376 },
        procGlowUseClassColor = false,
        procGlowEnabled = false,
        -- Assisted Highlight ring: extra pixels per side beyond the button
        -- footprint. 0 = Blizzard's size (art sits exactly on the button).
        -- Positive pushes the blue swirl outward so it reads apart from a proc
        -- glow on the same edge; negative pulls it inward.
        assistGlowOutset = 0,
        -- How the Assisted Highlight is drawn: 1 = Blizzard's glow ring only
        -- (default, unchanged behavior), 2 = flat tint over the whole button
        -- instead, 3 = both. The overlay leaves the button edge free for the
        -- proc glow, which is the point of offering it.
        -- Optional custom Assisted Highlight glows are purely additive. A value
        -- of 0 keeps the existing assistGlowStyle path and its current behavior.
        assistGlowType = 0,
        assistGlowColor = { r = 0.15, g = 0.5, b = 1 },
        assistGlowUseClassColor = false,
        assistGlowStyle = 1,
        -- On Cropped bars, size the glow ring to the button's rectangle
        -- instead of scaling the square art by width. Off = today's ring.
        assistGlowFitCropped = false,
        assistGlowOverlayColor = { r = 0.15, g = 0.5, b = 1 },
        assistGlowOverlayAlpha = 30,
        useBlizzardStyle = false,
        useClassicStyle = false,
        showBlizzIconBg = false,
        blizzIconBgAlpha = 1,
        -- Flat color background behind every button icon; defaults keep the
        -- legacy look (0.15 gray at 50%) so nothing changes until customized.
        slotBgColor = { r = 0.15, g = 0.15, b = 0.15 },
        slotBgOpacity = 50,
        hideCastingAnimations = true,
        mouseoverShowAll = false,
        barPositions = {},
        bars = {},
    },
}

for _, details in ipairs(BAR_CONFIG) do
    defaultSet.profile.bars[details.key] = {
        enabled = true,
        borderEnabled = true,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        borderSize = 1,
        borderClassColor = false,
        borderTexture = "solid",
        borderThickness = "thin",
        borderBehind = false,
        -- Textured border drawn above proc glows, the assisted highlight and
        -- the cooldown swipe. Show Behind wins over it.
        borderAboveEffects = false,
        buttonPadding = 2,
        buttonWidth = 0,
        buttonHeight = 0,
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        -- Optional Advanced Fade layer: on while a condition is checked (none by
        -- default, which keeps the native alpha behavior).
        fadeMaxAlpha = 1,
        fadeInSpeed = 0.15,
        fadeOutSpeed = 0.15,
        advancedFadeConditions = {},
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        barVisibility = "always",
        dragShow = false,
        -- Hide Bar When Using Gamepad: off by default; inert until a
        -- controller is connected with gamepad support enabled.
        gamepadHideBar = false,
        visHideHousing = false,
        visOnlyInstances = false,
        visHideMounted = false,
        visHideNoTarget = false,
        visHideNoEnemy = false,
        hideKeybind = false,
        keybindFontSize = 12,
        keybindFontColor = { r = 1, g = 1, b = 1 },
        hideMacroText = false,
        macroFontSize = 12,
        macroFontColor = { r = 1, g = 1, b = 1 },
        countFontSize = 12,
        countFontColor = { r = 1, g = 1, b = 1 },
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
        overrideNumIcons = nil,
        overrideNumRows = nil,
        growDirection = "up",
        -- Legacy flag, superseded by iconOrder. iconOrder has no default:
        -- nil means "derive from reverseIconOrder" so old profiles keep layout.
        reverseIconOrder = false,
        alwaysShowButtons = true,
        showPagingArrows = false,
        skipVisiblePagingBars = true,
        pagingArrowsRight = false,
        -- Paging Arrows off: the arrows still show while bar 1 is on a page
        -- the player paged to (LayoutPagingFrame's paged driver).
        pagingArrowsWhilePaged = true,
        paging = {},
        -- Auto-paging opt-outs (MainBar only; see BuildPagingConditions).
        disableFormPaging = false,
        disableSkyridingPaging = false,
        bgEnabled = false,
        bgColor = { r = 0, g = 0, b = 0, a = 0.5 },
        bgBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        bgBorderTexture = "solid",
        bgBorderBehind = false,
        bgBorderSize = 1,
        bgBorderThickness = "none",
        bgMultiplierX = 1,
        bgMultiplierY = 1,
        bgExpandDirectionX = "right",
        bgExpandDirectionY = "up",
        outOfRangeColoring = false,
        outOfRangeColor = { r = 0.8, g = 0.1, b = 0.1 },
        buttonShape = "none",
        shapeBorderEnabled = true,
        shapeBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        shapeBorderSize = 7,
        shapeBorderClassColor = nil,
        iconZoom = nil,
        keybindOffsetX = 0,
        keybindOffsetY = 0,
        macroOffsetX = 0,
        macroOffsetY = 0,
        countOffsetX = 0,
        countOffsetY = 0,
        -- Text anchors: nil or false keeps the stock placement (keybind top-right,
        -- charges bottom-right, macro name bottom-center). Any value from
        -- EAB.TEXT_ANCHOR_ORDER pins the text to that button corner/edge and
        -- justifies it the same way, so multi-digit text grows away from it.
        keybindAnchor = nil,
        countAnchor = nil,
        macroAnchor = nil,
        cooldownFontSize = 12,
        cooldownTextXOffset = 0,
        cooldownTextYOffset = 0,
        cooldownTextColor = { r = 1, g = 1, b = 1 },
        disableTooltips = false,
        showRankIcon = false,
        orientation = "horizontal",
        numIcons = 12,
        numRows = 1,
        targetWidth = 0,
        targetHeight = 0,
        -- End caps (the End Caps checklist and its cog) and WoW Forever's bar
        -- background, per bar. nil reads the bar's default (ns.AB_CapsSides,
        -- ns.AB_CapsVal, ns.AB_ForeverBg): Action Bar 1 falls back to the
        -- profile-wide keys, every other bar starts without them. The micro
        -- menu and bag bar read the same endCap* keys; the profile keys
        -- endCapSpanLeft / endCapSpanRight (written only by the first-install
        -- capture, in no defaults table) move bar 1's defaults to another bar.
        endCapLeft = nil,
        endCapRight = nil,
        endCapArt = nil,
        endCapScale = nil,
        endCapOffsetX = nil,
        endCapOffsetY = nil,
        foreverBarBg = nil,
    }
end

-- Bar9/Bar10 default to Hidden visibility (what the Visibility dropdown's
-- Hidden option sets) so they never show until the user picks another mode.
for _, k in ipairs({ "Bar9", "Bar10" }) do
    local b = defaultSet.profile.bars[k]
    if b then
        b.barVisibility = "never"
        b.alwaysHidden = true
    end
end

for _, details in ipairs(EXTRA_BARS) do
    defaultSet.profile.bars[details.key] = {
        mouseoverEnabled = false,
        mouseoverAlpha = 1,
        -- Optional Advanced Fade layer: on while a condition is checked (none by
        -- default, which keeps the native alpha behavior).
        fadeMaxAlpha = 1,
        fadeInSpeed = 0.15,
        fadeOutSpeed = 0.15,
        advancedFadeConditions = {},
        combatShowEnabled = false,
        combatHideEnabled = false,
        housingHideEnabled = false,
        alwaysHidden = false,
        mouseoverSpeed = 0.15,
        clickThrough = false,
    }
    if details.isDataBar then
        local skinData = defaultSet.profile.bars[details.key]
        skinData.width = 400
        skinData.height = 18
        skinData.orientation = "HORIZONTAL"
        skinData.clickThrough = true -- default on for data bars
        -- Custom Border (opt-in): off keeps the built-in 1px black line. The
        -- style keys below are what the option starts from (solid, thin, black)
        -- and render that same line. Offsets, shifts and borderThicknessPx have
        -- no default (nil = the style's own).
        skinData.customBorder = false
        skinData.borderTexture = "solid"
        skinData.borderThickness = "thin"
        skinData.borderColor = { r = 0, g = 0, b = 0, a = 1 }
        skinData.borderBehind = false
    end
end
-- House Favor bar ships opt-in: hidden until the user turns it on.
if defaultSet.profile.bars.FavorBar then
    defaultSet.profile.bars.FavorBar.alwaysHidden = true
end

-- Blizzard data bar override (let Blizzard control XP + Rep via Edit Mode). WoW
-- Forever keeps Blizzard's own bars by default (the per-client default rule).
defaultSet.profile.useBlizzardDataBars = (CludesUI.IS_FOREVER == true)
-- Equipped Item Color (Effects > Item Information): on by default on WoW Forever only.
defaultSet.profile.showEquippedBorder = (CludesUI.IS_FOREVER == true)
-- Stock vehicle / override bar suppression. Opt-in, and inert until switched
-- on: no frame, no events and no hook exist while it is false.
defaultSet.profile.hideBlizzardVehicleBar = false

mod.defaults = defaultSet

-------------------------------------------------------------------------------
--  Utility helpers
-------------------------------------------------------------------------------
local function SafeEnableMouse(widget, enable)
    if not widget then
        return
    end
    if widget.IsProtected and widget:IsProtected() and InCombatLockdown() then
        return
    end
    if widget.SetMouseClickEnabled then
        widget:SetMouseClickEnabled(enable)
        widget:SetMouseMotionEnabled(enable)
    else
        widget:EnableMouse(enable)
    end
end

-- Like SafeEnableMouse but only mouse motion (OnEnter/OnLeave); keeps
-- click-through so clicks pass to frames behind.
local function SafeEnableMouseMotionOnly(widget, enable)
    if not widget then
        return
    end
    if widget.IsProtected and widget:IsProtected() and InCombatLockdown() then
        return
    end
    if widget.SetMouseClickEnabled then
        widget:SetMouseClickEnabled(false)
        widget:SetMouseMotionEnabled(enable)
    else
        widget:EnableMouse(enable)
    end
end

-- The alpha THIS addon last wrote to each fade target (bar frames, data bar
-- and extra bar holders, MicroMenuContainer, BagsBar). Fades start from here,
-- never from GetAlpha: another addon may write a secret alpha onto these
-- frames, and math on that read throws. A side table, not a frame field: two
-- targets are Blizzard frames. No entry = never written by us = the default 1.
-- Every alpha write to a fade target goes through the fader, StopFade(frame,
-- alpha), or a record beside its SetAlpha.
local _fadeAlpha = {}

-- The micro menu's and bag bar's end caps ride our own follower frame, not
-- the Blizzard frame, so every alpha written to that Blizzard frame is copied
-- onto their cap layer: ns._abFadeTwin[blizzFrame] = cap layer (weak keys),
-- set only while that bar shows caps (ns.AB_ExtraCaps); nil otherwise.
function mod.AB_FadeTwin(widget, a)
    local tw = mod._abFadeTwin
    local hgt = tw and tw[widget]
    if hgt then
        hgt:SetAlpha(a)
    end
end

-- The one fader for every fade target: a shared OnUpdate queue.
-- AnimationGroups spread taint on Blizzard frames and cost 0.7-4ms to start
-- on secure bar frames.
local _extraFadeQueue = {}
local _extraFadeFrame = CreateFrame("Frame")

local function _ExtraFadeOnUpdate(_, elapsed)
    local anyActive = false
    local tw = mod._abFadeTwin
    for widget, details in pairs(_extraFadeQueue) do
        details.elapsed = details.elapsed + elapsed
        local t = details.elapsed / details.duration
        local a
        if t >= 1 then
            a = details.toAlpha
            widget:SetAlpha(a)
            _fadeAlpha[widget] = a
            _extraFadeQueue[widget] = nil
        else
            -- Smooth in/out easing
            local e = t < 0.5 and (2 * t * t) or (1 - (-2 * t + 2) ^ 2 / 2)
            a = details.fromAlpha + (details.toAlpha - details.fromAlpha) * e
            widget:SetAlpha(a)
            _fadeAlpha[widget] = a
            anyActive = true
        end
        if tw then
            local hgt = tw[widget]
            if hgt then
                hgt:SetAlpha(a)
            end
        end
    end
    if not anyActive then
        _extraFadeFrame:SetScript("OnUpdate", nil)
    end
end

-- Drag visibility state (file-scope so ApplyAll can reset strata on spec change)
local _dragState = { visible = false, strataCache = {} }

-- Grid show/hide state (show empty slots during spell drag)
local _gridState = {
    shown = false,
    visPending = false,
    spellsPending = false,
    want = nil,
    settlePending = false,
    showFns = {},
    hideFns = {},
}

-- Grid edges arrive in pairs from scripted cursor use: every
-- PickupContainerItem fires ACTIONBAR_SHOWGRID and every place fires
-- ACTIONBAR_HIDEGRID, hundreds of pairs per frame during a bag sort, and
-- applying each edge re-walked every bar and flipped mouseover bars between
-- alpha 1 and 0 (the visible blinking). Settle instead: a pair that nets back
-- to the applied state (_gridState.shown, owned by the appliers) costs
-- nothing, a real drag still surfaces the grid 50ms later. Appliers register
-- into showFns/hideFns at their own definition sites.
function mod.EABQueueGrid(show)
    _gridState.want = show
    if _gridState.settlePending then
        return
    end
    _gridState.settlePending = true
    C_Timer_After(0.05, function()
        _gridState.settlePending = false
        local wanted = _gridState.want
        if wanted == _gridState.shown then
            return
        end
        local entries = wanted and _gridState.showFns or _gridState.hideFns
        for index = 1, #entries do
            entries[index]()
        end
    end)
end
local _quickKeybindState = { open = false, closePending = false, art = {}, FinishClose = nil }

local function ShouldQuickKeybindSurfaceBar(cfg)
    if not _quickKeybindState.open or not cfg or cfg.enabled == false then
        return false
    end

    -- Surfaces bars hidden by transient runtime rules, but explicit "Never" wins.
    -- Hide Bar When Using Gamepad is not a Never: its verdict (EAB._padHide) is
    -- off while this mode is open, so a controller player can bind those bars.
    return not ABAR.VisibilityCompat.IsNever(cfg)
end

local function FadeTo(widget, toAlpha, duration)
    duration = duration or 0.1
    local current = _fadeAlpha[widget] or 1
    if abs(current - toAlpha) < 0.01 then
        widget:SetAlpha(toAlpha)
        _fadeAlpha[widget] = toAlpha
        mod.AB_FadeTwin(widget, toAlpha)
        return
    end
    local existing = _extraFadeQueue[widget]
    if existing and existing.toAlpha == toAlpha then
        return
    end
    _extraFadeQueue[widget] = {
        fromAlpha = current,
        toAlpha = toAlpha,
        duration = duration,
        elapsed = 0,
    }
    _extraFadeFrame:SetScript("OnUpdate", _ExtraFadeOnUpdate)
end

-- Stop a running fade. With an alpha, also paint and record it: the one path
-- for a direct write that must win over a fade.
local function StopFade(widget, alpha)
    _extraFadeQueue[widget] = nil
    if alpha then
        widget:SetAlpha(alpha)
        _fadeAlpha[widget] = alpha
        mod.AB_FadeTwin(widget, alpha)
    end
end

-- Unlock mode blanks a bar for one frame around a resize (0, then 1) and
-- reports both writes here, so a later fade still starts where the frame
-- really is. Frames this addon never wrote stay untracked.
function CludesUI._EABNoteAlpha(widget, a)
    if _fadeAlpha[widget] ~= nil then
        _fadeAlpha[widget] = a
    end
end

-- Resolve borderThickness dropdown to actual pixel values. The ONE size source
-- for a bar's square border: every paint path (bar borders, the shape repaint,
-- the flyout, the keybind-mode restore) takes both results from here. Second
-- result: the exact size from borderThicknessPx (CludesUI.BorderPx) while it
-- still pairs with this step and the bar's texture, else nil = the legacy path.
-- A custom shape's ring is on/off only: no exact size there.
local function ResolveBorderThickness(cfg)
    local thickness = cfg.borderThickness or "thin"
    local record = mod.BORDER_THICKNESS[thickness]
    if not record then
        record = mod.BORDER_THICKNESS["thin"]
    end
    local shapeKey = cfg.buttonShape or "none"
    if shapeKey ~= "none" and shapeKey ~= "cropped" then
        if thickness == "thin" and cfg.shapeBorderSize and cfg.shapeBorderSize ~= record.shape then
            return cfg.shapeBorderSize, nil
        end
        return record.shape, nil
    else
        local sz = record.regular
        return sz, CludesUI.BorderPx(cfg.borderThicknessPx, sz, cfg.borderTexture)
    end
end
mod.ResolveBorderThickness = ResolveBorderThickness

-- Condense keybind text (CTRL-2 C2, Mouse Button 4 M4, etc.)
local function FormatHotkeyText(textValue)
    if not textValue or textValue == "" then
        return ""
    end
    -- Gamepad binds resolve to glyph markup (no atlas name matches a substitution
    -- below); keyboard binds keep the raw tokens the substitutions are written against.
    local resolved = GetBindingText(textValue, 1)
    if resolved and resolved:find("|A:", 1, true) then
        textValue = resolved
    end
    textValue = textValue:gsub("CTRL%-", "C")
    textValue = textValue:gsub("ALT%-", "A")
    textValue = textValue:gsub("SHIFT%-", "S")
    textValue = textValue:gsub("META%-", "M") -- Mac Command key (CMD-E -> ME)
    textValue = textValue:gsub("Mouse Button ", "M")
    textValue = textValue:gsub("MOUSEWHEELUP", "MwU")
    textValue = textValue:gsub("MOUSEWHEELDOWN", "MwD")
    textValue = textValue:gsub("CAPSLOCK", "Caps")
    -- Specific NUMPAD keys must be handled before the generic NUMPAD prefix,
    -- or the prefix replacement makes them unmatchable (N. showed as NDECIMAL).
    textValue = textValue:gsub("NUMPADDECIMAL", "N.")
    textValue = textValue:gsub("NUMPADPLUS", "N+")
    textValue = textValue:gsub("NUMPADMINUS", "N-")
    textValue = textValue:gsub("NUMPADMULTIPLY", "N*")
    textValue = textValue:gsub("NUMPADDIVIDE", "N/")
    textValue = textValue:gsub("NUMPAD", "N")
    textValue = textValue:gsub("BUTTON", "M")
    return textValue
end

-- Check if a button has an action assigned
local function ButtonHasAction(button, prefixText)
    if not button then
        return false
    end
    if button.HasAction then
        local success, has = pcall(button.HasAction, button)
        if success then
            return has
        end
    end
    return button.icon and button.icon:IsShown() and button.icon:GetTexture() ~= nil
end
mod.ButtonHasAction = ButtonHasAction

-- An empty slot for the hide-empty rule (Always Show Buttons off). A pet slot
-- counts as empty only while a pet bar is out: with no pet the [pet] driver
-- already hides the whole bar, and a pet button hidden out of combat cannot be
-- shown again until combat ends (the buttons are secure), so a pet called in
-- combat would bring back an empty bar.
function mod.AB_EmptySlot(button, details)
    if details.isPetBar and not PetHasActionBar() then
        return false
    end
    return not ButtonHasAction(button, details.blizzBtnPrefix)
end

-- Force-paint a Blizzard-native button's cooldown swipe/text from current action state.
-- The stock cooldown broadcasters are killed at load, so buttons we don't rebuild
-- (OverrideActionBarButton1-6, ExtraActionButton1) would show no swipe/number for an
-- already-active cooldown until the next broadcast. Reads the slot via
-- GetAttribute("action"), never btn.action (protected -- reading it in combat taints).
-- Clears when no active duration resolves so a stale swipe is never left behind.
local function ForceCooldownPaint(button)
    if not button then
        return
    end
    local cooldown = button.cooldown
    local actionSlot = button:GetAttribute("action")
    if cooldown and actionSlot and HasAction(actionSlot) and C_ActionBar and C_ActionBar.GetActionCooldown then
        local cdInfo = C_ActionBar.GetActionCooldown(actionSlot)
        local durObj = cdInfo
            and cdInfo.isActive
            and C_ActionBar.GetActionCooldownDuration
            and C_ActionBar.GetActionCooldownDuration(actionSlot)
        if durObj then
            cooldown:SetCooldownFromDurationObject(durObj)
        else
            cooldown:Clear()
        end
    end
end
mod.ForceCooldownPaint = ForceCooldownPaint

-- Paint the One Button Assist button's cooldown from the SUGGESTED spell rather
-- than from its action slot. That button draws two things from two sources: the
-- icon is the suggestion sampled on the assist ticker, while the slot's own
-- cooldown mirrors whatever the engine is suggesting at the instant it is read.
-- The suggestion moves faster than the 5 Hz tick, so consecutive reads land on
-- different abilities and the swipe flips on and off under a still icon.
-- spellID nil means no suggestion, where RepaintAssistIcons falls the icon back
-- to the slot's own texture, so the swipe follows it there. isActive is
-- NeverSecret and the duration object carries the timing: no secret is read.
-- On ns, not a local.
mod.PaintAssistCooldown = function(button, spellId)
    if not spellId then
        return ForceCooldownPaint(button)
    end
    local cooldown = button and button.cooldown
    if not cooldown then
        return
    end
    local details = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellId)
    local durObj = details
        and details.isActive
        and C_Spell.GetSpellCooldownDuration
        and C_Spell.GetSpellCooldownDuration(spellId)
    if durObj then
        cooldown:SetCooldownFromDurationObject(durObj)
    else
        cooldown:Clear()
    end
end

-- Stock bar frames to disable. Each entry carries flags for how to handle it:
--   retainEvents  = true  -> do NOT unregister events (needed for override state)
local STOCK_BAR_DISPOSAL = {
    { name = "MainActionBar", retainEvents = true },
    { name = "MainMenuBar" },
    { name = "MultiBarBottomLeft" },
    { name = "MultiBarBottomRight" },
    { name = "MultiBarRight" },
    { name = "MultiBarLeft" },
    { name = "MultiBar5" },
    { name = "MultiBar6" },
    { name = "MultiBar7" },
    { name = "StanceBar" },
    { name = "PetActionBar" },
}

-- Main-chunk locals the other CUI_ActionBars_*.lua files re-import by name.
-- Each of those files adds the entry points the files behind it need (bottom
-- of that file).
-- The three ...Setters lists: a file that keeps one of these values registers
-- a setter here; the place that assigns it writes through SetSecureRefsReady,
-- SetPagingFrame or SetIsApplyingAll, built below, which runs them all.
CludesUI.NewInternals(mod, "_internals", {
    BAR_CONFIG = BAR_CONFIG,
    _fadeAlpha = _fadeAlpha,
    _quickKeybindState = _quickKeybindState,
    FormatHotkeyText = FormatHotkeyText,
    StopFade = StopFade,
    SafeEnableMouse = SafeEnableMouse,
    SafeEnableMouseMotionOnly = SafeEnableMouseMotionOnly,
    ShouldQuickKeybindSurfaceBar = ShouldQuickKeybindSurfaceBar,
    FONT_PATH = FONT_PATH,
    _gridState = _gridState,
    NUM_ACTIONBAR_BUTTONS = NUM_ACTIONBAR_BUTTONS,
    SHAPE_EDGE_SCALES = SHAPE_EDGE_SCALES,
    STOCK_BAR_DISPOSAL = STOCK_BAR_DISPOSAL,
    BAR_LOOKUP = BAR_LOOKUP,
    SHAPE_BTN_EXPAND = SHAPE_BTN_EXPAND,
    ALL_BARS = ALL_BARS,
    FadeTo = FadeTo,
    EXTRA_BARS = EXTRA_BARS,
    _dragState = _dragState,
    secureRefsReadySetters = {},
    pagingFrameSetters = {},
    isApplyingAllSetters = {},
}, {
    SetSecureRefsReady = "secureRefsReadySetters",
    SetPagingFrame = "pagingFrameSetters",
    SetIsApplyingAll = "isApplyingAllSetters",
})
