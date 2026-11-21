if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Unlock.lua
--
--  Unlock Mode: positions, grow direction and the element registration.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local floor, abs = math.floor, math.abs

local _B, REMIND, activeIcons, ICON_SIZE = Inner._B, Inner.EABR, Inner.activeIcons, Inner.ICON_SIZE
local LayoutIcons, ResizeAnchorCentered = Inner.LayoutIcons, Inner.ResizeAnchorCentered
local CursorAttachActive = Inner.CursorAttachActive

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
local iconAnchor
Inner.iconAnchorSetters[#Inner.iconAnchorSetters + 1] = function(val) iconAnchor = val end
local cursorAnchor
Inner.cursorAnchorSetters[#Inner.cursorAnchorSetters + 1] = function(val) cursorAnchor = val end

-------------------------------------------------------------------------------
--  Unlock Mode
-------------------------------------------------------------------------------
-- Nominal two-icon row width from settings alone: the nil-position grow edge and the converter's empty-row width.
function REMIND.NominalRowW(skinData)
    return 2 * floor(ICON_SIZE * (skinData.scale or 1.0) + 0.5) + (skinData.iconSpacing or 8)
end

local function ApplyUnlockPos()
    if not iconAnchor or not saved then return end
    -- Skip for unlock-anchored elements (anchor system is authority)
    local anchored = CludesUI and CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("EABR_Reminders")
    if anchored and iconAnchor:GetLeft() then return end
    local place = saved.profile.unlockPos
    if place and place.point then
        local px, py = place.x or 0, place.y or 0
        local PPa = CludesUI and CludesUI.PP
        if PPa then
            local es = iconAnchor:GetEffectiveScale()
            -- For CENTER anchor, uses SnapCenterForDim with the frame's actual size so odd-pixel-dim frames get the +0.5 offset that places edges on whole pixels.
            local isCenterAnchor = (place.point == "CENTER")
                and (place.relPoint == "CENTER" or place.relPoint == nil)
            if isCenterAnchor and PPa.SnapCenterForDim then
                px = PPa.SnapCenterForDim(px, iconAnchor:GetWidth() or 0, es)
                py = PPa.SnapCenterForDim(py, iconAnchor:GetHeight() or 0, es)
            elseif PPa.SnapForES then
                px = PPa.SnapForES(px, es)
                py = PPa.SnapForES(py, es)
            end
        end
        iconAnchor:ClearAllPoints()
        iconAnchor:SetPoint(place.point, UIParent, place.relPoint or place.point, px, py)
    else
        -- No saved position: the row sits at the configured offset from screen center, anchored by its grow edge.
        -- Grow Right/Left place that edge half a nominal two-icon row out (settings only, never the live width) so
        -- it never follows the icon count; LayoutIcons hangs the icons off the same edge and owns the anchor's size.
        local skinData = saved.profile.display
        local growDir = skinData.growDirection
        iconAnchor:ClearAllPoints()
        if growDir == "RIGHT" then
            iconAnchor:SetPoint(
                "LEFT",
                UIParent,
                "CENTER",
                (skinData.xOffset or 0) - REMIND.NominalRowW(skinData) / 2,
                skinData.yOffset or 0
            )
        elseif growDir == "LEFT" then
            iconAnchor:SetPoint(
                "RIGHT",
                UIParent,
                "CENTER",
                (skinData.xOffset or 0) + REMIND.NominalRowW(skinData) / 2,
                skinData.yOffset or 0
            )
        else
            iconAnchor:SetPoint("CENTER", UIParent, "CENTER", skinData.xOffset or 0, skinData.yOffset or 0)
        end
    end
end

-- Moves a saved position onto the new grow edge (Grow Right = LEFT, Grow Left = RIGHT, else CENTER) without
-- moving the row. Runs only on a grow direction change or a spec layer restoring a position banked under another
-- direction: the apply path never writes the DB, and a nil position stays nil. Only positions this module writes
-- (CENTER, LEFT or RIGHT of UIParent's CENTER) convert.
function REMIND.UpdateUnlockPosForGrowDir(newGrowDir)
    local place = saved.profile.unlockPos
    if not place or not place.point or (place.relPoint or place.point) ~= "CENTER" then return end
    local curPoint = place.point
    if curPoint ~= "CENTER" and curPoint ~= "LEFT" and curPoint ~= "RIGHT" then return end
    local targetPoint = (newGrowDir == "RIGHT" and "LEFT") or (newGrowDir == "LEFT" and "RIGHT") or "CENTER"
    if curPoint == targetPoint then return end
    local wid = iconAnchor and iconAnchor:GetWidth() or 0
    if wid <= 1 then wid = REMIND.NominalRowW(saved.profile.display) end
    local cx = place.x or 0
    if curPoint == "LEFT" then
        cx = cx + (wid / 2)
    elseif curPoint == "RIGHT" then
        cx = cx - (wid / 2)
    end
    if targetPoint == "LEFT" then
        place.x = cx - (wid / 2)
    elseif targetPoint == "RIGHT" then
        place.x = cx + (wid / 2)
    else
        place.x = cx
    end
    place.point = targetPoint
    place.relPoint = "CENTER"
end

function CludesUI.GetAuraBuffGrowDir()
    local skinData = saved and saved.profile and saved.profile.display
    return skinData and skinData.growDirection or "CENTER"
end

function CludesUI.SetAuraBuffGrowDir(val)
    if not saved or not saved.profile or not saved.profile.display then return end
    saved.profile.display.growDirection = val
    REMIND.UpdateUnlockPosForGrowDir(val)
    ApplyUnlockPos()
    LayoutIcons()
end

local function RegisterUnlockElements()
    if not CludesUI or not CludesUI.RegisterUnlockElements then return end
    local MK = CludesUI.MakeUnlockElement
    CludesUI:RegisterUnlockElements({
        MK({
            key = "EABR_Reminders",
            label = "Buff Reminders",
            group = "Buff Reminders",
            order = 600,
            noAnchorTarget = true, -- icon count changes dynamically with auras
            -- Icon size is driven solely by the Scale slider. No drag-resize: row width is count-dependent, so restoring a stored width under a different count would corrupt the persisted scale (matches External Defensives).
            noResize = true,
            getFrame = function() return iconAnchor end,
            getSize = function()
                local display = saved.profile.display
                local baseScale = display.scale or 1.0
                local iconSz = floor(ICON_SIZE * baseScale + 0.5)
                local iconH = iconSz
                if display.iconShape and display.iconShape ~= "none" then
                    iconSz, iconH = mod.IconDimensions(iconSz, display)
                end
                local spacing = display.iconSpacing or 8
                -- Fits all active icons (same set LayoutIcons places: reminders + merged beacon icons unless cursor-routed); falls back to a 2-wide grabbable box when empty so the mover overlay stays draggable.
                local total = #activeIcons
                local beaconsOnCursor = CursorAttachActive(display) and cursorAnchor
                if _B.icons and not beaconsOnCursor then
                    for _, ident in ipairs(_B.ALL or {}) do
                        if _B.iconState and _B.iconState[ident] and _B.icons[ident] then total = total + 1 end
                    end
                end
                if total < 1 then total = 2 end
                local wid = total * iconSz + (total - 1) * spacing
                local textH = 0
                if display.showText then textH = (display.textSize or 11) + abs(display.textYOffset or -2) end
                local hgt = iconH + textH
                -- Resizes the anchor for the overlay
                if iconAnchor then ResizeAnchorCentered(wid, hgt) end
                return wid, hgt
            end,
            savePos = function(key, anchorPoint, relPoint, posX, posY)
                -- Unlock mode hands over the row's CENTER; Grow Right/Left store their fixed edge instead.
                local growDir = saved.profile.display.growDirection
                if
                    (growDir == "RIGHT" or growDir == "LEFT")
                    and anchorPoint == "CENTER"
                    and relPoint == "CENTER"
                then
                    local halfW = (iconAnchor and iconAnchor:GetWidth() or 0) / 2
                    if growDir == "RIGHT" then
                        anchorPoint, posX = "LEFT", posX - halfW
                    else
                        anchorPoint, posX = "RIGHT", posX + halfW
                    end
                end
                saved.profile.unlockPos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                if not CludesUI._unlockActive then ApplyUnlockPos() end
            end,
            loadPos = function()
                local place = saved.profile.unlockPos
                -- A stored grow edge (LEFT/RIGHT of UIParent's CENTER) reports the row's CENTER, the form unlock mode works in.
                -- That CENTER follows the live width, so a Discard after the icon count changed moves the edge by half the change.
                if
                    not place
                    or (place.point ~= "LEFT" and place.point ~= "RIGHT")
                    or place.relPoint ~= "CENTER"
                then
                    return place
                end
                local halfW = (iconAnchor and iconAnchor:GetWidth() or 0) / 2
                return {
                    point = "CENTER",
                    relPoint = "CENTER",
                    x = (place.x or 0) + ((place.point == "LEFT") and halfW or -halfW),
                    y = place.y or 0,
                }
            end,
            -- Spec-override unlock layers bank the stored table itself, so a Grow Right/Left edge survives a
            -- layer round trip at any icon count; one banked under another direction moves onto the current edge.
            loadRawPos = function() return saved.profile.unlockPos end,
            saveRawPos = function(_, profile)
                if not (profile and profile.point) then return end
                saved.profile.unlockPos = {
                    point = profile.point,
                    relPoint = profile.relPoint or profile.point,
                    x = profile.x,
                    y = profile.y,
                }
                REMIND.UpdateUnlockPosForGrowDir(saved.profile.display.growDirection)
            end,
            clearPos = function() saved.profile.unlockPos = nil end,
            applyPos = function() ApplyUnlockPos() end,
        }),
    })
end

Inner.ApplyUnlockPos, Inner.RegisterUnlockElements = ApplyUnlockPos, RegisterUnlockElements
Inner.broken = false
