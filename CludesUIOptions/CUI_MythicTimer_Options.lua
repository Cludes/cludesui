if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_MythicTimer_Options.lua  --  Settings pages for Mythic+ Tools
--  (Mythic+ Timer / Kick Tracker / Cast Bars / Target & Focus Bars / Run Summary)
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIMythicTimer"
local mod = CludesUI._ModuleNS[ADDON_NAME] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

local PAGE_DISPLAY = "Mythic+ Timer"
-- The page keeps its identity (search alias, links, remembered page); its tab
-- reads "Cast Bars" through tabLabels below.
local PAGE_TSB = "Targeted Spell Bars"
local PAGE_TFB = "Target/Focus Bars"
local PAGE_RS = "Run Summary"
local PAGE_KT = "Kick Tracker"

-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- A length on a frame's physical pixel grid (onePx: one pixel in its units).
local function PvSnap(v, onePx)
    return math.floor(v / onePx + 0.5) * onePx
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not CludesUI or not CludesUI.RegisterModule then
        return
    end

    local saved
    C_Timer.After(0, function()
        saved = _G._CUMT_AceDB
    end)

    local function DB()
        if not saved then
            saved = _G._CUMT_AceDB
        end
        return saved and saved.profile
    end

    local function Cfg(key)
        local p = DB()
        return p and p[key]
    end

    local function Set(key, val)
        local p = DB()
        if p then
            p[key] = val
        end
    end

    -- Advanced-mode toggle removed: every option is always shown so the
    -- page can be trimmed deliberately. Guard kept as a stub so existing
    -- "if IsAdvanced() then ... end" blocks render unconditionally.
    local function IsAdvanced()
        return true
    end

    local function Refresh()
        if _G._CUMT_ApplyTimer then
            _G._CUMT_ApplyTimer()
        end
        CludesUI:RefreshPage()
    end

    local function RebuildPage()
        if _G._CUMT_ApplyTimer then
            _G._CUMT_ApplyTimer()
        end
        CludesUI:RefreshPage(true)
    end

    -- One-line stand-ins for the closures the Mythic+ Timer rows repeat.
    -- The timer as a whole switched off.
    local function ModOff()
        return Cfg("enabled") == false
    end
    -- The timer, or the switch named by key, turned off.
    local function OffWith(key)
        return function()
            return Cfg("enabled") == false or Cfg(key) == false
        end
    end
    -- The stored value, else def.
    local function Or(key, def)
        return function()
            return Cfg(key) or def
        end
    end
    -- A switch read as on until turned off / off until turned on.
    local function NotOff(key)
        return function()
            return Cfg(key) ~= false
        end
    end
    local function IsTrue(key)
        return function()
            return Cfg(key) == true
        end
    end
    -- Stores the value and re-applies the timer; repaint also redraws the page.
    local function Keep(key, repaint)
        return function(v)
            Set(key, v)
            Refresh()
            if repaint then
                CludesUI:RefreshPage()
            end
        end
    end

    ---------------------------------------------------------------------------
    --  Header previews: one kit for the Kick Tracker, Cast Bars and
    --  Target/Focus Bars pages. A page's header shows its elements side by
    --  side as the runtime paints them (ns.KTB_PaintSample, KT_PaintSampleIcon,
    --  TSB_PaintSample, TFB_PaintSample), each under a title on one line, at
    --  the size they have on screen (the panel's scale compensated, a wide
    --  element shrunk to its column). A column def: { title, on() -> full
    --  strength or dimmed, paint(host) -> w, h in UIParent px (nil: nothing
    --  to show), noFit }. Each column host is a plain frame built once per
    --  state and hung on every header root the page gets (the page pool
    --  buries foreign children of a frame it made, so a sample never sits
    --  under a pooled frame); only the title host and its font strings come
    --  from the pool.
    ---------------------------------------------------------------------------
    local PV_TITLE_H = 15 -- the 12 px title line and its 3 px gap, header px
    local PV_PAD_Y = 20 -- above and below the block
    local PV_MIN_H = 80

    local function PvNewState()
        return { cols = {} }
    end

    -- Paints every column and lays the block out; returns the header height
    -- (header px). building: the header builder's own pass, which returns
    -- the height instead of writing it.
    local function PvUpdate(st, building)
        local heading = st.hdr
        if not heading then
            return 0
        end
        local hdrW = st.hdrW or heading:GetWidth()
        -- The panel's scale compensated: a sample renders at UIParent's.
        st.scale = UIParent:GetEffectiveScale() / heading:GetEffectiveScale()
        local cols = st.cols
        local num = #cols
        local colW = (hdrW - 2 * CludesUI.CONTENT_PAD) / num
        local isShown, maxH = 0, 0
        for idx = 1, num do
            local c = cols[idx]
            local host = c.host
            if host:GetParent() ~= heading then
                host:SetParent(heading)
            end
            -- Painted at the last pass's scale, so the sample's pixel snaps
            -- read the scale it shows at; a changed fit paints it again.
            local fit = c.fit or 1
            host:SetScale(st.scale * fit)
            local wid, hgt = c.def.paint(host)
            if not wid then
                c.w = nil
                host:Hide()
                c.fs:Hide()
            else
                local wanted = c.def.noFit and 1 or math.min(1, colW / (wid * st.scale))
                if math.abs(wanted - fit) > 0.001 then
                    fit = wanted
                    host:SetScale(st.scale * fit)
                    wid, hgt = c.def.paint(host)
                end
                c.w, c.h, c.fit = wid, hgt, fit
                host:SetSize(wid, hgt)
                isShown = isShown + 1
                maxH = math.max(maxH, hgt * fit * st.scale)
            end
        end
        -- Every element's top on one line, its title above it: the block
        -- (the title line and the tallest element) centred in the header.
        -- A SetPoint offset is in the host's own units, so the header px
        -- divide by the host's scale.
        local blockH = maxH + PV_TITLE_H
        for idx = 1, num do
            local c = cols[idx]
            if c.w then
                local host = c.host
                local hs = st.scale * c.fit
                local onePx = CludesUI.PP.perfect / host:GetEffectiveScale()
                local cx = (-(num - 1) / 2 + (idx - 1)) * colW
                local topY = blockH / 2 - PV_TITLE_H
                host:ClearAllPoints()
                host:SetPoint("TOP", heading, "CENTER", PvSnap(cx / hs, onePx), PvSnap(topY / hs, onePx))
                host:SetAlpha(c.def.on() and 1 or 0.3)
                host:Show()
                c.fs:ClearAllPoints()
                c.fs:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 3)
                c.fs:Show()
            end
        end
        local H = 0
        if isShown > 0 then
            H = math.max(PV_MIN_H, math.ceil(blockH + 2 * PV_PAD_Y))
        end
        st.baseH = H
        if not building then
            -- Silent: the page moves down, never scrolls under the header;
            -- written only for a change of at least half a physical pixel.
            local es = heading:GetEffectiveScale()
            local px = (es > 0) and (CludesUI.PP.perfect / es) or 1
            if math.abs(heading:GetHeight() - H) >= px * 0.5 then
                CludesUI:SetContentHeaderHeightSilent(H)
            end
        end
        return H
    end

    -- The header builder of a state over its column defs (in order, every
    -- build, so the pool hands the same kinds back in the same order).
    local function PvBuilder(st, cols)
        return function(heading, hdrW)
            st.hdr = heading
            local lblHost = CreateFrame("Frame", nil, heading)
            lblHost:SetAllPoints(heading)
            lblHost:SetFrameLevel(heading:GetFrameLevel() + 3)
            st.lblHost = lblHost
            for idx = 1, #cols do
                local c = st.cols[idx]
                if not c then
                    c = {}
                    st.cols[idx] = c
                end
                c.def = cols[idx]
                c.host = c.host or _G.CreateFrame("Frame", nil, heading)
                local fontStr = CludesUI.MakeFont(lblHost, 11, nil, 1, 1, 1)
                fontStr:SetAlpha(0.6)
                fontStr:SetText(CludesUI.L(c.def.title))
                c.fs = fontStr
            end
            st.hdrW = hdrW
            local hgt = PvUpdate(st, true)
            st.hdrW = nil
            return hgt
        end
    end

    -- A write on the page: its shown preview paints again.
    local function PvRepaint(st)
        if st.hdr and st.hdr:IsVisible() then
            PvUpdate(st, false)
        end
    end

    local tsbPv, tfbPv = PvNewState(), PvNewState()
    -- The Kick Tracker page (its own file) builds its header from the kit.
    mod._MT_Preview = { NewState = PvNewState, Builder = PvBuilder, Update = PvUpdate, Repaint = PvRepaint }

    local function BuildBarTexDropdown()
        if mod.AppendSharedMediaBarTextures then
            mod.AppendSharedMediaBarTextures()
        end

        local values, sequence = {}, {}
        local nameList = mod.barTextureNames or {}
        local textureOrder = mod.barTextureOrder or {}
        for _, key in ipairs(textureOrder) do
            if key ~= "---" then
                values[key] = nameList[key] or key
                sequence[#sequence + 1] = key
            end
        end

        local textureLookup = mod.barTextures or {}
        values._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return textureLookup[key]
            end,
        }
        return values, sequence
    end

    -- Build Page Toggle preview + sync the Quest Tracker suppression so it doesn't sit
    -- on top of the M+ Timer preview frame.
    local function _setPreview(v)
        Set("showPreview", v)
        Refresh()
        if _G._CUQT_SetSuppressed then
            _G._CUQT_SetSuppressed("MTimerPreview", v == true)
        end
    end

    -- Auto-disable the preview when the CUI options window closes, so the preview
    -- frame doesn't linger after the user is done configuring. Installed once, the
    -- first time the M+ Timer page is built (which guarantees CludesUIFrame exists).
    local function _installPreviewAutoOff()
        local mf = _G.CludesUIFrame
        if not mf or mf._eMTPreviewHook then
            return
        end
        mf._eMTPreviewHook = true
        mf:HookScript("OnHide", function()
            if Cfg("showPreview") == true then
                _setPreview(false)
                CludesUI:RefreshPage() -- update toggle visual immediately
            end
        end)
    end

    local function BuildPage(pageName, hostFrame, yOffset)
        _installPreviewAutoOff()

        local W = CludesUI.Widgets
        local Pix = CludesUI.PP
        local posY = yOffset
        local _, row, hgt, heading

        if CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        local function ApplyBorder()
            if mod.ApplyBorder then
                mod.ApplyBorder()
            end
        end

        local alignValues = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" }
        local alignOrder = { "LEFT", "CENTER", "RIGHT" }
        local titleAffixPositionValues = {
            ABOVE_TIMER = "Above Timer",
            BELOW_TIMER = "Below Timer",
        }
        local titleAffixPositionOrder = { "ABOVE_TIMER", "BELOW_TIMER" }
        local objectiveTimePositionValues = { RIGHT = "Right", LEFT = "Left" }
        local objectiveTimePositionOrder = { "RIGHT", "LEFT" }
        local compareModeValues = {
            NONE = "None",
            DUNGEON = "Per Dungeon",
            LEVEL = "Per Dungeon + Level",
            LEVEL_AFFIX = "Per Dungeon + Level + Affixes",
        }
        local compareModeOrder = { "NONE", "DUNGEON", "LEVEL", "LEVEL_AFFIX" }
        local forcesTextValues = {
            PERCENT = "Percent",
            COUNT = "Count / Total",
            COUNT_PERCENT = "Count / Total + %",
            COUNT_REMAINING = "Count / Total + Remaining",
            REMAINING = "Remaining Count",
        }
        local forcesTextOrder = { "PERCENT", "COUNT", "COUNT_PERCENT", "COUNT_REMAINING", "REMAINING" }

        -- DISPLAY
        heading, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
        posY = posY - hgt
        CludesUI.BuildSectionUnlockJump(heading, {
            key = "EMT_MythicTimer",
            disabled = ModOff,
            disabledTooltip = "Enable Mythic+ Timer",
        })

        local alignAllValues = { LEFT = "Left", RIGHT = "Right" }
        local alignAllOrder = { "LEFT", "RIGHT" }

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Mythic+ Timer",
            tooltip = "The Mythic+ timer window in keys.",
            getValue = NotOff("enabled"),
            setValue = function(v)
                Set("enabled", v and true or false)
                if not v and Cfg("showPreview") == true then
                    _setPreview(false)
                end
                Refresh()
            end,
        }, {
            type = "dropdown",
            text = "Text Align",
            disabled = ModOff,
            disabledTooltip = "the module",
            values = alignAllValues,
            order = alignAllOrder,
            getValue = Or("alignAllText", "RIGHT"),
            setValue = function(v)
                Set("alignAllText", v)
                if _G._CUMT_RebuildStandalone then
                    _G._CUMT_RebuildStandalone()
                end
                Refresh()
            end,
        })
        posY = posY - hgt
        -- The preview eye on the enable toggle: a sample run in the timer
        -- window while the page is open (off again when the panel closes,
        -- _installPreviewAutoOff). None in the search pre-build.
        if not CludesUI._prebuilding then
            local EYE_VISIBLE, EYE_INVISIBLE = CludesUI.EYE_VISIBLE_ICON, CludesUI.EYE_INVISIBLE_ICON
            local region = row._leftRegion
            local eyeBtn = CreateFrame("Button", nil, region)
            eyeBtn:SetSize(26, 26)
            eyeBtn:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            eyeBtn:SetFrameLevel(region:GetFrameLevel() + 5)
            region._lastInline = eyeBtn
            local eyeTex = eyeBtn:CreateTexture(nil, "OVERLAY")
            eyeTex:SetAllPoints()
            local function Off()
                return Cfg("enabled") == false
            end
            local function RefreshEye()
                -- The art is named the other way round: the "invisible" file is the open eye.
                eyeTex:SetTexture(Cfg("showPreview") == true and EYE_INVISIBLE or EYE_VISIBLE)
                CludesUI.SetGlyphAlpha(eyeBtn, Off() and 0.15 or 0.4)
            end
            RefreshEye()
            CludesUI.RegisterWidgetRefresh(RefreshEye)
            eyeBtn:SetScript("OnClick", function()
                if Off() then
                    return
                end
                _setPreview(Cfg("showPreview") ~= true)
                RefreshEye()
            end)
            eyeBtn:SetScript("OnEnter", function(self)
                if Off() then
                    CludesUI.ShowWidgetTooltip(
                        self,
                        CludesUI.DisabledTooltip("Enable Mythic+ Timer"),
                        { width = 175 }
                    )
                    return
                end
                CludesUI.SetGlyphAlpha(self, 0.7)
                CludesUI.ShowWidgetTooltip(self, "Show/Hide Preview", { width = 175 })
            end)
            eyeBtn:SetScript("OnLeave", function(self)
                CludesUI.SetGlyphAlpha(self, Off() and 0.15 or 0.4)
                CludesUI.HideWidgetTooltip()
            end)
        end

        -- Scale + Background Opacity: side-by-side dual row.
        local scaleRow
        scaleRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Scale",
            disabled = ModOff,
            disabledTooltip = "the module",
            min = 0.5,
            max = 2.0,
            step = 0.01,
            isPercent = false,
            getValue = Or("scale", 1.0),
            setValue = Keep("scale"),
        }, {
            type = "slider",
            text = "Background Opacity",
            disabled = ModOff,
            disabledTooltip = "the module",
            min = 0,
            max = 100,
            step = 5,
            isPercent = false,
            -- Stored 0..1 internally; displayed 0..100 to the user.
            getValue = function()
                return (Cfg("standaloneAlpha") or 0) * 100
            end,
            setValue = function(v)
                Set("standaloneAlpha", v / 100)
                Refresh()
            end,
        })
        posY = posY - hgt

        -- Inline RESIZE cog on Scale: Frame Width slider
        if not CludesUI._prebuilding then
            local leftRgn = scaleRow._leftRegion
            CludesUI.BuildInlineCog(leftRgn, {
                title = "Frame Width",
                rows = {
                    {
                        type = "slider",
                        label = "Width",
                        min = 180,
                        max = 420,
                        step = 1,
                        get = Or("frameWidth", 260),
                        set = Keep("frameWidth"),
                    },
                },
                gap = 6,
                chain = false,
                disabled = ModOff,
                disabledTooltip = "the module",
            })
        end

        -- Bar Width and the border apply to the timer bar and the forces bar alike,
        -- so they stay usable while either bar is shown.
        local function _barsOff()
            return Cfg("enabled") == false or (Cfg("showTimerBar") == false and Cfg("showEnemyBar") == false)
        end
        local function _barsReq()
            if Cfg("enabled") == false then
                return "the module"
            end
            return "This option requires Show Timer Bar or Show Enemy Forces to be enabled"
        end

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Bar Width",
            disabled = _barsOff,
            disabledTooltip = _barsReq,
            min = 120,
            max = 420,
            step = 1,
            isPercent = false,
            getValue = Or("barWidth", 210),
            setValue = Keep("barWidth"),
        }, {
            type = "toggle",
            text = "Custom Border Style",
            tooltip = "Show the border style and size controls for the timer bars.",
            disabled = _barsOff,
            disabledTooltip = _barsReq,
            getValue = IsTrue("customBorderStyle"),
            setValue = function(v)
                Set("customBorderStyle", v)
                ApplyBorder()
                CludesUI:RefreshPage(true)
            end,
        })
        posY = posY - hgt

        --Border Style (+ cog) | Border Size (+ inline swatch)
        -- Only built when "Custom Border Style" (above) is on, so the whole
        -- row plus its offset cog and colour swatch stay hidden by default and
        -- reclaim their space when off.
        if Cfg("customBorderStyle") then
            -- The border reaches the forces bar only with Apply to Forces Bar on, so
            -- with the timer bar hidden it has nothing to draw on without it. The
            -- Border Options cog (which holds that toggle) stays usable regardless.
            local function _borderOff()
                if _barsOff() then
                    return true
                end
                return Cfg("showTimerBar") == false and Cfg("borderApplyToForces") == false
            end
            local function _borderReq()
                if _barsOff() then
                    return _barsReq()
                end
                return "This option requires Show Timer Bar or Apply to Forces Bar to be enabled"
            end
            -- Distinct local names on purpose: this border-texture list must NOT
            -- be confused with the bar-texture "texValues"/"texOrder" used by the
            -- timer and forces bar Texture dropdowns. Feeding border textures into
            -- those dropdowns once let a border key get written into barTexture.
            local borderTexValues, borderTexOrder = CludesUI.GetBorderTextureDropdown()
            borderTexValues.shadow = nil
            for idx = #borderTexOrder, 1, -1 do
                if borderTexOrder[idx] == "shadow" then
                    table.remove(borderTexOrder, idx)
                end
            end

            local bsRow
            bsRow, hgt = W:DualRow(
                hostFrame,
                posY,
                {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = _borderOff,
                    disabledTooltip = _borderReq,
                    values = borderTexValues,
                    order = borderTexOrder,
                    getValue = Or("borderTexture", "solid"),
                    setValue = function(v)
                        Set("borderTexture", v)
                        Set("borderTextureOffset", nil)
                        Set("borderTextureOffsetY", nil)
                        Set("borderTextureShiftX", nil)
                        Set("borderTextureShiftY", nil)
                        local selC = CludesUI.GetBorderSelectColor(v)
                        if selC then
                            -- The style's select colour (Pixels grey).
                            Set("borderR", selC.r)
                            Set("borderG", selC.g)
                            Set("borderB", selC.b)
                            Set("borderA", 1)
                        elseif v ~= "solid" then
                            Set("borderR", 1)
                            Set("borderG", 1)
                            Set("borderB", 1)
                            Set("borderA", 1)
                        else
                            Set("borderR", 0)
                            Set("borderG", 0)
                            Set("borderB", 0)
                            Set("borderA", 1)
                        end
                        local defSz = CludesUI.GetBorderDefaultSize("MythicPlus", v)
                        if defSz then
                            Set("borderSize", defSz)
                        end
                        if Cfg("borderSizePx") then
                            Set("borderSizePx", false)
                        end
                        ApplyBorder()
                        CludesUI:RefreshPage(true)
                    end,
                },
                CludesUI.BorderPxSliderCfg({
                    text = "Border Size",
                    disabled = _borderOff,
                    disabledTooltip = _borderReq,
                    getStep = Or("borderSize", 0),
                    setStep = function(step)
                        Set("borderSize", step)
                    end,
                    getTex = Or("borderTexture", "solid"),
                    getPx = function()
                        return Cfg("borderSizePx")
                    end,
                    setPx = function(v)
                        Set("borderSizePx", v)
                    end,
                    apply = function()
                        ApplyBorder()
                        CludesUI:RefreshPage()
                    end,
                })
            )
            posY = posY - hgt
            -- Width Offset | Height Offset: only while a textured style is
            -- selected (a solid border has no outward offsets). Built during
            -- prebuild too so the y advance is identical whenever it is present.
            local borderTex = Cfg("borderTexture") or "solid"
            if borderTex ~= "" and borderTex ~= "solid" then
                local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "MythicPlus",
                    getTex = Or("borderTexture", "solid"),
                    getStep = Or("borderSize", 0),
                    getSizeKey = Or("borderSize", 0),
                    getPx = function()
                        return Cfg("borderSizePx")
                    end,
                    getX = function()
                        return Cfg("borderTextureOffset")
                    end,
                    setX = function(v)
                        Set("borderTextureOffset", v)
                    end,
                    getY = function()
                        return Cfg("borderTextureOffsetY")
                    end,
                    setY = function(v)
                        Set("borderTextureOffsetY", v)
                    end,
                    apply = function()
                        ApplyBorder()
                    end,
                })
                ocfgL.disabled, ocfgL.disabledTooltip = _borderOff, _borderReq
                ocfgR.disabled, ocfgR.disabledTooltip = _borderOff, _borderReq
                row, hgt = W:DualRow(hostFrame, posY, ocfgL, ocfgR)
                posY = posY - hgt
            end
            -- Inline cog for border options (left region)
            if not CludesUI._prebuilding then
                local region = bsRow._leftRegion
                CludesUI.BuildInlineCog(region, {
                    title = "Border Options",
                    -- Greys with the bars; stays usable when only Apply to Forces Bar is off.
                    disabled = _barsOff,
                    disabledTooltip = _barsReq,
                    rows = {
                        {
                            type = "toggle",
                            label = "Apply to Forces Bar",
                            get = NotOff("borderApplyToForces"),
                            set = function(v)
                                Set("borderApplyToForces", v)
                                ApplyBorder()
                                CludesUI:RefreshPage()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift X",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local v = Cfg("borderTextureShiftX")
                                if v then
                                    return v
                                end
                                local tex = Cfg("borderTexture") or "solid"
                                local sz = Cfg("borderSize") or 1
                                local _, _, dsx = CludesUI.GetBorderDefaults("MythicPlus", tex, sz)
                                return dsx
                            end,
                            set = function(v)
                                Set("borderTextureShiftX", v == 0 and nil or v)
                                ApplyBorder()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local v = Cfg("borderTextureShiftY")
                                if v then
                                    return v
                                end
                                local tex = Cfg("borderTexture") or "solid"
                                local sz = Cfg("borderSize") or 1
                                local _, _, _, dsy = CludesUI.GetBorderDefaults("MythicPlus", tex, sz)
                                return dsy
                            end,
                            set = function(v)
                                Set("borderTextureShiftY", v == 0 and nil or v)
                                ApplyBorder()
                            end,
                        },
                    },
                    anchorTo = region._control,
                })
            end
            -- Inline color swatch on Border Size (right region)
            if not CludesUI._prebuilding then
                local region = bsRow._rightRegion
                local ctrl = region._control
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 3,
                    function()
                        return Cfg("borderR") or 0,
                            Cfg("borderG") or 0,
                            Cfg("borderB") or 0,
                            Cfg("borderA") or 1
                    end,
                    function(r, g, b, a)
                        Set("borderR", r)
                        Set("borderG", g)
                        Set("borderB", b)
                        Set("borderA", a)
                        ApplyBorder()
                    end,
                    true,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                -- Disabled block: swallows clicks and shows the requirement tooltip.
                local block = CreateFrame("Frame", nil, colorSwatch)
                block:SetAllPoints()
                block:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip(_borderReq()))
                end)
                block:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local function UpdateSwatch()
                    updateSwatch()
                    local off = _borderOff()
                    colorSwatch:SetAlpha(off and 0.3 or 1)
                    block:SetShown(off)
                end
                CludesUI.RegisterWidgetRefresh(UpdateSwatch)
                UpdateSwatch()
            end
        end

        -- Inline color swatch attached to a DualRow region (left of the control,
        -- chaining off rgn._lastInline so it coexists with an inline cog). Blocked
        -- + dimmed via overlay when isDisabled() is true, mirroring the cog pattern.
        local function _AttachInlineSwatch(
            region,
            colorKey,
            defR,
            defG,
            defB,
            afterSet,
            isDisabled,
            disabledTip
        )
            local Pix = CludesUI.PP
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local c = Cfg(colorKey)
                    if c then
                        return c.r or defR, c.g or defG, c.b or defB, 1
                    end
                    return defR, defG, defB, 1
                end,
                function(r, g, b)
                    Set(colorKey, { r = r, g = g, b = b })
                    if afterSet then
                        afterSet(r, g, b)
                    end
                    Refresh()
                end,
                false,
                18
            )
            Pix.Point(colorSwatch, "RIGHT", region._lastInline or region._control or region, "LEFT", -8, 0)
            region._lastInline = colorSwatch
            local block = CreateFrame("Frame", nil, colorSwatch)
            block:SetAllPoints()
            block:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip(disabledTip or "the module"))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateState()
                if updateSwatch then
                    updateSwatch()
                end
                if isDisabled and isDisabled() then
                    colorSwatch:SetAlpha(0.3)
                    block:Show()
                else
                    colorSwatch:SetAlpha(1)
                    block:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateState)
            UpdateState()
            return colorSwatch
        end

        -- Attach the accent + custom colour pair as two INLINE swatches on a
        -- DualRow region, chaining off rgn._lastInline. Click the accent swatch
        -- to follow the theme accent; click the custom swatch to switch to a
        -- custom colour (opens the picker).
        -- The inactive swatch dims to 0.3; both are blocked + dimmed with the
        -- requirement tooltip while isDisabled() is true (mirrors _AttachInlineSwatch).
        -- followTip/followColor optionally replace the accent swatch's label and
        -- color source when the "follow" color is not the theme accent.
        local function _AttachInlineAccentSwatches(
            region,
            useAccentKey,
            colorKey,
            defR,
            defG,
            defB,
            isDisabled,
            disabledTip,
            followTip,
            followColor
        )
            local Pix = CludesUI.PP

            -- Accent swatch (nearest the control, or the cog): live theme accent.
            local accentSwatch, updateAccent = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local ar, ag, ab
                    if followColor then
                        ar, ag, ab = followColor()
                    else
                        ar, ag, ab = CludesUI.ResolveActiveAccent()
                    end
                    return ar, ag, ab, 1
                end,
                function() end,
                false,
                18
            )
            accentSwatch:SetScript("OnClick", function()
                Set(useAccentKey, true)
                Refresh()
                CludesUI:RefreshPage()
            end)
            Pix.Point(accentSwatch, "RIGHT", region._lastInline or region._control or region, "LEFT", -8, 0)
            region._lastInline = accentSwatch

            -- Custom-colour swatch (to the left of accent): the stored custom colour.
            local customSwatch, updateCustom = CludesUI.BuildColorSwatch(
                region,
                region:GetFrameLevel() + 5,
                function()
                    local c = Cfg(colorKey)
                    if c then
                        return c.r or defR, c.g or defG, c.b or defB, 1
                    end
                    return defR, defG, defB, 1
                end,
                function(r, g, b)
                    Set(colorKey, { r = r, g = g, b = b })
                    Refresh()
                end,
                false,
                18
            )
            -- Preserve BuildColorSwatch's picker click, but while accent mode is on a
            -- click just switches back to custom mode (accent turns off) instead.
            local openPicker = customSwatch:GetScript("OnClick")
            customSwatch:SetScript("OnClick", function(self)
                if Cfg(useAccentKey) ~= false then
                    Set(useAccentKey, false)
                    Refresh()
                    CludesUI:RefreshPage()
                    return
                end
                if openPicker then
                    openPicker(self)
                end
            end)
            Pix.Point(customSwatch, "RIGHT", region._lastInline or region._control or region, "LEFT", -8, 0)
            region._lastInline = customSwatch

            -- Per-swatch hover tooltip (colour name when enabled) + disabled block.
            local function AddBlock(sw, enterTip)
                sw:HookScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(sw, enterTip)
                end)
                sw:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                local block = CreateFrame("Frame", nil, sw)
                block:SetAllPoints()
                block:SetFrameLevel(sw:GetFrameLevel() + 10)
                block:EnableMouse(true)
                block:SetScript("OnEnter", function()
                    -- disabledTip may be a function, like a DualRow cfg.disabledTooltip.
                    local tipText = disabledTip
                    if type(tipText) == "function" then
                        tipText = tipText()
                    end
                    CludesUI.ShowWidgetTooltip(sw, CludesUI.DisabledTooltip(tipText or "the module"))
                end)
                block:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                sw._block = block
            end
            AddBlock(accentSwatch, followTip or "Accent Color")
            AddBlock(customSwatch, "Custom Color")

            local function UpdateState()
                if updateAccent then
                    updateAccent()
                end
                if updateCustom then
                    updateCustom()
                end
                local disabled = isDisabled and isDisabled()
                local useAccent = Cfg(useAccentKey) ~= false
                if disabled then
                    accentSwatch:SetAlpha(0.15)
                    accentSwatch._block:Show()
                    customSwatch:SetAlpha(0.15)
                    customSwatch._block:Show()
                else
                    accentSwatch:SetAlpha(useAccent and 1 or 0.3)
                    accentSwatch._block:Hide()
                    customSwatch:SetAlpha(useAccent and 0.3 or 1)
                    customSwatch._block:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateState)
            UpdateState()
        end

        local timerDisplayValues = {
            REMAINING = "11:37",
            REMAINING_TOTAL = "11:37 / 33:00",
            ELAPSED = "21:23",
            ELAPSED_DETAIL = "21:23 (11:37 / 33:00)",
        }
        local timerDisplayOrder = { "REMAINING", "REMAINING_TOTAL", "ELAPSED", "ELAPSED_DETAIL" }
        local timerBarStyleValues = { TICKS = "Ticks", SEGMENTS = "Gaps" }
        local timerBarStyleOrder = { "TICKS", "SEGMENTS" }
        local texValues, texOrder = BuildBarTexDropdown()

        -- Cog disabled tooltips: a cog greys out with the module OR its section
        -- toggle, so name whichever is actually off.
        local function ModuleOr(noun)
            return function()
                if Cfg("enabled") == false then
                    return "the module"
                end
                return noun
            end
        end

        _, hgt = W:SectionHeader(hostFrame, "TITLE AND AFFIXES", posY)
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Title",
            disabled = ModOff,
            disabledTooltip = "the module",
            getValue = NotOff("showTitle"),
            setValue = Keep("showTitle"),
        }, {
            type = "slider",
            text = "Title Size",
            min = 8,
            max = 24,
            step = 1,
            trackWidth = 130,
            disabled = OffWith("showTitle"),
            disabledTooltip = ModuleOr("Show Title"),
            getValue = Or("titleSize", 16),
            setValue = Keep("titleSize"),
        })
        -- Regular-cog settings popup on Show Title: Show Dungeon Name (default on;
        -- when off the title shows only the +key level, not the dungeon name).
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Title",
                gap = 6,
                rows = {
                    {
                        type = "toggle",
                        label = "Show Dungeon Name",
                        get = NotOff("showDungeonName"),
                        set = Keep("showDungeonName"),
                    },
                    -- Moves the lone "+key" title down onto the timer line as "+21  |  timer".
                    -- Only meaningful when the dungeon name is hidden, so it is gated on that.
                    {
                        type = "toggle",
                        label = "Show Key Level on Timer",
                        disabled = NotOff("showDungeonName"),
                        disabledTooltip = "Show Dungeon Name",
                        requireState = "disabled",
                        get = IsTrue("showKeyLevelOnTimer"),
                        set = Keep("showKeyLevelOnTimer"),
                    },
                    {
                        type = "slider",
                        pixel = true,
                        label = "Spacing",
                        min = 0,
                        max = 40,
                        step = 1,
                        disabled = function()
                            return Cfg("showKeyLevelOnTimer") ~= true
                        end,
                        disabledTooltip = "Show Key Level on Timer",
                        get = Or("keyLevelTimerSpacing", 8),
                        set = Keep("keyLevelTimerSpacing"),
                    },
                },
                disabled = OffWith("showTitle"),
                disabledTooltip = ModuleOr("Show Title"),
            })
            -- Inline accent + custom colour swatches on the Title Size slider.
            _AttachInlineAccentSwatches(
                row._rightRegion,
                "titleUseAccent",
                "titleColor",
                1,
                1,
                1,
                OffWith("showTitle"),
                "Show Title"
            )
        end
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Affix",
            disabled = ModOff,
            disabledTooltip = "the module",
            getValue = NotOff("showAffixes"),
            setValue = Keep("showAffixes"),
        }, {
            type = "dropdown",
            text = "Title/Affix Position",
            disabled = ModOff,
            disabledTooltip = "the module",
            values = titleAffixPositionValues,
            order = titleAffixPositionOrder,
            getValue = Or("titleAffixPosition", "ABOVE_TIMER"),
            setValue = Keep("titleAffixPosition", true),
        })
        -- Inline Affix Size cog on Show Affix (cog before swatch), then the Affix Color swatch
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Affix Size",
                gap = 6,
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 20,
                        step = 1,
                        get = Or("affixSize", 12),
                        set = Keep("affixSize"),
                    },
                },
                disabled = OffWith("showAffixes"),
                disabledTooltip = ModuleOr("Show Affix"),
            })
            _AttachInlineSwatch(
                row._leftRegion,
                "affixTextColor",
                1,
                1,
                1,
                nil,
                OffWith("showAffixes"),
                "Show Affix"
            )
            -- Title/Affix Spacing cog on Position (now the right-side widget)
            CludesUI.BuildInlineCog(row._rightRegion, {
                title = "Title/Affix Spacing",
                gap = 6,
                rows = {
                    {
                        type = "slider",
                        pixel = true,
                        label = "Death Gap",
                        min = -10,
                        max = 30,
                        step = 1,
                        disabled = function()
                            return (Cfg("titleAffixPosition") or "ABOVE_TIMER") == "BELOW_TIMER"
                        end,
                        disabledTooltip = "Above Timer",
                        get = Or("titleAffixDeathGap", 11),
                        set = Keep("titleAffixDeathGap"),
                    },
                    {
                        type = "slider",
                        pixel = true,
                        label = "Timer Gap",
                        min = -10,
                        max = 30,
                        step = 1,
                        disabled = function()
                            return (Cfg("titleAffixPosition") or "ABOVE_TIMER") ~= "BELOW_TIMER"
                        end,
                        disabledTooltip = "Below Timer",
                        get = function()
                            return Cfg("titleAffixTimerGap") or Cfg("titleAffixSandwichGap") or 6
                        end,
                        set = Keep("titleAffixTimerGap"),
                    },
                    {
                        type = "slider",
                        pixel = true,
                        label = "Bar Gap",
                        min = -10,
                        max = 30,
                        step = 1,
                        disabled = function()
                            return (Cfg("titleAffixPosition") or "ABOVE_TIMER") ~= "BELOW_TIMER"
                        end,
                        disabledTooltip = "Below Timer",
                        get = function()
                            return Cfg("titleAffixBarGap") or Cfg("titleAffixSandwichGap") or 6
                        end,
                        set = Keep("titleAffixBarGap"),
                    },
                },
                disabled = ModOff,
                disabledTooltip = "the module",
            })
        end
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "TIMER", posY)
        posY = posY - hgt

        local timerFontValues, timerFontOrder = CludesUI.BuildFontDropdownData()
        -- Timer Size only drives the standalone clock; the in-bar timer text has a fixed size.
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Timer Size",
            disabled = function()
                return Cfg("enabled") == false or (Cfg("timerInBar") == true and Cfg("showTimerBar") ~= false)
            end,
            disabledTooltip = function()
                if Cfg("enabled") == false then
                    return "the module"
                end
                return "This option requires Move Timer Inside Bar to be disabled"
            end,
            min = 10,
            max = 32,
            step = 1,
            isPercent = false,
            getValue = Or("timerTextSize", 20),
            setValue = Keep("timerTextSize"),
        }, {
            type = "dropdown",
            text = "Timer Format",
            disabled = ModOff,
            disabledTooltip = "the module",
            values = timerDisplayValues,
            order = timerDisplayOrder,
            getValue = Or("timerDisplayMode", "REMAINING_TOTAL"),
            setValue = Keep("timerDisplayMode"),
        })
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Timer Font",
            disabled = ModOff,
            disabledTooltip = "the module",
            values = timerFontValues,
            order = timerFontOrder,
            getValue = Or("timerFont", "__global"),
            setValue = Keep("timerFont"),
        }, CludesUI.BlankRowCfg())
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "TIMER BAR", posY)
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Timer Bar",
            disabled = ModOff,
            disabledTooltip = "the module",
            getValue = NotOff("showTimerBar"),
            setValue = Keep("showTimerBar", true),
        }, {
            type = "toggle",
            text = "Move Timer Inside Bar",
            disabled = OffWith("showTimerBar"),
            disabledTooltip = ModuleOr("Show Timer Bar"),
            getValue = IsTrue("timerInBar"),
            setValue = Keep("timerInBar", true),
        })
        if not CludesUI._prebuilding then
            -- These rows only affect the in-bar timer, so the cog also requires Move Timer Inside Bar.
            CludesUI.BuildInlineCog(row._rightRegion, {
                title = "In-Bar Timer",
                gap = 6,
                rows = {
                    {
                        type = "slider",
                        label = "In-Bar Height",
                        min = 8,
                        max = 40,
                        step = 1,
                        tooltip = "Minimum height of the timer bar while the timer is inside it. The larger of this and Timer Bar Height is used.",
                        get = Or("barHeightExpanded", 22),
                        set = Keep("barHeightExpanded"),
                    },
                    {
                        type = "slider",
                        label = "Fill Opacity",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        tooltip = "Opacity of the bar fill while the timer is inside it.",
                        get = Or("barFillAlphaExpanded", 0.85),
                        set = Keep("barFillAlphaExpanded"),
                    },
                    {
                        type = "toggle",
                        label = "Left Text",
                        tooltip = "Align the timer text to the left edge of the bar instead of centering it.",
                        get = IsTrue("timerInBarLeftText"),
                        set = Keep("timerInBarLeftText"),
                    },
                },
                disabled = function()
                    return Cfg("enabled") == false
                        or Cfg("showTimerBar") == false
                        or Cfg("timerInBar") ~= true
                end,
                disabledTooltip = function()
                    if Cfg("enabled") == false then
                        return "the module"
                    end
                    if Cfg("showTimerBar") == false then
                        return "Show Timer Bar"
                    end
                    return "Move Timer Inside Bar"
                end,
            })
        end
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Timer Bar Height",
            tooltip = "Height of the timer bar. While the timer is inside the bar, In-Bar Height sets the minimum.",
            disabled = OffWith("showTimerBar"),
            disabledTooltip = ModuleOr("Show Timer Bar"),
            min = 4,
            max = 30,
            step = 1,
            isPercent = false,
            getValue = Or("barHeight", 8),
            setValue = function(v)
                -- Pin the forces bar to its current height before the first
                -- change, so the two height sliders act independently.
                if Cfg("enemyBarHeight") == nil then
                    Set("enemyBarHeight", Cfg("barHeight") or 8)
                end
                Set("barHeight", v)
                Refresh()
            end,
        }, {
            type = "dropdown",
            text = "Timer Bar Texture",
            disabled = OffWith("showTimerBar"),
            disabledTooltip = ModuleOr("Show Timer Bar"),
            values = texValues,
            order = texOrder,
            getValue = Or("barTexture", "none"),
            setValue = Keep("barTexture"),
        })
        -- Inline cog on Bar Texture: the bar's background texture
        CludesUI.BuildInlineCog(row._rightRegion, {
            title = "Bar Texture",
            gap = 6,
            rows = {
                {
                    type = "dropdown",
                    label = "Background Texture",
                    values = texValues,
                    order = texOrder,
                    get = Or("barBgTexture", "none"),
                    set = Keep("barBgTexture"),
                },
            },
            disabled = OffWith("showTimerBar"),
            disabledTooltip = ModuleOr("Show Timer Bar"),
        })
        posY = posY - hgt

        -- Builds a threshold toggle config plus an attach() that hangs the inline
        -- RESIZE cog (white text / size / x / y) and the colour swatch onto a given
        -- DualRow region, so two thresholds can share one dual row.
        local function _ThresholdWidget(
            labelText,
            barColorKey,
            showKey,
            sizeKey,
            offsetXKey,
            offsetYKey,
            whiteKey,
            defR,
            defG,
            defB,
            afterBarSet
        )
            local function IsTimerTextShown()
                if showKey == "showThreshRemaining" then
                    return Cfg(showKey) == true
                end
                return Cfg(showKey) ~= false
            end

            local conf = {
                type = "toggle",
                text = "Show " .. labelText .. " Timer Text",
                tooltip = "Show Timer Text",
                disabled = ModOff,
                disabledTooltip = "the module",
                getValue = IsTimerTextShown,
                setValue = function(v)
                    Set(showKey, v)
                    Refresh()
                end,
            }

            local function attach(region)
                -- Inline RESIZE cog (white text / size / x / y) on the toggle first so it
                -- sits adjacent to the control, before the swatch (cog-before-swatch rule).
                CludesUI.BuildInlineCog(region, {
                    title = labelText .. " Timer Text",
                    gap = 6,
                    rows = {
                        {
                            type = "toggle",
                            label = "White Text",
                            get = function()
                                return Cfg(whiteKey) == true
                            end,
                            set = function(v)
                                Set(whiteKey, v)
                                Refresh()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Text Size",
                            min = 6,
                            max = 20,
                            step = 1,
                            get = function()
                                return Cfg(sizeKey) or Cfg("thresholdSize") or 12
                            end,
                            set = function(v)
                                Set(sizeKey, v)
                                Refresh()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Text X",
                            min = -80,
                            max = 80,
                            step = 1,
                            get = function()
                                return Cfg(offsetXKey) or Cfg("thresholdTextOffsetX") or 0
                            end,
                            set = function(v)
                                Set(offsetXKey, v)
                                Refresh()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Text Y",
                            min = -40,
                            max = 40,
                            step = 1,
                            get = function()
                                return Cfg(offsetYKey) or Cfg("thresholdTextOffsetY") or 0
                            end,
                            set = function(v)
                                Set(offsetYKey, v)
                                Refresh()
                            end,
                        },
                    },
                    disabled = function()
                        return Cfg("enabled") == false or not IsTimerTextShown()
                    end,
                    disabledTooltip = ModuleOr(conf.text),
                })
                -- Inline colour swatch (the +N threshold / segment colour), left of the cog
                _AttachInlineSwatch(region, barColorKey, defR, defG, defB, afterBarSet, ModOff, "the module")
            end

            return conf, attach
        end

        _, hgt = W:SectionHeader(hostFrame, "THRESHOLDS", posY)
        posY = posY - hgt

        local p3cfg, p3attach = _ThresholdWidget(
            "+3 Threshold",
            "timerSegment1Color",
            "showPlusThreeTimer",
            "thresholdPlusThreeSize",
            "thresholdPlusThreeTextOffsetX",
            "thresholdPlusThreeTextOffsetY",
            "thresholdPlusThreeTextWhite",
            0.4,
            1,
            0.4,
            function(r, g, b)
                Set("timerPlusThreeColor", { r = r, g = g, b = b })
            end
        )
        local p2cfg, p2attach = _ThresholdWidget(
            "+2 Threshold",
            "timerSegment2Color",
            "showPlusTwoTimer",
            "thresholdPlusTwoSize",
            "thresholdPlusTwoTextOffsetX",
            "thresholdPlusTwoTextOffsetY",
            "thresholdPlusTwoTextWhite",
            0.3,
            0.8,
            1,
            function(r, g, b)
                Set("timerPlusTwoColor", { r = r, g = g, b = b })
            end
        )
        local p1cfg, p1attach = _ThresholdWidget(
            "+1 Threshold",
            "timerSegment3Color",
            "showThreshRemaining",
            "thresholdPlusOneSize",
            "thresholdPlusOneTextOffsetX",
            "thresholdPlusOneTextOffsetY",
            "thresholdPlusOneTextWhite",
            0.69,
            0.35,
            0.8
        )

        -- Row 1: Ticks / Gaps (style + inline cog + Tick Color swatch) | +3 Threshold
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Ticks / Gaps",
            disabled = OffWith("showTimerBar"),
            disabledTooltip = ModuleOr("Show Timer Bar"),
            values = timerBarStyleValues,
            order = timerBarStyleOrder,
            getValue = Or("timerBarStyle", "TICKS"),
            setValue = Keep("timerBarStyle", true),
        }, p3cfg)
        -- Inline cog first so it sits adjacent to the control, then the Tick Color
        -- swatch (TICKS style only) left of it (cog-before-swatch rule).
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Ticks / Gaps",
                gap = 6,
                rows = {
                    {
                        type = "slider",
                        label = "Tick Opacity",
                        min = 0,
                        max = 1,
                        step = 0.05,
                        disabled = function()
                            return (Cfg("timerBarStyle") or "TICKS") ~= "TICKS"
                        end,
                        disabledTooltip = "Ticks",
                        get = Or("tickAlpha", 1),
                        set = Keep("tickAlpha"),
                    },
                    {
                        type = "slider",
                        pixel = true,
                        label = "Gap Size",
                        min = 0,
                        max = 12,
                        step = 1,
                        disabled = function()
                            return (Cfg("timerBarStyle") or "TICKS") ~= "SEGMENTS"
                        end,
                        disabledTooltip = "Gaps",
                        get = Or("timerBarSegmentGap", 2),
                        set = Keep("timerBarSegmentGap"),
                    },
                },
                disabled = OffWith("showTimerBar"),
                disabledTooltip = ModuleOr("Show Timer Bar"),
            })
            _AttachInlineSwatch(row._leftRegion, "timerTickColor", 1, 1, 1, nil, function()
                return Cfg("enabled") == false
                    or Cfg("showTimerBar") == false
                    or (Cfg("timerBarStyle") or "TICKS") ~= "TICKS"
            end, "Ticks")
            p3attach(row._rightRegion)
        end
        posY = posY - hgt

        -- Row 2: +2 Threshold | +1 Threshold
        row, hgt = W:DualRow(hostFrame, posY, p2cfg, p1cfg)
        if not CludesUI._prebuilding then
            p2attach(row._leftRegion)
            p1attach(row._rightRegion)
        end
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "FORCES", posY)
        posY = posY - hgt

        local function _forcesOff()
            return Cfg("enabled") == false or Cfg("showEnemyBar") == false
        end

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Enemy Forces",
            disabled = ModOff,
            disabledTooltip = "the module",
            getValue = NotOff("showEnemyBar"),
            setValue = Keep("showEnemyBar", true),
        }, {
            type = "slider",
            text = "Forces Bar Height",
            disabled = _forcesOff,
            disabledTooltip = ModuleOr("Show Enemy Forces"),
            min = 4,
            max = 30,
            step = 1,
            isPercent = false,
            -- enemyBarHeight stays unset until either height slider is changed
            -- and falls back to the timer bar height, so existing layouts keep
            -- their look.
            getValue = function()
                return Cfg("enemyBarHeight") or Cfg("barHeight") or 8
            end,
            setValue = Keep("enemyBarHeight"),
        })
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Enemy Text Format",
            disabled = _forcesOff,
            disabledTooltip = ModuleOr("Show Enemy Forces"),
            values = forcesTextValues,
            order = forcesTextOrder,
            getValue = Or("enemyForcesTextFormat", "PERCENT"),
            setValue = Keep("enemyForcesTextFormat"),
        }, {
            type = "dropdown",
            text = "Percent Position",
            tooltip = "Where the enemy forces percentage is shown: in the label text, in the bar or beside it.",
            disabled = _forcesOff,
            disabledTooltip = ModuleOr("Show Enemy Forces"),
            values = { LABEL = "In Label Text", BAR = "In Bar", BESIDE = "Beside Bar" },
            order = { "LABEL", "BAR", "BESIDE" },
            getValue = Or("enemyForcesPctPos", "LABEL"),
            setValue = Keep("enemyForcesPctPos"),
        })
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Enemy Forces Text",
                gap = 6,
                rows = {
                    {
                        type = "toggle",
                        label = "Hide Label",
                        get = IsTrue("hideEnemyForcesLabel"),
                        set = Keep("hideEnemyForcesLabel"),
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 8,
                        max = 24,
                        step = 1,
                        get = function()
                            return Cfg("enemyForcesTextSize") or Cfg("objectivesSize") or 12
                        end,
                        set = Keep("enemyForcesTextSize"),
                    },
                    {
                        type = "slider",
                        label = "Text X",
                        min = -80,
                        max = 80,
                        step = 1,
                        get = Or("enemyForcesTextOffsetX", 0),
                        set = Keep("enemyForcesTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Text Y",
                        min = -40,
                        max = 40,
                        step = 1,
                        get = Or("enemyForcesTextOffsetY", 0),
                        set = Keep("enemyForcesTextOffsetY"),
                    },
                },
                disabled = _forcesOff,
                disabledTooltip = ModuleOr("Show Enemy Forces"),
            })
        end
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Enemy Forces Position",
            disabled = _forcesOff,
            disabledTooltip = ModuleOr("Show Enemy Forces"),
            values = { BOTTOM = "Bottom", UNDER_BAR = "Under Timer Bar" },
            order = { "BOTTOM", "UNDER_BAR" },
            getValue = Or("enemyForcesPos", "BOTTOM"),
            setValue = Keep("enemyForcesPos"),
        }, {
            type = "dropdown",
            text = "Forces Bar Texture",
            tooltip = "Texture of the enemy forces bar. The swatches next to it set the Enemy Bar Color (theme accent or a custom color).",
            disabled = _forcesOff,
            disabledTooltip = ModuleOr("Show Enemy Forces"),
            values = texValues,
            order = texOrder,
            getValue = Or("enemyBarTexture", "none"),
            setValue = Keep("enemyBarTexture"),
        })
        if not CludesUI._prebuilding then
            -- The background texture cog, then the fill colour (accent or custom) as inline swatches.
            CludesUI.BuildInlineCog(row._rightRegion, {
                title = "Bar Texture",
                gap = 6,
                rows = {
                    {
                        type = "dropdown",
                        label = "Background Texture",
                        values = texValues,
                        order = texOrder,
                        get = Or("enemyBarBgTexture", "none"),
                        set = Keep("enemyBarBgTexture"),
                    },
                },
                disabled = _forcesOff,
                disabledTooltip = ModuleOr("Show Enemy Forces"),
            })
            _AttachInlineAccentSwatches(
                row._rightRegion,
                "enemyBarUseAccent",
                "enemyBarColor",
                0.35,
                0.55,
                0.8,
                _forcesOff,
                ModuleOr("Show Enemy Forces")
            )
        end
        posY = posY - hgt

        -- The pull bar's default color is the forces fill color (accent or custom).
        local function _enemyBarColor()
            if Cfg("enemyBarUseAccent") ~= false then
                return CludesUI.ResolveActiveAccent()
            end
            local c = Cfg("enemyBarColor")
            if c then
                return c.r or 0.35, c.g or 0.55, c.b or 0.8
            end
            return 0.35, 0.55, 0.8
        end
        local function _pullBarOff()
            return _forcesOff() or Cfg("showPullBar") ~= true
        end
        -- Names whichever requirement actually disables the pull controls.
        local function _pullBarReq()
            if Cfg("enabled") == false then
                return "the module"
            end
            if Cfg("showEnemyBar") == false then
                return "Show Enemy Forces"
            end
            return "Show Current Pull in Bar"
        end
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Current Pull in Bar",
            disabled = _forcesOff,
            disabledTooltip = ModuleOr("Show Enemy Forces"),
            tooltip = "Previews the forces of every enemy in combat with a visible nameplate on the enemy forces bar.",
            getValue = IsTrue("showPullBar"),
            setValue = Keep("showPullBar", true),
        }, {
            type = "slider",
            text = "Current Pull Color",
            min = 0,
            max = 100,
            step = 5,
            isPercent = false,
            trackWidth = 130,
            disabled = _pullBarOff,
            disabledTooltip = _pullBarReq,
            tooltip = "Opacity of the current pull on the enemy forces bar.",
            -- Stored 0..1 internally; displayed 0..100 to the user.
            getValue = function()
                return (Cfg("pullBarAlpha") or 0.35) * 100
            end,
            setValue = function(v)
                Set("pullBarAlpha", v / 100)
                Refresh()
            end,
        })
        if not CludesUI._prebuilding then
            -- Pull color: follows the enemy bar color by default, or a custom color.
            _AttachInlineAccentSwatches(
                row._rightRegion,
                "pullBarUseBarColor",
                "pullBarColor",
                1,
                0.55,
                0.1,
                _pullBarOff,
                _pullBarReq,
                "Enemy Bar Color",
                _enemyBarColor
            )
        end
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "BOSS OBJECTIVES", posY)
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Boss Objectives",
            disabled = ModOff,
            disabledTooltip = "the module",
            getValue = NotOff("showObjectives"),
            setValue = Keep("showObjectives", true),
        }, {
            type = "slider",
            text = "Objectives Size",
            disabled = OffWith("showObjectives"),
            disabledTooltip = ModuleOr("Show Boss Objectives"),
            min = 8,
            max = 20,
            step = 1,
            isPercent = false,
            getValue = Or("objectivesSize", 12),
            setValue = Keep("objectivesSize"),
        })
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                title = "Boss Position",
                gap = 6,
                rows = {
                    {
                        type = "slider",
                        label = "Boss X",
                        min = -80,
                        max = 80,
                        step = 1,
                        get = Or("objectiveTextOffsetX", 0),
                        set = Keep("objectiveTextOffsetX"),
                    },
                    {
                        type = "slider",
                        label = "Boss Y",
                        min = -40,
                        max = 40,
                        step = 1,
                        get = Or("objectiveTextOffsetY", 0),
                        set = Keep("objectiveTextOffsetY"),
                    },
                },
                disabled = OffWith("showObjectives"),
                disabledTooltip = ModuleOr("Show Boss Objectives"),
            })
        end
        posY = posY - hgt

        -- Time Position also places the Split Compare text, so it stays usable
        -- while either the objective times or a compare mode is shown.
        row, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Objective Times",
            disabled = OffWith("showObjectives"),
            disabledTooltip = ModuleOr("Show Boss Objectives"),
            getValue = NotOff("showObjectiveTimes"),
            setValue = Keep("showObjectiveTimes"),
        }, {
            type = "dropdown",
            text = "Time Position",
            tooltip = "Which side of each boss objective shows its split times and Split Compare text.",
            disabled = function()
                return Cfg("enabled") == false
                    or Cfg("showObjectives") == false
                    or (
                        Cfg("showObjectiveTimes") == false
                        and (Cfg("objectiveCompareMode") or "NONE") == "NONE"
                    )
            end,
            disabledTooltip = function()
                if Cfg("enabled") == false then
                    return "the module"
                end
                if Cfg("showObjectives") == false then
                    return "Show Boss Objectives"
                end
                return "This option requires Show Objective Times or a Split Compare mode"
            end,
            values = objectiveTimePositionValues,
            order = objectiveTimePositionOrder,
            getValue = Or("objectiveTimePosition", "RIGHT"),
            setValue = Keep("objectiveTimePosition"),
        })
        posY = posY - hgt

        row, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            pixel = true,
            text = "Objective Spacing",
            disabled = OffWith("showObjectives"),
            disabledTooltip = ModuleOr("Show Boss Objectives"),
            min = 0,
            max = 12,
            step = 1,
            isPercent = false,
            getValue = Or("objectiveGap", 4),
            setValue = Keep("objectiveGap"),
        }, {
            type = "dropdown",
            text = "Split Compare",
            disabled = OffWith("showObjectives"),
            disabledTooltip = ModuleOr("Show Boss Objectives"),
            values = compareModeValues,
            order = compareModeOrder,
            getValue = Or("objectiveCompareMode", "NONE"),
            setValue = Keep("objectiveCompareMode"),
        })
        -- Split Compare cog: strict scoping (only meaningful for the level scopes,
        -- since Per Dungeon is the fallback it removes) and the upcoming-split target.
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._rightRegion, {
                title = "Split Compare",
                gap = 6,
                rows = {
                    {
                        type = "toggle",
                        label = "Always Show Split Times",
                        tooltip = "Shows your best split on upcoming bosses instead of only killed ones.",
                        disabled = function()
                            return (Cfg("objectiveCompareMode") or "NONE") == "NONE"
                        end,
                        disabledTooltip = "This option requires a Split Compare mode",
                        get = IsTrue("showUpcomingSplitTargets"),
                        set = Keep("showUpcomingSplitTargets"),
                    },
                    {
                        type = "toggle",
                        label = "Strict Comparison Mode",
                        tooltip = "Compare only against splits from the same key level (off: new key levels compare against your dungeon best).",
                        disabled = function()
                            local mode = Cfg("objectiveCompareMode") or "NONE"
                            return mode ~= "LEVEL" and mode ~= "LEVEL_AFFIX"
                        end,
                        disabledTooltip = "This option requires Split Compare to include a key level",
                        get = IsTrue("objectiveCompareStrict"),
                        set = Keep("objectiveCompareStrict"),
                    },
                    {
                        type = "toggle",
                        label = "Fastest Run Splits",
                        tooltip = "Compare against the splits of your fastest completed run instead of your best individual splits.",
                        disabled = function()
                            return (Cfg("objectiveCompareMode") or "NONE") == "NONE"
                        end,
                        disabledTooltip = "This option requires a Split Compare mode",
                        get = IsTrue("showFastestRunSplits"),
                        set = Keep("showFastestRunSplits"),
                    },
                },
                disabled = OffWith("showObjectives"),
                disabledTooltip = ModuleOr("Show Boss Objectives"),
            })
        end
        posY = posY - hgt

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt

        hostFrame:SetHeight(math.abs(posY - yOffset))
    end

    ---------------------------------------------------------------------------
    --  Shared helpers for the Mythic+ Tools cast-bar tabs
    ---------------------------------------------------------------------------
    local function TSB()
        local p = DB()
        return p and p.tsb
    end
    local function TFB()
        local p = DB()
        return p and p.tfb
    end
    local function TFBBar(which)
        local t = TFB()
        return t and t[which]
    end
    -- The runtime restyles first, the header sample paints second.
    local function TSBRefresh()
        if mod.TSB_Refresh then
            mod.TSB_Refresh()
        end
        PvRepaint(tsbPv)
    end
    local function TFBRefresh()
        if mod.TFB_Refresh then
            mod.TFB_Refresh()
        end
        PvRepaint(tfbPv)
    end

    -- Closure makers for one settings table, so a row names its key once
    -- instead of spelling out the lookup. tbl() hands back the table (nil
    -- until the profile exists) and redraw() follows every write.
    local function Accessors(tbl, redraw)
        local A = {}
        -- The stored value, or def when unset.
        function A.Or(key, def)
            return function()
                local c = tbl()
                return (c and c[key]) or def
            end
        end
        -- The stored value as is.
        function A.Raw(key)
            return function()
                local c = tbl()
                return c and c[key]
            end
        end
        -- A switch that counts as on unless it was turned off.
        function A.NotOff(key)
            return function()
                local c = tbl()
                return not c or c[key] ~= false
            end
        end
        -- A switch that counts as on only once it was turned on.
        function A.IsOn(key)
            return function()
                local c = tbl()
                return c and c[key] == true
            end
        end
        function A.NotOn(key)
            return function()
                local c = tbl()
                return not (c and c[key] == true)
            end
        end
        -- Writers; repaint also redraws the page's widgets afterwards.
        local function Writer(key, cast, repaint)
            return function(v)
                local c = tbl()
                if not c then
                    return
                end
                c[key] = cast(v)
                redraw()
                if repaint then
                    CludesUI:RefreshPage()
                end
            end
        end
        local function Same(v)
            return v
        end
        local function Truth(v)
            return v and true or false
        end
        function A.Put(key, repaint)
            return Writer(key, Same, repaint)
        end
        function A.Flag(key, repaint)
            return Writer(key, Truth, repaint)
        end
        -- A colour kept as { r, g, b }: its reader (defaults per channel) and writer.
        function A.Rgb(key, r0, g0, b0)
            return function()
                local c = tbl()
                local col = c and c[key]
                return (col and col.r) or r0, (col and col.g) or g0, (col and col.b) or b0
            end, function(r, g, b)
                local c = tbl()
                if not c then
                    return
                end
                c[key] = { r = r, g = g, b = b }
                redraw()
            end
        end
        return A
    end

    -- A cog's text rows: size, then the X and Y nudges of keys prefix..Size,
    -- prefix..X and prefix..Y.
    local function TextRows(A, prefix, sizeMax, sizeDef)
        local rows = {
            {
                type = "slider",
                label = "Text Size",
                min = 6,
                max = sizeMax,
                step = 1,
                get = A.Or(prefix .. "Size", sizeDef),
                set = A.Put(prefix .. "Size"),
            },
        }
        for _, axis in ipairs({ "X", "Y" }) do
            rows[#rows + 1] = {
                type = "slider",
                label = axis .. " Offset",
                min = -100,
                max = 100,
                step = 1,
                pixel = true,
                get = A.Or(prefix .. axis, 0),
                set = A.Put(prefix .. axis),
            }
        end
        return rows
    end

    -- The four cast colour swatches the Cast Bars and Target/Focus Bars pages
    -- share (firstKey: where the interruptible colour lives).
    local function CastColorSwatches(A, firstKey)
        local function Swatch(tooltip, key, r, g, b)
            local get, set = A.Rgb(key, r, g, b)
            return { tooltip = tooltip, getValue = get, setValue = set }
        end
        local important = Swatch("Important Cast", "importantColor", 1, 0.2, 0.2)
        important.disabled = A.NotOn("importantEnabled")
        important.disabledTooltip = "Important Cast Color"
        return {
            Swatch("Interruptible Cast", firstKey, 0.70, 0.40, 0.90),
            Swatch("Interrupt on CD", "interruptReady", 0.92, 0.35, 0.20),
            Swatch("Uninterruptible Cast", "uninterruptible", 0.45, 0.45, 0.45),
            important,
        }
    end

    -- Where to Show labels, keyed by the content keys of ns.MTWhere: one
    -- table for every Where to Show list of the module (Targeted Spell Bars,
    -- Kick Tracker).
    local WHERE_LABELS = {
        open_world = "Open World",
        raid_mythic = "Mythic Raid",
        raid_heroic = "Heroic Raid",
        raid_normal_lfr = "Normal/LFR Raid",
        dungeon_mythic = "Mythic Dungeons",
        dungeon_nonmythic = "Non-Mythic Dungeons",
        timewalking = "Timewalking",
        delve = "Delve",
        lair = "Lair",
        scenario = "Scenario",
        arena = "Arena",
        battleground = "Battlegrounds",
        in_combat = "In Combat",
        out_of_combat = "Out of Combat",
    }
    mod._MT_WHERE_LABELS = WHERE_LABELS
    -- The bar texture dropdown data, for the Kick Tracker page (its own file).
    mod._MT_BuildBarTexDropdown = BuildBarTexDropdown

    -- Where to Show: same content-type list and multi-select checkbox
    -- dropdown (CludesUI.BuildVisOptsCBDropdown) as AuraBuffReminders.
    local TSB_WHERE_ITEMS = {}
    do
        local keyList = {
            "open_world",
            "raid_mythic",
            "raid_heroic",
            "raid_normal_lfr",
            "dungeon_mythic",
            "dungeon_nonmythic",
            "timewalking",
            "delve",
            "lair",
            "scenario",
            "in_combat",
            "out_of_combat",
        }
        for idx = 1, #keyList do
            TSB_WHERE_ITEMS[idx] = { key = keyList[idx], label = WHERE_LABELS[keyList[idx]] }
        end
    end
    local function TSBWhere()
        local c = TSB()
        if not c then
            return nil
        end
        c.whereToShow = c.whereToShow or {}
        return c.whereToShow
    end
    -- Positive filter: only selected entries are stored (true); nothing
    -- selected = the bars show everywhere.
    local function TSBWhereGet(k)
        local t = TSBWhere()
        return t and t[k] == true or false
    end
    local function TSBWhereSet(k, v)
        local t = TSBWhere()
        if not t then
            return
        end
        t[k] = v and true or nil
        TSBRefresh()
    end

    -- The cast bar pages' header previews: the Cast Bars group's plain sample
    -- row, and the Target and Focus cast bars side by side. A column whose
    -- runtime export is missing hides instead of erroring. Each painter returns
    -- two values, so the guard is a statement: an `and` chain would keep only
    -- the width.
    local tsbBuilder = PvBuilder(tsbPv, {
        {
            title = "Cast Bars",
            on = function()
                local c = TSB()
                return c and c.enabled == true
            end,
            paint = function(host)
                if mod.TSB_PaintSample then
                    return mod.TSB_PaintSample(host)
                end
            end,
        },
    })
    local tfbBuilder = PvBuilder(tfbPv, {
        {
            title = "Target Cast Bar",
            on = function()
                local c = TFBBar("target")
                return c and c.enabled == true
            end,
            paint = function(host)
                if mod.TFB_PaintSample then
                    return mod.TFB_PaintSample(host, "target")
                end
            end,
        },
        {
            title = "Focus Cast Bar",
            on = function()
                local c = TFBBar("focus")
                return c and c.enabled == true
            end,
            paint = function(host)
                if mod.TFB_PaintSample then
                    return mod.TFB_PaintSample(host, "focus")
                end
            end,
        },
    })

    ---------------------------------------------------------------------------
    --  Targeted Spell Bars page
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    --  Glow site: the Targeted Spell Bars important cast glow as a shared glow
    --  descriptor, used by the TSB page and the Global Settings Glows page. The
    --  bar is an engine host by choice (zero per-frame Lua): C-side styles only.
    ---------------------------------------------------------------------------
    local mtImpGlowDesc
    do
        local GO = CludesUI.GlowOptions
        local function TsbOff()
            local c = TSB()
            return not (c and c.enabled == true)
        end
        mtImpGlowDesc = {
            host = "engine",
            caps = { mode = true, params = true, bg = true },
            defaultColor = { r = 1, g = 0.2, b = 0.2 },
            disabled = TsbOff,
            disabledTooltip = "Enable Cast Bars",
            isOff = function()
                local c = TSB()
                return not (c and c.importantGlow == true)
            end,
            onChange = TSBRefresh,
            get = function(f)
                local c = TSB()
                if not c then
                    return nil
                end
                if f == "style" then
                    return c.importantGlowStyle or 1
                elseif f == "mode" then
                    return c.importantGlowColorMode or "custom"
                elseif f == "color" then
                    local col = c.importantGlowColor
                    return (col and col.r) or 1, (col and col.g) or 0.2, (col and col.b) or 0.2
                end
                return CludesUI.GlowOptions.FlatGet(c, "importantGlow", f)
            end,
            set = function(f, a, b2, c2)
                local c = TSB()
                if not c then
                    return
                end
                if f == "style" then
                    if a == 0 then
                        c.importantGlow = false
                    else
                        c.importantGlow = true
                        c.importantGlowStyle = a
                    end
                elseif f == "mode" then
                    c.importantGlowColorMode = a
                else
                    CludesUI.GlowOptions.FlatSet(c, "importantGlow", f, a, b2, c2)
                end
            end,
        }
        GO.RegisterSite({
            id = "mt_importantcast",
            label = "Important Cast Glow",
            group = "module",
            module = "CludesUIMythicTimer",
            page = PAGE_TSB,
            section = "INTERRUPT AND VISIBILITY",
            highlight = "Important Cast Glow",
            desc = mtImpGlowDesc,
        })
    end

    local function BuildTSBPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, row, hgt

        CludesUI:SetContentHeader(tsbBuilder)
        hostFrame._showRowDivider = true

        local A = Accessors(TSB, TSBRefresh)
        local On = A.IsOn("enabled")
        local function Off()
            return not On()
        end
        local REQ = "Enable Cast Bars"
        -- Every row below greys out with the group's own switch.
        local function Gated(cfg)
            cfg.disabled, cfg.disabledTooltip = Off, REQ
            return cfg
        end
        local function Row(left, right)
            row, hgt = W:DualRow(hostFrame, posY, left, right)
            posY = posY - hgt
            return row
        end
        local function Slider(text, key, lo, hi, def, pixel, tooltip)
            return Gated({
                type = "slider",
                text = text,
                tooltip = tooltip,
                min = lo,
                max = hi,
                step = 1,
                pixel = pixel,
                getValue = A.Or(key, def),
                setValue = A.Put(key),
            })
        end
        local function Toggle(text, key, read, tooltip)
            return Gated({
                type = "toggle",
                text = text,
                tooltip = tooltip,
                getValue = read(key),
                setValue = A.Flag(key),
            })
        end
        local function Cog(region, tip, title, rows)
            CludesUI.BuildInlineCog(region, { tip = tip, title = title, rows = rows })
        end

        local heading
        heading, hgt = W:SectionHeader(hostFrame, "CAST BARS", posY)
        posY = posY - hgt
        CludesUI.BuildSectionUnlockJump(
            heading,
            { key = "EMT_TargetedSpellBars", disabled = Off, disabledTooltip = REQ }
        )

        -- The right half is a stand-in: the Where to Show checkbox dropdown
        -- replaces its control below (outside the search pre-build).
        Row(
            {
                type = "toggle",
                text = "Enable Cast Bars",
                tooltip = "Show one plain cast bar per enemy nameplate that is casting, gathered into a single movable group with the spell name, its target, and the cast timer.",
                getValue = On,
                setValue = A.Flag("enabled", true),
            },
            Gated({
                type = "dropdown",
                text = "Where to Show",
                tooltip = "Limit the bars to the selected content and combat states; nothing selected shows them everywhere.",
                values = { _placeholder = "..." },
                order = { "_placeholder" },
                getValue = function()
                    return "_placeholder"
                end,
                setValue = function() end,
            })
        )
        if not CludesUI._prebuilding then
            local slot = row._rightRegion
            if slot._control then
                slot._control:Hide()
            end
            local where, whereRefresh = CludesUI.BuildVisOptsCBDropdown(
                slot,
                220,
                slot:GetFrameLevel() + 2,
                TSB_WHERE_ITEMS,
                TSBWhereGet,
                TSBWhereSet,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = Off, disabledTooltip = REQ, emptyLabel = "All" }
            )
            CludesUI.PanelPP.Point(where, "RIGHT", slot, "RIGHT", -20, 0)
            slot._control = where
            slot._lastInline = nil
            CludesUI.RegisterWidgetRefresh(whereRefresh)
        end

        Row(
            Gated({
                type = "segmented",
                text = "Grow Direction",
                tooltip = "Which way new bars stack as more enemies start casting.",
                values = { DOWN = "Down", UP = "Up" },
                order = { "DOWN", "UP" },
                getValue = function()
                    local c = TSB()
                    return (c and c.growUp) and "UP" or "DOWN"
                end,
                setValue = function(v)
                    local c = TSB()
                    if c then
                        c.growUp = v == "UP"
                        TSBRefresh()
                    end
                end,
            }),
            Slider("Width", "width", 80, 600, 240, true)
        )
        Row(Slider("Height", "height", 6, 60, 20, true), Slider("Bar Spacing", "spacing", 0, 20, 4, true))

        local texValues, texOrder = BuildBarTexDropdown()
        Row(
            Slider(
                "Max Bars",
                "maxBars",
                1,
                10,
                5,
                nil,
                "The most cast bars shown at once. Extra casters take a bar as soon as one frees up."
            ),
            Gated({
                type = "dropdown",
                text = "Bar Texture",
                values = texValues,
                order = texOrder,
                getValue = A.Or("texture", "none"),
                setValue = A.Put("texture"),
            })
        )

        Row(
            Gated({
                type = "multiSwatch",
                text = "Background Color",
                swatches = {
                    {
                        tooltip = "Background Color",
                        hasAlpha = true,
                        getValue = function()
                            local c = TSB()
                            local col = c and c.bgColor
                            return (col and col.r) or 0,
                                (col and col.g) or 0,
                                (col and col.b) or 0,
                                (col and col.a) or 0.45
                        end,
                        setValue = function(r, g, b, a)
                            local c = TSB()
                            if c then
                                c.bgColor = { r = r, g = g, b = b, a = a }
                                TSBRefresh()
                            end
                        end,
                    },
                },
            }),
            Slider("Border Size", "borderSize", 0, 5, 1, true)
        )

        Row(Toggle("Show Icon", "showIcon", A.NotOff), Toggle("Show Spell Name", "showSpellName", A.NotOff))
        if not CludesUI._prebuilding then
            Cog(row._leftRegion, "Spell Icon Settings", "Spell Icon Settings", {
                {
                    type = "toggle",
                    label = "Icon on Right",
                    tooltip = "Attach the spell icon to the right of the cast bar instead of the left.",
                    get = A.Raw("iconOnRight"),
                    set = A.Put("iconOnRight"),
                },
                {
                    type = "toggle",
                    label = "Show Icon Divider",
                    tooltip = "Draw a 1px divider between the spell icon and the cast bar, matching the border color.",
                    get = A.Raw("showIconDivider"),
                    set = A.Put("showIconDivider"),
                },
            })
            Cog(row._rightRegion, "Spell Name Settings", "Spell Name", TextRows(A, "name", 20, 10))
        end

        Row(
            Toggle("Show Cast Timer", "showTimer", A.NotOff),
            Toggle(
                "Show Spell Target",
                "showTarget",
                A.NotOff,
                "Show who each spell is being cast on, exactly like the nameplate cast bars."
            )
        )
        if not CludesUI._prebuilding then
            Cog(row._leftRegion, "Cast Timer Settings", "Cast Timer", TextRows(A, "timer", 20, 10))
            local targetRows = TextRows(A, "target", 20, 10)
            local getColor, setColor = A.Rgb("targetColor", 1, 1, 1)
            targetRows[4] = {
                type = "toggle",
                label = "Class Colored Names",
                get = A.NotOff("targetClassColor"),
                set = A.Flag("targetClassColor"),
            }
            targetRows[5] = {
                type = "colorpicker",
                label = "Custom Color",
                disabled = A.NotOff("targetClassColor"),
                disabledTooltip = "Class Colored Names to be off",
                get = getColor,
                set = setColor,
            }
            Cog(row._rightRegion, "Spell Target Settings", "Spell Target", targetRows)
        end

        ---------------------------------------------------------------------
        --  Interrupt awareness and visibility
        ---------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "INTERRUPT AND VISIBILITY", posY)
        posY = posY - hgt

        local GO = CludesUI.GlowOptions

        -- Cast Colors (the kick-ready and uninterruptible tints are always
        -- on; a cog holds the opt-in Important Cast tint) | Important Cast
        -- Glow (a dropdown that doubles as the switch, with its cog and glow
        -- swatches, laid out as on the Nameplates page).
        Row(
            Gated({ type = "multiSwatch", text = "Cast Colors", swatches = CastColorSwatches(A, "barColor") }),
            GO.DropdownSpec(
                mtImpGlowDesc,
                "Important Cast Glow",
                "Glow the bar when the enemy casts a spell Blizzard flags as important."
            )
        )
        if not CludesUI._prebuilding then
            Cog(row._leftRegion, "Important Cast Color", "Important Cast Color", {
                {
                    type = "toggle",
                    label = "Important Cast Color",
                    tooltip = "Tint the bar with the Important colour when the enemy casts a spell the game flags as important.",
                    get = A.IsOn("importantEnabled"),
                    set = A.Flag("importantEnabled", true),
                },
            })
            GO.AttachInline(row._rightRegion, mtImpGlowDesc)
        end

        Row(
            Toggle(
                "Fade Out of Interrupt Range",
                "oorEnabled",
                A.IsOn,
                "Fade a bar when the enemy is beyond your active interrupt spell's range. Has no effect for specs without an interrupt."
            ),
            Toggle(
                "Show Raid Target Marker",
                "showRaidMarker",
                A.IsOn,
                "Show the enemy's raid target marker to the left of the spell name."
            )
        )
        if not CludesUI._prebuilding then
            Cog(row._leftRegion, "Range Fade Settings", "Fade Out of Interrupt Range", {
                {
                    type = "slider",
                    label = "Opacity",
                    min = 0,
                    max = 100,
                    step = 5,
                    -- Stored 0..1, shown as a percentage.
                    get = function()
                        return math.floor(A.Or("oorAlpha", 0.45)() * 100 + 0.5)
                    end,
                    set = function(v)
                        A.Put("oorAlpha")(v / 100)
                    end,
                },
            })
            Cog(row._rightRegion, "Raid Marker Settings", "Raid Target Marker", {
                {
                    type = "slider",
                    label = "Marker Size",
                    min = 6,
                    max = 30,
                    step = 1,
                    pixel = true,
                    get = A.Or("raidMarkerSize", 14),
                    set = A.Put("raidMarkerSize"),
                },
            })
        end

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        hostFrame:SetHeight(math.abs(posY - yOffset))
    end

    ---------------------------------------------------------------------------
    --  Target/Focus Bars page
    ---------------------------------------------------------------------------
    local function BuildTFBPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, row, hgt

        CludesUI:SetContentHeader(tfbBuilder)
        hostFrame._showRowDivider = true

        local texValues, texOrder = BuildBarTexDropdown()

        local function Row(left, right)
            row, hgt = W:DualRow(hostFrame, posY, left, right)
            posY = posY - hgt
            return row
        end
        -- Settings both bars share (colours, kick hint, flash).
        local S = Accessors(TFB, TFBRefresh)

        -- One section per bar; the rows are the same, keyed by `which`.
        local function BuildBarSection(which, header, enableLabel)
            local A = Accessors(function()
                return TFBBar(which)
            end, TFBRefresh)
            local On = A.IsOn("enabled")
            local function Off()
                return not On()
            end
            local REQ = enableLabel
            local function Gated(cfg)
                cfg.disabled, cfg.disabledTooltip = Off, REQ
                return cfg
            end
            local function Slider(text, key, lo, hi, def)
                return Gated({
                    type = "slider",
                    text = text,
                    min = lo,
                    max = hi,
                    step = 1,
                    pixel = true,
                    getValue = A.Or(key, def),
                    setValue = A.Put(key),
                })
            end
            local function Toggle(text, key, tooltip, read)
                return Gated({
                    type = "toggle",
                    text = text,
                    tooltip = tooltip,
                    getValue = read or A.NotOff(key),
                    setValue = A.Flag(key),
                })
            end
            local function Cog(region, tip, title, rows)
                CludesUI.BuildInlineCog(region, {
                    tip = tip,
                    title = title,
                    disabled = Off,
                    disabledTooltip = REQ,
                    rows = rows,
                })
            end
            local function SizeRow(label, key, hi, def)
                return {
                    type = "slider",
                    label = label,
                    min = 6,
                    max = hi,
                    step = 1,
                    get = A.Or(key, def),
                    set = A.Put(key),
                }
            end

            local heading
            heading, hgt = W:SectionHeader(hostFrame, header, posY)
            posY = posY - hgt
            CludesUI.BuildSectionUnlockJump(heading, {
                key = (which == "target") and "EMT_TargetCastBar" or "EMT_FocusCastBar",
                disabled = Off,
                disabledTooltip = REQ,
            })

            Row(
                {
                    type = "toggle",
                    text = enableLabel,
                    tooltip = "A standalone cast bar for this unit, placeable anywhere in Layout Mode. Runs alongside the Unit Frames cast bars.",
                    getValue = On,
                    setValue = A.Flag("enabled", true),
                },
                Gated({
                    type = "dropdown",
                    text = "Bar Texture",
                    values = texValues,
                    order = texOrder,
                    getValue = A.Or("texture", "none"),
                    setValue = A.Put("texture"),
                })
            )
            Row(Slider("Width", "width", 80, 600, 260), Slider("Height", "height", 6, 60, 22))

            Row(Toggle("Show Spell Name", "showSpellName"), Toggle("Show Cast Timer", "showTimer"))
            if not CludesUI._prebuilding then
                Cog(
                    row._leftRegion,
                    "Spell Name Settings",
                    "Spell Name",
                    { SizeRow("Text Size", "nameSize", 22, 11) }
                )
                Cog(
                    row._rightRegion,
                    "Cast Timer Settings",
                    "Cast Timer",
                    { SizeRow("Text Size", "timerSize", 22, 11) }
                )
            end

            Row(
                Toggle("Show Icon", "showIcon"),
                Toggle(
                    "Show Spell Target",
                    "showTarget",
                    "Show who the spell is being cast on, exactly like the nameplate cast bars.",
                    -- Per bar; a bar never set follows the older shared switch.
                    function()
                        local mine = A.Raw("showTarget")()
                        if mine == nil then
                            mine = S.NotOff("showTarget")()
                        end
                        return mine
                    end
                )
            )
            if not CludesUI._prebuilding then
                -- The colours belong to both bars; only the text size is per bar.
                local getColor, setColor = S.Rgb("targetColor", 1, 1, 1)
                Cog(row._rightRegion, "Spell Target Settings", "Spell Target", {
                    {
                        type = "toggle",
                        label = "Class Colored Names",
                        get = S.NotOff("targetClassColor"),
                        set = S.Flag("targetClassColor"),
                    },
                    {
                        type = "colorpicker",
                        label = "Custom Color",
                        disabled = S.NotOff("targetClassColor"),
                        disabledTooltip = "Class Colored Names to be off",
                        get = getColor,
                        set = setColor,
                    },
                    SizeRow(
                        (which == "target") and "Text Size (Target)" or "Text Size (Focus)",
                        "targetSize",
                        20,
                        10
                    ),
                })
            end
        end

        BuildBarSection("target", "TARGET CAST BAR", "Enable Target Cast Bar")
        BuildBarSection("focus", "FOCUS CAST BAR", "Enable Focus Cast Bar")

        -- CAST COLORS AND EFFECTS (shared by both bars)
        _, hgt = W:SectionHeader(hostFrame, "CAST COLORS AND EFFECTS", posY)
        posY = posY - hgt

        local function SharedOff()
            local t, f = TFBBar("target"), TFBBar("focus")
            return not ((t and t.enabled == true) or (f and f.enabled == true))
        end
        local SHARED_REQ = "a Target or Focus Cast Bar"

        Row({
            type = "multiSwatch",
            text = "Cast Color",
            disabled = SharedOff,
            disabledTooltip = SHARED_REQ,
            swatches = CastColorSwatches(S, "castColor"),
        }, {
            type = "dropdown",
            text = "Kick Ready Mid-Cast Hint",
            disabled = SharedOff,
            disabledTooltip = SHARED_REQ,
            tooltip = 'Shows where your interrupt will be ready during a cast. "Tick" marks the exact spot on the cast bar; "Tick + Bar" also colours the window during which your interrupt will be available.',
            values = { none = "None", tick = "Tick", tickbar = "Tick + Bar" },
            order = { "none", "tick", "tickbar" },
            -- Two stored switches read as one three-way choice.
            getValue = function()
                local t = TFB()
                if t and t.kickTickEnabled == false then
                    return "none"
                end
                return (t and t.midCastEnabled == true) and "tickbar" or "tick"
            end,
            setValue = function(v)
                local t = TFB()
                if t then
                    t.kickTickEnabled = v ~= "none"
                    t.midCastEnabled = v ~= "none" and v ~= "tick"
                    TFBRefresh()
                end
            end,
        })
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineCog(row._leftRegion, {
                tip = "Cast Color Settings",
                title = "Cast Color",
                rows = {
                    {
                        type = "toggle",
                        label = "Show Shield Icon",
                        tooltip = "Show a shield icon on the cast bar when the cast cannot be interrupted.",
                        get = S.NotOff("showShield"),
                        set = S.Flag("showShield"),
                    },
                    {
                        type = "toggle",
                        label = "Show Spark",
                        tooltip = "Show the bright spark at the leading edge of the cast bar fill.",
                        get = S.NotOff("showSpark"),
                        set = S.Flag("showSpark"),
                    },
                    {
                        type = "toggle",
                        label = "Important Cast Color",
                        tooltip = "Tint the cast bar with the Important colour when the unit casts a spell the game flags as important. Your interrupt being on cooldown still takes priority.",
                        get = S.IsOn("importantEnabled"),
                        set = S.Flag("importantEnabled", true),
                    },
                },
            })
            local getMid, setMid = S.Rgb("midCastColor", 0.318, 0.820, 0.357)
            local getTick, setTick = S.Rgb("kickTickColor", 1, 1, 1)
            CludesUI.BuildInlineCog(row._rightRegion, {
                tip = "Kick Hint Settings",
                title = "Kick Ready Mid-Cast Hint",
                rows = {
                    {
                        type = "colorpicker",
                        label = "Mid-Cast Bar Color",
                        disabled = S.NotOn("midCastEnabled"),
                        disabledTooltip = "Tick + Bar",
                        get = getMid,
                        set = setMid,
                    },
                    { type = "colorpicker", label = "Tick Color", get = getTick, set = setTick },
                },
            })
        end

        Row({
            type = "toggle",
            text = "Show Interrupted Flash Effect",
            disabled = SharedOff,
            disabledTooltip = SHARED_REQ,
            tooltip = 'Flash the cast bar and show "Interrupted" for a moment when the cast is interrupted.',
            getValue = S.NotOff("interruptedFlash"),
            setValue = S.Flag("interruptedFlash"),
        }, { type = "label", text = "" })
        if not CludesUI._prebuilding then
            local getFlash, setFlash = S.Rgb("interruptedColor", 0.8, 0, 0)
            CludesUI.BuildInlineCog(row._leftRegion, {
                tip = "Interrupted Flash Settings",
                title = "Interrupted Flash",
                rows = { { type = "colorpicker", label = "Flash Color", get = getFlash, set = setFlash } },
            })
        end

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        hostFrame:SetHeight(math.abs(posY - yOffset))
    end

    -----------------------------------------------------------------------
    --  Run Summary page
    -----------------------------------------------------------------------
    local function RSCfg()
        local p = DB()
        return p and p.runSummary
    end

    -- A Run Summary setting, fallback while it was never stored.
    local function RSGet(key, fallback)
        local c = RSCfg()
        local v = c and c[key]
        if v ~= nil then
            return v
        end
        return fallback
    end

    -- Stores a Run Summary setting, then re-applies it and repaints an open
    -- panel (columns and scale show at once, not only on the next opening).
    local function RSSet(key, val)
        local c = RSCfg()
        if c then
            c[key] = val
        end
        for _, step in ipairs({ "RS_Apply", "RS_Refresh" }) do
            if mod[step] then
                mod[step]()
            end
        end
    end

    local function RSOn()
        local c = RSCfg()
        return c ~= nil and c.enabled == true
    end
    local function RSOff()
        return not RSOn()
    end

    local function BuildRSPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt

        if CludesUI.ClearContentHeader then
            CludesUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        local REQ = "Enable Run Summary"
        local function Row(left, right)
            _, hgt = W:DualRow(hostFrame, posY, left, right)
            posY = posY - hgt
        end
        local function Section(title)
            _, hgt = W:SectionHeader(hostFrame, title, posY)
            posY = posY - hgt
        end
        -- A switch that is on until turned off.
        local function Switch(text, key, tooltip)
            return {
                type = "toggle",
                text = text,
                tooltip = tooltip,
                disabled = RSOff,
                disabledTooltip = REQ,
                getValue = function()
                    return RSGet(key, true) == true
                end,
                setValue = function(v)
                    RSSet(key, v and true or false)
                end,
            }
        end
        local function Slider(text, key, lo, hi, step, def, tooltip)
            return {
                type = "slider",
                text = text,
                tooltip = tooltip,
                min = lo,
                max = hi,
                step = step,
                disabled = RSOff,
                disabledTooltip = REQ,
                getValue = function()
                    return RSGet(key, def)
                end,
                setValue = function(v)
                    RSSet(key, v)
                end,
            }
        end

        -- Two 312x38 buttons across the top, centred with a 40px gap between.
        do
            local PPn = CludesUI.PanelPP
            local BTN_W, BTN_H, GAP = 312, 38, 40
            local ROW_H = BTN_H + 20
            local strip = CreateFrame("Frame", nil, hostFrame)
            PPn.Size(strip, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, ROW_H)
            PPn.Point(strip, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, posY)
            local function Action(label, point, dx, onClick)
                local btn = CreateFrame("Button", nil, strip)
                PPn.Size(btn, BTN_W, BTN_H)
                PPn.Point(btn, point, strip, "CENTER", dx, 0)
                btn:SetFrameLevel(strip:GetFrameLevel() + 1)
                CludesUI.MakeStyledButton(btn, label, 14, CludesUI.WB_COLOURS, onClick)
            end
            Action("Show Preview", "RIGHT", -(GAP / 2), function()
                if mod.RS_ShowPreview then
                    mod.RS_ShowPreview()
                end
            end)
            Action("Clear Run History", "LEFT", GAP / 2, function()
                CludesUI:ShowConfirmPopup({
                    title = "Clear Run History",
                    message = "Delete every recorded Mythic+ run for this character?",
                    confirmText = "Delete",
                    cancelText = "Cancel",
                    onConfirm = function()
                        if mod.RS_ClearHistory then
                            mod.RS_ClearHistory()
                        end
                    end,
                })
            end)
            posY = posY - ROW_H
        end

        Section("RUN SUMMARY")
        Row(
            {
                type = "toggle",
                text = "Enable Run Summary",
                tooltip = "Records every finished Mythic+ key and shows an overview of the group when the run ends. Nothing is registered or created while this is off.",
                getValue = RSOn,
                setValue = function(v)
                    RSSet("enabled", v and true or false)
                    CludesUI:RefreshPage()
                end,
            },
            Switch(
                "Show After Looting",
                "showAfterLoot",
                "Open the overview once the end of run chest has been looted. With this off it opens as soon as the key ends. /ov reopens it at any time."
            )
        )
        Row(
            Slider("History Size", "historySize", 5, 50, 1, 20),
            Slider("Panel Scale", "scale", 0.5, 2, 0.05, 1)
        )
        Row(
            Slider(
                "Text Size",
                "textSize",
                10,
                20,
                1,
                14,
                "Size of the player rows. The title and column headers keep their own size."
            ),
            { type = "label", text = "" }
        )

        Section("COLUMNS")
        Row(
            Switch("Show Spec Icons", "showSpecIcons"),
            Switch(
                "Item Level",
                "colItemLevel",
                "Shown in grey next to each name. Item levels are read by inspecting party members during the run, so a member who stayed out of range shows none."
            )
        )
        Row(
            Switch(
                "M+ Score",
                "colScore",
                "Current season score plus the gain from this run. Your own gain is the exact value the server reports; for party members it is their score before the key subtracted from their score after it."
            ),
            Switch(
                "Loot",
                "colLoot",
                "What each player looted. Your own chest reward always appears; other players' items only when the server announces the loot to the group, which it does not always do for the end of run chest."
            )
        )
        Row(
            Switch(
                "DPS",
                "colDps",
                "Read from Blizzard's own damage meter. With that meter switched off this column, Damage Taken and Interrupts stay empty."
            ),
            Switch("Damage Taken", "colDamageTaken")
        )
        Row(Switch("Interrupts", "colInterrupts"), Switch("Deaths", "colDeaths"))

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        hostFrame:SetHeight(math.abs(posY - yOffset))
    end

    -- RegisterModule
    CludesUI:RegisterModule("CludesUIMythicTimer", {
        title = "Mythic+ Tools",
        description = "Mythic+ timer, Kick Tracker, cast bars and target/focus bars.",
        pages = { PAGE_DISPLAY, PAGE_KT, PAGE_TSB, PAGE_TFB, PAGE_RS },
        tabLabels = { [PAGE_TSB] = "Cast Bars" },
        buildPage = function(pageName, hostFrame, yOffset)
            if pageName == PAGE_TSB then
                return BuildTSBPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_TFB then
                return BuildTFBPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_RS then
                return BuildRSPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_KT then
                -- CUI_MythicTimer_KickTracker_Options.lua (loads before this file)
                return mod._KT_BuildPage(pageName, hostFrame, yOffset)
            end
            return BuildPage(pageName, hostFrame, yOffset)
        end,
        -- The header previews of the Kick Tracker and cast bar pages (the
        -- same answer buildPage gave, so a kept page keeps its header).
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_TSB then
                return tsbBuilder
            elseif pageName == PAGE_TFB then
                return tfbBuilder
            elseif pageName == PAGE_KT then
                return mod._KT_HeaderBuilder
            end
            return nil
        end,
        -- A kept page shown again: its preview paints again (the Fonts and
        -- Textures pages and a profile switch write its keys from elsewhere).
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_TSB then
                PvUpdate(tsbPv, false)
            elseif pageName == PAGE_TFB then
                PvUpdate(tfbPv, false)
            elseif pageName == PAGE_KT and mod._KT_RestorePreview then
                mod._KT_RestorePreview()
            end
        end,
        onReset = function()
            -- Lite DB stores data at CludesUIDB.profiles[X].addons.CludesUIMythicTimer
            if CludesUIDB and CludesUIDB.profiles then
                local profile = CludesUIDB.activeProfile or "Default"
                local p = CludesUIDB.profiles[profile]
                if p and p.addons and p.addons.CludesUIMythicTimer then
                    wipe(p.addons.CludesUIMythicTimer)
                end
            end
        end,
    })
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
