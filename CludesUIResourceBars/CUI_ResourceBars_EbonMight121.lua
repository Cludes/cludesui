if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_ResourceBars_EbonMight121.lua
-- 12.1 ONLY: engine-slot driver for the Aug Evoker Ebon Might power bar.
--
-- Ebon Might (395296) is secret-flagged since build 68824, so the legacy
-- numeric countdown (GetPlayerAuraBySpellID expirationTime + OnUpdate
-- drain) can never run in restricted content. Same technique as the CDM
-- fake-active port: a hidden one-slot aura container on the player
-- (includeSpellIDs -- helpful-on-self passes the identity gate regardless
-- of secrecy) whose slot subtree IS the display, engine-driven end to end:
-- the button shows only while the aura is up, a slot-child StatusBar bound via
-- SetDurationBar renders remaining time (extensions included), and a bound FontString
-- renders the countdown text. Everything is styled INSIDE the creation window -- the
-- subtree is denied to addon code afterward, reads and writes both (engine contract #7)
-- -- baked from the live bar's settings, so styling edits apply on the next /reload.
--
-- The main file's Ebon Might fill/text paths early-return under ns.EMB121_Owns and call
-- ns.EMB121_Sync from UpdatePrimaryBar's Ebon Might branch -- which always runs with
-- the live bar and resolved settings in hand, so there is no build race: Sync IS the
-- trigger. ns.EMB121_Gate parks the overlay whenever the primary power type is no
-- longer Ebon Might (spec change).

local _, mod = ...
local CludesUI = _G.CludesUI
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()

local EBON_AURA_ID = 395296

-- Load-time ownership flag: legacy paths gate on this, and it must exist
-- at FILE LOAD -- a construction-time flag would let legacy paths run (and
-- error under restriction) before the deferred build completes.
mod.EMB121_Owns = true

-- proxy, container, btn, bar, built, queued, armed, rbBar, pp, pc, fsErr
local S = {}

-- "18.4"-style remaining text (legacy parity: %.1f seconds; minutes floor
-- to "2m" if extensions ever push past 60). Falls back to the suite
-- duration formatter, then to the engine default.
local timeFmt
local function GetTimeFormatter()
    if timeFmt ~= nil then
        return timeFmt or nil
    end
    timeFmt = false
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding then
        local frame = C_StringUtil.CreateNumericRuleFormatter()
        local Down = Enum.NumericRuleFormatRounding.Down
        local success = pcall(frame.SetBreakpoints, frame, {
            { threshold = 0, format = "%.1f", step = 0.1, rounding = Down },
            { threshold = 60, format = "%dm", step = 1, rounding = Down, components = { { div = 60 } } },
        })
        if success then
            timeFmt = frame
        end
    end
    if not timeFmt then
        local AK = CludesUI.AuraKit
        timeFmt = (AK and AK.GetDurationFormatter and AK.GetDurationFormatter()) or false
    end
    return timeFmt or nil
end

local function Build()
    local AK = CludesUI.AuraKit
    if S.built or not AK or not S.rbBar then
        return
    end
    local rb, pp, pc = S.rbBar, S.pp or {}, S.pc

    AK.styles["erb:emb121"] = AK.styles["erb:emb121"] or { noRegions = true, width = 1, height = 1 }
    if not S.proxy then
        S.proxy = CreateFrame("Frame", nil, UIParent)
        S.proxy:Hide()
    end

    -- Bake the live bar's visuals (our frames -- readable): fill texture
    -- path, then color per the legacy priority (custom = whatever the
    -- build pass painted on the fill; else the Ebon Might power color,
    -- flat or gradient per settings).
    local ft = rb.GetStatusBarTexture and rb:GetStatusBarTexture()
    local texPath = (ft and ft.GetTexture and ft:GetTexture()) or "Interface\\Buttons\\WHITE8x8"
    local red, green, blue, a = 1, 1, 1, 1
    if pp.customColored and ft and ft.GetVertexColor then
        red, green, blue, a = ft:GetVertexColor()
    elseif pc then
        red, green, blue = pc[1] or 1, pc[2] or 1, pc[3] or 1
    end

    -- Text bake source: the bar's own text FS (font + anchor), so the
    -- engine text lands exactly where the legacy text sat.
    local tFont, tSize, tFlags, tPoint, tRelP, tX, tY
    local rbText = rb._text
    if rbText and rbText.GetFont then
        tFont, tSize, tFlags = rbText:GetFont()
        if rbText.GetPoint and rbText:GetNumPoints() > 0 then
            local point, _, relPoint, posX, posY = rbText:GetPoint(1)
            tPoint, tRelP, tX, tY = point, relPoint, posX, posY
        end
    end
    local showText = pp.textFormat and pp.textFormat ~= "none"

    local boxHolder = AK.CreateContainerShell(S.proxy, { point = { "CENTER" } })
    AK.AddSlotToContainer(boxHolder, {
        key = "em",
        filter = { "HELPFUL" },
        candidateFilters = { includeSpellIDs = { [EBON_AURA_ID] = true } },
        style = "erb:emb121",
        extraInit = function(btnFrame)
            -- Creation window: the only legal moment to touch this
            -- subtree. Two-point anchoring sizes the button by anchors
            -- forever; all repositioning is proxy moves.
            btnFrame:SetAllPoints(S.proxy)
            -- Both halves, and inside the creation window: this is the only
            -- legal moment to set them. The slot button is an engine Button, so
            -- mouse is on by default -- motion alone only suppresses the
            -- tooltip. With clicks still enabled it is an invisible click
            -- blocker over the bar's whole rect for as long as Ebon Might is
            -- up, swallowing clicks meant for the world (nameplates behind the
            -- bar stop responding mid-combat). It is a display-only overlay and
            -- has no OnClick, so it should never take mouse input at all.
            if btnFrame.SetMouseClickEnabled then
                btnFrame:SetMouseClickEnabled(false)
            end
            if btnFrame.SetMouseMotionEnabled then
                btnFrame:SetMouseMotionEnabled(false)
            end

            local barFrame = CreateFrame("StatusBar", nil, btnFrame)
            barFrame:SetAllPoints(btnFrame)
            barFrame:SetStatusBarTexture(texPath)
            local bft = barFrame:GetStatusBarTexture()
            if bft then
                if pp.gradientEnabled and not pp.customColored and bft.SetGradient then
                    -- Mirrors the legacy gradient applier: white vertex,
                    -- endpoint colors carry the gradient.
                    bft:SetVertexColor(1, 1, 1, 1)
                    bft:SetGradient(
                        pp.gradientDir or "HORIZONTAL",
                        CreateColor(red, green, blue, 1),
                        CreateColor(
                            pp.gradientR or red,
                            pp.gradientG or green,
                            pp.gradientB or blue,
                            pp.gradientA or 1
                        )
                    )
                else
                    bft:SetVertexColor(red, green, blue, a or 1)
                end
            end
            local options = {}
            if Enum.StatusBarInterpolation then
                options.interpolation = Enum.StatusBarInterpolation.Immediate
            end
            if Enum.StatusBarTimerDirection then
                options.direction = Enum.StatusBarTimerDirection.RemainingTime
            end
            btnFrame:SetDurationBar(barFrame, options)

            if showText then
                -- ARMORED: an uncaught error here aborts the engine's
                -- CreateFrameBatch and kills the slot. Text is optional
                -- polish; failures land in S.fsErr.
                local okFS, errFS = pcall(function()
                    local tc = CreateFrame("Frame", nil, btnFrame)
                    tc:SetAllPoints(btnFrame)
                    tc:SetFrameLevel(barFrame:GetFrameLevel() + 5)
                    local fontStr = tc:CreateFontString(nil, "OVERLAY")
                    -- Font BEFORE registration (the engine SetText()s every
                    -- registered string; an unfonted FS hard-errors).
                    if tFont then
                        fontStr:SetFont(tFont, tSize, tFlags)
                    else
                        fontStr:SetFont(
                            "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF",
                            12,
                            "OUTLINE"
                        )
                    end
                    if rbText and rbText.GetTextColor then
                        fontStr:SetTextColor(rbText:GetTextColor())
                    end
                    fontStr:SetPoint(
                        tPoint or "CENTER",
                        btnFrame,
                        tRelP or tPoint or "CENTER",
                        tX or 0,
                        tY or 0
                    )
                    -- 68914 schema key (textFormatter); BuildDurationTextOpts
                    -- when available, bare table fallback otherwise.
                    local AK2 = CludesUI.AuraKit
                    local dopts
                    if AK2 and AK2.BuildDurationTextOpts then
                        dopts = AK2.BuildDurationTextOpts(GetTimeFormatter())
                    else
                        dopts = { textFormatter = GetTimeFormatter() }
                    end
                    if AK2 and AK2.SetDurationTextSafe then
                        AK2.SetDurationTextSafe(btnFrame, fontStr, dopts)
                    else
                        btnFrame:SetDurationText(fontStr, dopts)
                    end
                end)
                if not okFS then
                    S.fsErr = errFS
                end
            end

            S.btn, S.bar = btnFrame, barFrame
        end,
    })
    AK.FinishContainer(boxHolder, "player")
    S.container = boxHolder
    S.built = true
end

local function EnsureBuilt()
    if S.built or S.queued then
        return
    end
    local AK = CludesUI.AuraKit
    if not (AK and AK.QueueBuildJob) then
        return
    end
    S.queued = true
    AKWorker:Queue(function()
        S.queued = nil
        Build()
        if S.built and S.armed and S.rbBar then
            mod.EMB121_Sync(S.rbBar, S.pp, S.pc)
        end
    end, "erb:emb121-shell")
end

-- True once the engine overlay's countdown text is confirmed live: false
-- while the (async, one-shot) build is still queued, and false if the build
-- ran but its FontString creation hit the pcall guard in Build() (armored
-- because an uncaught error there kills the whole slot). Callers use this to
-- fall back to the legacy numeric text instead of leaving the bar
-- permanently blank for the rest of the session (S.built never gets a second
-- attempt once set -- only a /reload resets it).
function mod.EMB121_TextOk()
    return S.built and not S.fsErr
end

-- Called from UpdatePrimaryBar whenever the primary power type resolves:
-- parks the overlay the moment the bar stops being Ebon Might (spec swap).
function mod.EMB121_Gate(isEbon)
    if not isEbon and S.armed then
        S.armed = nil
        if S.proxy then
            S.proxy:Hide()
        end
    end
end

-- Called from UpdatePrimaryBar's Ebon Might branch with the live bar and
-- resolved settings -- the build trigger AND the attach, race-free by
-- construction. Repositioning is always proxy moves (our frame).
function mod.EMB121_Sync(barFrame, pp, pc)
    S.rbBar, S.pp, S.pc = barFrame, pp, pc
    S.armed = true
    if not S.built then
        EnsureBuilt()
        return
    end
    S.proxy:SetParent(barFrame)
    S.proxy:ClearAllPoints()
    S.proxy:SetAllPoints(barFrame)
    S.proxy:Show()
    -- One container-level set lifts the whole engine subtree above the
    -- (empty) legacy fill.
    local lvl = barFrame:GetFrameLevel() + 1
    S.container:SetFrameLevel(lvl)
    -- ...which also lifts it above the bar's border strips (bar+2), so the
    -- fill -- a slot-button child two levels down, edge to edge over the whole
    -- rect -- paints over them: Border Size/Color silently did nothing while
    -- the power type was Ebon Might. Push the border back on top, clearing the
    -- engine fill with a level of margin (the subtree is denied to us
    -- afterward, so its exact levels can't be read back). The countdown text
    -- sits at fill+5, still above the border, as on the legacy path. Draw Above
    -- GCD Bar stamps its own cover on the bar (_erbGcdCover): the higher wins, so
    -- a power tick never lowers that lift.
    if barFrame.RaiseBorderAbove then
        barFrame:RaiseBorderAbove(math.max(lvl + 3, barFrame._erbGcdCover or 0), pp and pp.borderBehind)
    end
end
