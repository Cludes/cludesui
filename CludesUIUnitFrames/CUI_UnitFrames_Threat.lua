if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Threat.lua
--
--  Threat display on the unit frames: the additive Player Threat border
--  and the threat % text on target and focus (WoW Forever only). Loads
--  after the main file and reads it through ns and ns._internals;
--  db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue
local Pix = CludesUI.PP

local Inner = mod._internals
local frameList, GetSelectedFont, SetFSFont = Inner.frames, Inner.GetSelectedFont, Inner.SetFSFont
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
--  Player Threat border (additive "Shadow" style on the PLAYER frame)
--
--  Zero cost unless enabled: no frame created, no event registered until the
--  option is on. When on, watches ONLY the player's own threat (RegisterUnitEvent
--  ... "player") plus minimal combat/zone boundaries to clear it; shows only in
--  instanced content (party/raid/delve) while grouped -- mirrors nameplate non-tank logic.
-------------------------------------------------------------------------------
local _ptWatcher -- lazily-created event frame
local _ptOn = false -- the watcher's events are registered
local _ptShownState -- nil / "has" / "near" -- skip redundant re-apply

-- party/raid/delve instances only (mirrors the nameplate threat-context gate)
local function PT_InInstancedContent()
    local _, instanceType, difficultyID = GetInstanceInfo()
    if (tonumber(difficultyID) or 0) == 0 then
        return false
    end
    if C_Garrison and C_Garrison.IsOnGarrisonMap and C_Garrison.IsOnGarrisonMap() then
        return false
    end
    local isDelve = C_PartyInfo and C_PartyInfo.IsDelveInProgress and C_PartyInfo.IsDelveInProgress()
    return instanceType == "party" or instanceType == "raid" or isDelve
end

-- Lazily create the dedicated additive shadow border on the player frame. It
-- sits behind the frame like the real "Shadow" border style, separate from the
-- unified border so it ADDS to whatever border the user already has.
local function PT_EnsureBorder(popFrame)
    if popFrame._threatShadowBorder then
        return popFrame._threatShadowBorder
    end
    local widget = CreateFrame("Frame", nil, popFrame)
    Pix.Point(widget, "TOPLEFT", popFrame, "TOPLEFT", 0, 0)
    Pix.Point(widget, "BOTTOMRIGHT", popFrame, "BOTTOMRIGHT", 0, 0)
    widget:SetFrameLevel(math.max(0, popFrame:GetFrameLevel() - 1))
    widget:Hide()
    popFrame._threatShadowBorder = widget
    return widget
end

local function PT_HideGlow()
    local popFrame = frameList.player
    if popFrame and popFrame._threatShadowBorder then
        popFrame._threatShadowBorder:Hide()
    end
    _ptShownState = nil
end

-- Render the additive Shadow border (size 2) tinted with the threat color --
-- identical to picking "Shadow" at size 2 from the Border Style dropdown.
local function PT_Show(state, color)
    local popFrame = frameList.player
    if not popFrame then
        return
    end
    local widget = PT_EnsureBorder(popFrame)
    if _ptShownState ~= state then
        _ptShownState = state
        CludesUI.ApplyBorderStyle(widget, 2, color.r, color.g, color.b, 1, "shadow", nil, nil, nil, nil, "unitframes", 2)
    else
        CludesUI.SetBorderStyleColor(widget, color.r, color.g, color.b, 1)
    end
    widget:Show()
end

-- Re-evaluate the player's threat and paint/clear the additive shadow border.
function mod.UpdatePlayerThreatBorder()
    if not (saved and saved.profile and saved.profile.playerThreatBorderEnabled) then
        PT_HideGlow()
        return
    end
    if not frameList.player then
        return
    end
    if not PT_InInstancedContent() or not IsInGroup() then
        PT_HideGlow()
        return
    end
    local status = UnitThreatSituation("player")
    if status and status >= 2 then
        -- status 2/3: the mob is on you -- you have aggro.
        PT_Show("has", saved.profile.playerThreatHasAggroColor or { r = 1, g = 0.5, b = 0 })
    elseif status == 1 then
        -- status 1: higher threat than the tank but not tanking yet -- close to aggro.
        PT_Show("near", saved.profile.playerThreatNearAggroColor or { r = 0.81, g = 0.72, b = 0.19 })
    else
        PT_HideGlow()
    end
end

-- Enable/disable the watcher. Registers ONLY the player's own threat event plus
-- the minimal boundaries to clear it; tears everything down and hides when off.
function mod.SetPlayerThreatEnabled(enabled)
    _ptOn = enabled and true or false
    if enabled then
        if not _ptWatcher then
            _ptWatcher = CreateFrame("Frame")
            _ptWatcher:SetScript("OnEvent", function()
                mod.UpdatePlayerThreatBorder()
            end)
        end
        _ptWatcher:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")
        _ptWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        _ptWatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
        _ptWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        _ptWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
        mod.UpdatePlayerThreatBorder()
    else
        if _ptWatcher then
            _ptWatcher:UnregisterAllEvents()
        end
        PT_HideGlow()
    end
end

