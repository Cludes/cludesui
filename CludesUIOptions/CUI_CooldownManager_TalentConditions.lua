if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CooldownManager_TalentConditions.lua
--  Talent Conditions for the CDM per-icon menu (cooldown/utility bars): the
--  menu row opens the shared picker (CludesUI.ShowTalentConditionsPopup in
--  CludesUI_TalentConditionsPopup.lua) on the spell's own list, and the bar
--  preview marks the slots whose spells carry conditions.
--
--  Storage, evaluation and the reanchor filter live in the CDM addon
--  (CludesUICdmTalentConditions.lua). Conditions are stored per spec, so
--  what the picker shows (the active config's committed build) is exactly
--  what decides the icon.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then
    return
end

-- The options page pool (CludesUI_FramePool.lua): the corner mark on a
-- preview slot (a reused header's slot is a pool host) is handed out again
-- reset to fresh.
local CreateFrame = CludesUI._Pool.CreateFrame

local Pix = CludesUI.PP
local NOT_TAKEN = CludesUI.TALENT_COND_NOT_TAKEN

-- The picker's texts, in the icon's words (made on the first open).
local iconTexts
local function IconTexts()
    if not iconTexts then
        iconTexts = {
            hint = CludesUI.L(
                "Click a talent to require it: Taken, then Not Taken, then cleared. Every condition must hold for the icon to show."
            ),
            none = CludesUI.L("No conditions: the icon always shows."),
            met = function(num)
                return CludesUI.Lf("%1$d condition(s), met by your current talents: the icon shows.", num)
            end,
            notMet = function(num)
                return CludesUI.Lf(
                    "%1$d condition(s), not met by your current talents: the icon is hidden.",
                    num
                )
            end,
        }
    end
    return iconTexts
end

-------------------------------------------------------------------------------
--  Options preview helpers (called from the CDM bar preview; kept here so the
--  preview function, already near Lua 5.1's local cap, gains one local only)
-------------------------------------------------------------------------------

-- For a CD/utility bar's assigned ids: id -> "on" when its conditions hold now,
-- "off" when they do not. Includes Empty Slot markers; nil when none have conditions.
function mod.TalentCondPreviewSet(barId, tracked)
    local storage = mod.GetSpellSettingsStore(barId)
    if not storage or type(tracked) ~= "table" then
        return nil
    end
    local group
    for _, ident in ipairs(tracked) do
        local record = type(ident) == "number"
            and (ident > 0 or mod.IsEmptySlotMarker(ident))
            and storage[ident]
        local conds = type(record) == "table" and rawget(record, "talentConditions")
        if type(conds) == "table" and #conds > 0 then
            group = group or {}
            group[ident] = mod.TalentConditionsHold(conds) and "on" or "off"
        end
    end
    return group
end

-- Small corner mark on a preview slot whose spell carries conditions: accent while
-- they hold, red while they do not. state nil hides it. Built on first use. Kept under
-- the slot's text overlay (its border strips sit one level above the fill), so keybind
-- and stack text stay readable in every icon style (the overlay's level differs per style).
function mod.PaintTalentCondMark(slotIndex, status)
    local mark = slotIndex._tcMark
    if not status then
        if mark then
            mark:Hide()
        end
        return
    end
    if not mark then
        mark = CreateFrame("Frame", nil, slotIndex)
        mark:EnableMouse(false)
        mark._tex = mark:CreateTexture(nil, "ARTWORK")
        mark._tex:SetAllPoints()
        Pix.CreateBorder(mark, 0, 0, 0, 1, 1, "OVERLAY", 7)
        slotIndex._tcMark = mark
    end
    mark:SetFrameLevel(slotIndex._pvTextOverlay:GetFrameLevel() - 2)
    local dim = math.max(6, math.floor((slotIndex:GetWidth() or 0) * 0.28 + 0.5))
    mark:SetSize(dim, dim)
    mark:ClearAllPoints()
    mark:SetPoint("TOPLEFT", slotIndex, "TOPLEFT", 3, -3)
    if status == "off" then
        mark._tex:SetColorTexture(NOT_TAKEN[1], NOT_TAKEN[2], NOT_TAKEN[3], 1)
    else
        local ar, ag, ab = CludesUI.GetAccentColor()
        mark._tex:SetColorTexture(ar, ag, ab, 1)
    end
    mark:Show()
end

-------------------------------------------------------------------------------
--  Entry point (the per-icon menu's "Talent Conditions" row)
--  conds: the spell's saved list (read only here); confirm(newList or nil).
-------------------------------------------------------------------------------
function mod.ShowCDMTalentConditionsPopup(spellId, conds, confirm)
    local spellName = mod.IsEmptySlotMarker(spellId) and CludesUI.L("Empty Slot")
        or C_Spell.GetSpellName(spellId)
        or tostring(spellId)
    CludesUI.ShowTalentConditionsPopup({
        title = CludesUI.Lf("Talent Conditions: %1$s", spellName),
        conds = conds,
        onConfirm = confirm,
        texts = IconTexts(),
        fontKey = "cdm",
    })
end