-- Login and every real reload pass (profile switch, spec override, import):
-- the saved toggle never reaches SetPlayerThreatEnabled any other way.
function mod.SyncPlayerThreat()
    local wanted = saved.profile.playerThreatBorderEnabled == true
    if wanted ~= _ptOn then
        mod.SetPlayerThreatEnabled(wanted)
    elseif wanted then
        mod.UpdatePlayerThreatBorder()
    end
end

-------------------------------------------------------------------------------
--  Threat % text on the target and focus frames (WoW Forever only; retail
--  defines none of it). The watcher carries no events until
--  SetThreatPctEnabled(true).
-------------------------------------------------------------------------------
if CludesUI.IS_FOREVER then
    -- Inside spots sit on the health bar; outside spots sit beside the whole
    -- frame (past an attached portrait), centred on its height.
    local POS = {
        RIGHT = { point = "RIGHT", x = -4 },
        LEFT = { point = "LEFT", x = 4 },
        CENTER = { point = "CENTER", x = 0 },
        OUTRIGHT = { point = "LEFT", rel = "RIGHT", x = 4, outside = true },
        OUTLEFT = { point = "RIGHT", rel = "LEFT", x = -4, outside = true },
    }
    local watcher = CreateFrame("Frame")

    local function Layout(widget, fontStr)
        local profile = saved.profile
        local posKey = POS[profile.threatPctPosition] and profile.threatPctPosition or "CENTER"
        local size = profile.threatPctSize
        local posX, posY = profile.threatPctXOffset, profile.threatPctYOffset
        local font = GetSelectedFont()
        local outline = CludesUI.GetFontOutlineFlag("unitFrames")
        if
            widget._tpPos == posKey
            and widget._tpSize == size
            and widget._tpX == posX
            and widget._tpY == posY
            and widget._tpFont == font
            and widget._tpOutline == outline
        then
            return
        end
        widget._tpPos, widget._tpSize, widget._tpX, widget._tpY = posKey, size, posX, posY
        widget._tpFont, widget._tpOutline = font, outline
        local place = POS[posKey]
        SetFSFont(fontStr, size)
        fontStr:ClearAllPoints()
        Pix.Point(
            fontStr,
            place.point,
            place.outside and widget or widget.Health,
            place.rel or place.point,
            place.x + posX,
            posY
        )
        fontStr:SetJustifyH(place.point)
    end

    -- The percent may be secret: only type() and issecretvalue() read it here
    -- (a readable 0 hides the text), then it goes straight to PaintThreatPct.
    local function UpdateUnit(unitToken)
        local widget = frameList[unitToken]
        if not (widget and widget._textOverlay) then
            return
        end
        local fontStr = widget._threatPctText
        local profile = saved.profile
        if profile.threatPctEnabled and (unitToken == "target" or profile.threatPctFocus) then
            local isTanking, status, pct = UnitDetailedThreatSituation("player", unitToken)
            if type(pct) == "number" and (issecretvalue(pct) or pct ~= 0) then
                if not fontStr then
                    fontStr = widget._textOverlay:CreateFontString(nil, "OVERLAY")
                    fontStr:SetWordWrap(false)
                    widget._threatPctText = fontStr
                end
                Layout(widget, fontStr)
                CludesUI.PaintThreatPct(fontStr, pct, status, isTanking, profile.threatPctColorByThreat)
                fontStr:Show()
                return
            end
        end
        if fontStr then
            fontStr:Hide()
        end
    end

    local function UpdateAll()
        UpdateUnit("target")
        UpdateUnit("focus")
    end

    local function OnEvent(_, evt, unitToken)
        if evt == "UNIT_THREAT_LIST_UPDATE" then
            UpdateUnit(unitToken)
        elseif evt == "PLAYER_TARGET_CHANGED" then
            UpdateUnit("target")
        elseif evt == "PLAYER_FOCUS_CHANGED" then
            UpdateUnit("focus")
        else
            UpdateAll()
        end
    end

    watcher:SetScript("OnEvent", OnEvent)

    -- Events only while on AND an CludesUI target or focus frame exists
    -- (a frame source change reloads, so the frames never appear later).
    local tpOn = false
    function mod.SetThreatPctEnabled(enabled)
        enabled = enabled == true and (frameList.target or frameList.focus) ~= nil
        if enabled ~= tpOn then
            tpOn = enabled
            if enabled then
                watcher:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target", "focus")
                watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
                watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
                watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                watcher:UnregisterAllEvents()
            end
        end
        UpdateAll()
    end

    -- Login and every real reload pass (profile switch, spec override, import):
    -- the saved toggle never reaches SetThreatPctEnabled any other way.
    function mod.SyncThreatPct()
        local wanted = saved.profile.threatPctEnabled == true and (frameList.target or frameList.focus) ~= nil
        if wanted ~= tpOn then
            mod.SetThreatPctEnabled(wanted)
        elseif wanted then
            UpdateAll()
        end
    end

    -- Options setters of the position, size, offset and colour keys (the
    -- layout memo compares every layout input).
    mod.RefreshThreatPct = UpdateAll
end -- IS_FOREVER
