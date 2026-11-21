if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  ActionBars_Options\AnimationsPage_Options.lua
--  Action Bars options: the Bar Animations page (Bar Interactions, Custom
--  Proc Glow). CUI_ActionBars_Options.lua calls the init function once at
--  load, at the block's original place, so the Custom Proc Glow site
--  registers in the same order as before; it returns the page builder.
-------------------------------------------------------------------------------
local mod = CUI._ModuleNS["CludesUIActionBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): a frame
-- made here on a pool host (a kept page and every frame it hands out) is reset
-- and dressed again by the next build instead of made anew; on any other
-- parent this is CreateFrame. The preview icons are made again by every build
-- (never held back for a later one), so the pool hands each build the same ones.
local CreateFrame = CUI._Pool.CreateFrame

local function InitAnimationsPage(Pix, ABAR, PAGE_ANIMATIONS)
    local SECTION_BAR_INTERACTIONS = "BAR INTERACTIONS"
    local SECTION_PROC_GLOW = "CUSTOM PROC GLOW"

    -- "Light" here is a strength, not the Holy school or Blessing of Light: it
    -- has a key of its own, and English (or a locale without it) shows "Light".
    local lightLabel = CUI.L("Light (Strength)")
    if lightLabel == "Light (Strength)" then lightLabel = "Light" end
    local interactionTypeValues = {
        [1] = lightLabel,
        [2] = "Medium",
        [3] = "Strong",
        [4] = "Solid Color",
        [5] = "Border",
        [6] = "None",
    }
    local interactionTypeOrder = { 1, 2, 3, 4, 5, 6 }
    local pushedTypeValues, pushedTypeOrder = interactionTypeValues, interactionTypeOrder
    local highlightTypeValues, highlightTypeOrder = interactionTypeValues, interactionTypeOrder
    -- Custom Proc Glow: shared glow controls over the proc glow keys. Shape Glow
    -- is internal-only (forced by custom button shapes at render time).
    local function ProcP() return ABAR.db.profile end
    local _procGlowPreview
    local UpdateProcGlowPreview
    local GO = CUI.GlowOptions
    -- Custom button shapes force Shape Glow at render time (none/cropped do not).
    local function AnyBarHasCustomShape()
        local barList = ABAR.db.profile.bars
        if not barList then return false end
        for _, s in pairs(barList) do
            if s.buttonShape and s.buttonShape ~= "none" and s.buttonShape ~= "cropped" then return true end
        end
        return false
    end
    local procGlowDesc = {
        host = "icon",
        excludes = { [4] = true },
        disabled = function() return CUI.BlizzStyle.Get("actionbars") end,
        disabledTooltip = function()
            return CUI.DisabledTooltip(CUI.BlizzStyle.Label("actionbars"), "disabled")
        end,
        rawTooltip = true,
        -- Custom shapes lock only the style: the forced Shape Glow still takes
        -- the color, and bars without a custom shape keep the saved style.
        styleDisabled = AnyBarHasCustomShape,
        styleDisabledTooltip = "Custom shapes always use Shape Glow -- change your bar shape to None or Cropped to pick a different glow",
        caps = { mode = true, params = true, bg = true },
        defaultColor = { r = 1, g = 0.776, b = 0.376 },
        isOff = function()
            local p = ProcP()
            return p.procGlowEnabled == false or p.procGlowType == 0
        end,
        onChange = function()
            ABAR:RefreshProcGlows()
            UpdateProcGlowPreview(_procGlowPreview)
        end,
        get = function(f)
            local p = ProcP()
            if f == "style" then
                return p.procGlowType or 1
            elseif f == "mode" then
                -- The class flag alone decides Class, so a spec override that
                -- holds only the flag keeps applying; the mode key tells Default
                -- from Custom. Both are read on every call (override tracing).
                local m = p.procGlowColorMode
                if p.procGlowUseClassColor then return "class" end
                return (m == "default") and "default" or "custom"
            elseif f == "color" then
                local color = p.procGlowColor or { r = 1, g = 0.776, b = 0.376 }
                return color.r, color.g, color.b
            end
            return CUI.GlowOptions.FlatGet(p, "procGlow", f)
        end,
        set = function(f, a, b2, c2)
            local p = ProcP()
            if f == "style" then
                p.procGlowType = a
                p.procGlowEnabled = (a ~= 0)
            elseif f == "mode" then
                -- The class flag stays in step (Bar Interactions' unified class toggle writes it too).
                p.procGlowColorMode = a
                p.procGlowUseClassColor = (a == "class")
            else
                CUI.GlowOptions.FlatSet(p, "procGlow", f, a, b2, c2)
            end
        end,
        confirm = function(val, commit)
            local p = ProcP()
            if ((p.procGlowType == 0) or (p.procGlowEnabled == false)) and val ~= 0 then
                CUI:ShowConfirmPopup({
                    title = "Custom Proc Glow Settings",
                    message = "Custom proc glow may cause a slight loss in performance efficiency. Do you want to enable it?",
                    confirmText = "Enable",
                    cancelText = "Cancel",
                    onConfirm = commit,
                    onCancel = function() CUI:RefreshPage() end,
                })
                return
            end
            commit()
        end,
    }
    GO.RegisterSite({
        id = "ab_proc",
        label = "Custom Proc Glow",
        group = "module",
        module = "CludesUIActionBars",
        page = PAGE_ANIMATIONS,
        section = "CUSTOM PROC GLOW",
        highlight = "Custom Proc Glow",
        desc = procGlowDesc,
        -- Blizzard Style bars draw Blizzard's own proc glow.
        blocked = function() return CUI.BlizzStyle.Get("actionbars") end,
    })

    -----------------------------------------------------------------------
    --  Preview icon helper for animation dropdown rows: small square icon with a 1px
    --  border, parented to a DualRow's left region, centered between label and dropdown.
    -----------------------------------------------------------------------
    local PREVIEW_ICON_SIZE = 30

    local function CreatePreviewIcon(parentRegion)
        local frame = CreateFrame("Frame", nil, parentRegion)
        frame:EnableMouse(false)
        Pix.Size(frame, PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
        -- Center vertically, positioned roughly between label and dropdown
        Pix.Point(frame, "RIGHT", parentRegion, "RIGHT", -200, 0)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetColorTexture(0.15, 0.15, 0.15, 1)
        frame._icon = icon

        Pix.CreateBorder(frame, 0, 0, 0, 1, 1, "OVERLAY", 7)

        return frame
    end

    -- Unified interaction preview (pushed / highlight)
    local INTERACTION_DEFAULTS = {
        pushed = { typeDefault = 3, texFallback = 2, solidColor = { r = 1, g = 0.792, b = 0.427, a = 1 } },
        highlight = {
            typeDefault = 2,
            texFallback = 1,
            solidColor = { r = 0.973, g = 0.839, b = 0.604, a = 1 },
        },
    }
    local function UpdateInteractionPreview(frame, prefixText)
        if not frame then return end
        local profile = ABAR.db.profile
        local defs = INTERACTION_DEFAULTS[prefixText]
        local iType = profile[prefixText .. "TextureType"] or defs.typeDefault
        if not frame._overlay then
            local shade = frame:CreateTexture(nil, "OVERLAY", nil, 1)
            shade:SetAllPoints()
            frame._overlay = shade
        end
        if not frame._borderOv then
            frame._borderOv = {}
            for idx = 1, 4 do
                local tex = frame:CreateTexture(nil, "OVERLAY", nil, 2)
                tex:SetColorTexture(1, 1, 1, 1)
                frame._borderOv[idx] = tex
            end
        end
        local shade = frame._overlay
        local bo = frame._borderOv
        if iType == 6 then
            shade:Hide()
            for idx = 1, 4 do
                bo[idx]:Hide()
            end
        elseif iType == 4 then
            shade:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            shade:SetTexCoord(0, 1, 0, 1)
            shade:SetDesaturated(false)
            local cr, cg, checkBtn, ca
            if profile[prefixText .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local classColor = RAID_CLASS_COLORS[class]
                cr, cg, checkBtn =
                    classColor and classColor.r or 1,
                    classColor and classColor.g or 1,
                    classColor and classColor.b or 1
                ca = 1
            else
                local color = profile[prefixText .. "CustomColor"] or defs.solidColor
                cr, cg, checkBtn, ca = color.r, color.g, color.b, color.a
            end
            shade:SetVertexColor(cr, cg, checkBtn, 0.3)
            shade:Show()
            for idx = 1, 4 do
                bo[idx]:Hide()
            end
        elseif iType == 5 then
            shade:Hide()
            local bsz = profile[prefixText .. "BorderSize"] or 4
            local cr, cg, checkBtn, ca
            if profile[prefixText .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local classColor = RAID_CLASS_COLORS[class]
                cr, cg, checkBtn =
                    classColor and classColor.r or 1,
                    classColor and classColor.g or 1,
                    classColor and classColor.b or 1
                ca = 1
            else
                local color = profile[prefixText .. "CustomColor"] or { r = 1, g = 0.792, b = 0.427, a = 1 }
                cr, cg, checkBtn, ca = color.r, color.g, color.b, color.a
            end
            for idx = 1, 4 do
                bo[idx]:SetVertexColor(cr, cg, checkBtn, ca)
            end
            bo[1]:ClearAllPoints()
            bo[1]:SetPoint("TOPLEFT", frame)
            bo[1]:SetPoint("TOPRIGHT", frame)
            Pix.Height(bo[1], bsz)
            bo[1]:Show()
            bo[2]:ClearAllPoints()
            bo[2]:SetPoint("BOTTOMLEFT", frame)
            bo[2]:SetPoint("BOTTOMRIGHT", frame)
            Pix.Height(bo[2], bsz)
            bo[2]:Show()
            bo[3]:ClearAllPoints()
            bo[3]:SetPoint("TOPLEFT", bo[1], "BOTTOMLEFT")
            bo[3]:SetPoint("BOTTOMLEFT", bo[2], "TOPLEFT")
            Pix.Width(bo[3], bsz)
            bo[3]:Show()
            bo[4]:ClearAllPoints()
            bo[4]:SetPoint("TOPRIGHT", bo[1], "BOTTOMRIGHT")
            bo[4]:SetPoint("BOTTOMRIGHT", bo[2], "TOPRIGHT")
            Pix.Width(bo[4], bsz)
            bo[4]:Show()
        else
            local texIdx = iType
            if texIdx < 1 or texIdx > 3 then texIdx = defs.texFallback end
            shade:SetTexture(mod.HIGHLIGHT_TEXTURES[texIdx])
            shade:SetTexCoord(0, 1, 0, 1)
            if profile[prefixText .. "UseClassColor"] then
                local _, class = UnitClass("player")
                local classColor = RAID_CLASS_COLORS[class]
                shade:SetDesaturated(true)
                shade:SetVertexColor(
                    classColor and classColor.r or 1,
                    classColor and classColor.g or 1,
                    classColor and classColor.b or 1,
                    1
                )
            else
                local color = profile[prefixText .. "CustomColor"] or { r = 1, g = 0.792, b = 0.427, a = 1 }
                shade:SetDesaturated(true)
                shade:SetVertexColor(color.r, color.g, color.b, color.a)
            end
            shade:Show()
            for idx = 1, 4 do
                bo[idx]:Hide()
            end
        end
    end
    local function PaintPushedPreview(f) UpdateInteractionPreview(f, "pushed") end
    local function PaintHighlightPreview(f) UpdateInteractionPreview(f, "highlight") end

    -- Proc glow preview: supports FlipBook + procedural glow engines
    local function GetNthActionButtonIcon(num)
        -- Find the Nth action button with an assigned spell across bars 1-8
        num = num or 1
        local BAR_CONFIG = {
            { prefix = "ActionButton", count = 12 },
            { prefix = "MultiBarBottomLeftButton", count = 12 },
            { prefix = "MultiBarBottomRightButton", count = 12 },
            { prefix = "MultiBarRightButton", count = 12 },
            { prefix = "MultiBarLeftButton", count = 12 },
            { prefix = "MultiBar5Button", count = 12 },
            { prefix = "MultiBar6Button", count = 12 },
            { prefix = "MultiBar7Button", count = 12 },
        }
        local found = 0
        for _, bar in ipairs(BAR_CONFIG) do
            for idx = 1, bar.count do
                local button = _G[bar.prefix .. idx]
                if button and button.icon then
                    local texture = button.icon:GetTexture()
                    if texture and texture ~= 0 and texture ~= "" and texture ~= 136235 then
                        found = found + 1
                        if found >= num then return texture end
                    end
                end
            end
        end
        return 136197 -- fallback: generic spell icon
    end

    UpdateProcGlowPreview = function(frame)
        if not frame then return end
        local G = CUI.Glows
        -- The glow draws on its own child frame: on f itself it shares the
        -- border's OVERLAY sublevel and a 1px Pixel Glow can vanish under it.
        local shade = frame._glowOv
        if not shade then
            shade = CreateFrame("Frame", nil, frame)
            shade:SetAllPoints(frame)
            shade:EnableMouse(false)
            frame._glowOv = shade
        end
        shade:SetFrameLevel(frame:GetFrameLevel() + 2)
        G.StopAllGlows(shade)
        frame:Show()
        -- Hidden (options closed, page left): stays stopped; OnShow restarts it.
        if not frame:IsVisible() then return end
        -- If disabled (None selected), keep the icon visible but grayed out
        if not GO.IsCustomGlow(procGlowDesc) then
            frame:SetAlpha(0.15)
            return
        end
        frame:SetAlpha(1)
        G.StartSpecGlow(
            shade,
            GO.Spec(procGlowDesc),
            PREVIEW_ICON_SIZE,
            PREVIEW_ICON_SIZE,
            "icon",
            G.PANEL_EXTRA
        )
    end

    -- Assisted Highlight preview. A custom glow runs on the shared glow engine,
    -- as on the live buttons; the ring and overlay styles draw a plain stand-in
    -- of their own, so the preview never touches a live button's glow.
    local function PaintAssistGlowPreview(frame)
        if not frame then return end
        local p = ABAR.db and ABAR.db.profile or {}
        local customType = p.assistGlowType or 0
        local style = (p.assistGlowStyle == 0 and 1) or p.assistGlowStyle or 1
        local G = CUI.Glows

        if not frame._assistOverlay then
            local shade = frame:CreateTexture(nil, "OVERLAY", nil, 1)
            shade:SetAllPoints()
            frame._assistOverlay = shade
        end
        if not frame._assistRing then
            local ring = {}
            for idx = 1, 4 do
                local tex = frame:CreateTexture(nil, "OVERLAY", nil, 2)
                tex:SetColorTexture(0.15, 0.5, 1, 1)
                ring[idx] = tex
            end
            frame._assistRing = ring
        end
        if not frame._assistGlowOv then
            local host = CreateFrame("Frame", nil, frame)
            host:SetAllPoints(frame)
            host:EnableMouse(false)
            frame._assistGlowOv = host
        end

        local shade = frame._assistOverlay
        local ring = frame._assistRing
        local glowHost = frame._assistGlowOv
        glowHost:SetFrameLevel(frame:GetFrameLevel() + 2)
        shade:Hide()
        for idx = 1, 4 do
            ring[idx]:Hide()
        end

        local entries = mod.LOOP_GLOW_TYPES or {}
        if customType > 0 and entries[customType] then
            local cr, cg, checkBtn = mod._AssistCustomGlowColor()
            frame:SetAlpha(1)
            -- Every widget refresh lands here: the engine glow restarts only
            -- when the style or colour moved, or after a hide stopped it.
            if
                frame:IsVisible()
                and not (
                    frame._assistPvType == customType
                    and frame._assistPvR == cr
                    and frame._assistPvG == cg
                    and frame._assistPvB == checkBtn
                )
            then
                G.StopAllGlows(glowHost)
                G.StartSpecGlow(
                    glowHost,
                    { style = customType, r = cr, g = cg, b = checkBtn },
                    PREVIEW_ICON_SIZE,
                    PREVIEW_ICON_SIZE,
                    "icon",
                    G.PANEL_EXTRA
                )
                frame._assistPvType, frame._assistPvR, frame._assistPvG, frame._assistPvB =
                    customType, cr, cg, checkBtn
            end
            return
        end

        G.StopAllGlows(glowHost)
        frame._assistPvType = nil
        frame:SetAlpha(1)

        -- The ring and overlay styles: a plain stand-in of each.
        if style == 1 or style == 3 then
            ring[1]:ClearAllPoints()
            ring[1]:SetPoint("TOPLEFT", frame)
            ring[1]:SetPoint("TOPRIGHT", frame)
            ring[1]:SetHeight(2)
            ring[2]:ClearAllPoints()
            ring[2]:SetPoint("BOTTOMLEFT", frame)
            ring[2]:SetPoint("BOTTOMRIGHT", frame)
            ring[2]:SetHeight(2)
            ring[3]:ClearAllPoints()
            ring[3]:SetPoint("TOPLEFT", ring[1], "BOTTOMLEFT")
            ring[3]:SetPoint("BOTTOMLEFT", ring[2], "TOPLEFT")
            ring[3]:SetWidth(2)
            ring[4]:ClearAllPoints()
            ring[4]:SetPoint("TOPRIGHT", ring[1], "BOTTOMRIGHT")
            ring[4]:SetPoint("BOTTOMRIGHT", ring[2], "TOPRIGHT")
            ring[4]:SetWidth(2)
            for idx = 1, 4 do
                ring[idx]:Show()
            end
        end

        if style == 2 or style == 3 then
            local color = p.assistGlowOverlayColor or { r = 0.15, g = 0.5, b = 1 }
            local a = (p.assistGlowOverlayAlpha or 30) / 100
            shade:SetColorTexture(color.r or 0.15, color.g or 0.5, color.b or 1, a)
            shade:Show()
        end
    end

    -- Persistent preview icon frames (survive page cache restores)
    local _pushedPreview, _highlightPreview, _assistGlowPreview

    local function BuildAnimationsPage(pageName, hostFrame, yOffset)
        local W = CUI.Widgets
        local cursorY = yOffset
        local _, height, row
        local profile = ABAR.db.profile

        -- No content header for animations page (global settings, no bar selector)
        CUI:ClearContentHeader()

        hostFrame._showRowDivider = true

        -------------------------------------------------------------------
        --  BAR INTERACTIONS
        -------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, SECTION_BAR_INTERACTIONS, cursorY)
        cursorY = cursorY - height

        local INTERACTIONS_TIP =
            "Bar Interactions are the light effects that happen when you hover/press a spell, your cooldown swipe line, aura active border glow, etc"

        -- Helper: apply unified color to ALL interaction systems
        local function ApplyAllInteractionColors()
            ABAR:ApplyPushedTextures()
            ABAR:ApplyHighlightTextures()
            ABAR:ApplyCooldownEdge()
            ABAR:ApplyMiscTextures()
            ABAR:RefreshProcGlows()
            PaintPushedPreview(_pushedPreview)
            PaintHighlightPreview(_highlightPreview)
            UpdateProcGlowPreview(_procGlowPreview)
        end

        local function SetUnifiedColor(red, green, blue, a)
            profile.pushedCustomColor = { r = red, g = green, b = blue, a = a }
            profile.highlightCustomColor = { r = red, g = green, b = blue, a = a }
            profile.cooldownEdgeColor = { r = red, g = green, b = blue, a = a }
            profile.procGlowColor = { r = red, g = green, b = blue }
            -- A Default-mode proc glow would ignore the pick; it takes the unified color as before.
            if profile.procGlowColorMode == "default" then profile.procGlowColorMode = "custom" end
            ApplyAllInteractionColors()
        end

        local function SetUnifiedClassColor(val)
            profile.pushedUseClassColor = val
            profile.highlightUseClassColor = val
            profile.cooldownEdgeUseClassColor = val
            profile.procGlowUseClassColor = val
            -- Keep the mode key in step with the flag.
            if profile.procGlowColorMode == "class" or (val and profile.procGlowColorMode) then
                profile.procGlowColorMode = val and "class" or "custom"
            end
            ApplyAllInteractionColors()
            CUI:RefreshPage()
        end

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "colorpicker",
            text = "Bar Interactions Color",
            tooltip = INTERACTIONS_TIP,
            disabled = function() return CUI.BlizzStyle.Get("actionbars") or profile.pushedUseClassColor end,
            disabledTooltip = function()
                if CUI.BlizzStyle.Get("actionbars") then
                    return CUI.DisabledTooltip(CUI.BlizzStyle.Label("actionbars"), "disabled")
                end
                return "This option requires Class Colors to be disabled"
            end,
            rawTooltip = true,
            getValue = function()
                local color = profile.pushedCustomColor
                if not color then return 0.973, 0.839, 0.604, 1 end
                return color.r, color.g, color.b, color.a
            end,
            setValue = function(red, green, blue, a) SetUnifiedColor(red, green, blue, a) end,
            hasAlpha = true,
        }, {
            type = "toggle",
            text = "Class Colored Bar Interactions",
            tooltip = INTERACTIONS_TIP,
            disabled = function() return CUI.BlizzStyle.Get("actionbars") end,
            disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            getValue = function() return profile.pushedUseClassColor end,
            setValue = function(val) SetUnifiedClassColor(val) end,
        })
        cursorY = cursorY - height

        row, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Pushed Type",
            tooltip = "The overlay that appears on the icon when you press and hold a spell button",
            disabled = function() return CUI.BlizzStyle.Get("actionbars") end,
            disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            values = pushedTypeValues,
            order = pushedTypeOrder,
            getValue = function() return profile.pushedTextureType or 2 end,
            setValue = function(val)
                profile.pushedTextureType = val
                ABAR:ApplyPushedTextures()
                PaintPushedPreview(_pushedPreview)
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Highlight Type",
            tooltip = "The overlay that appears on the icon when you hover your mouse over a spell button",
            disabled = function() return CUI.BlizzStyle.Get("actionbars") end,
            disabledTooltip = CUI.BlizzStyle.Label("actionbars"),
            requireState = "disabled",
            values = highlightTypeValues,
            order = highlightTypeOrder,
            getValue = function() return profile.highlightTextureType or 2 end,
            setValue = function(val)
                profile.highlightTextureType = val
                ABAR:ApplyHighlightTextures()
                PaintHighlightPreview(_highlightPreview)
                CUI:RefreshPage()
            end,
        })
        -- Preview chrome: the search pre-build's absorber row cannot host frames.
        if not CUI._prebuilding then
            local leftRegion = row._leftRegion
            _pushedPreview = CreatePreviewIcon(leftRegion)
            if _pushedPreview._icon then
                _pushedPreview._icon:SetTexture(GetNthActionButtonIcon(1))
                _pushedPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            PaintPushedPreview(_pushedPreview)
            CUI.RegisterWidgetRefresh(function() PaintPushedPreview(_pushedPreview) end)

            CUI.BuildInlineCog(leftRegion, {
                title = "Pushed Border Settings",
                anchorTo = _pushedPreview,
                chain = false,
                captureRegion = leftRegion,
                disabled = function() return (profile.pushedTextureType or 2) ~= 5 end,
                disabledTooltip = "Border Pushed Type",
                rows = {
                    {
                        type = "slider",
                        label = "Border Size",
                        min = 1,
                        max = 10,
                        step = 1,
                        get = function() return profile.pushedBorderSize or 4 end,
                        set = function(val)
                            profile.pushedBorderSize = val
                            ABAR:ApplyPushedTextures()
                            PaintPushedPreview(_pushedPreview)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Match Bar Border",
                        tooltip = "On bars with a textured border style, a press lights up the button's own border instead of drawing lines.",
                        get = function() return profile.pushedBorderMatchBar or false end,
                        set = function(val)
                            profile.pushedBorderMatchBar = val
                            ABAR:ApplyPushedTextures()
                        end,
                    },
                },
            })

            local rightRegion = row._rightRegion
            _highlightPreview = CreatePreviewIcon(rightRegion)
            if _highlightPreview._icon then
                _highlightPreview._icon:SetTexture(GetNthActionButtonIcon(2))
                _highlightPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            PaintHighlightPreview(_highlightPreview)
            CUI.RegisterWidgetRefresh(function() PaintHighlightPreview(_highlightPreview) end)

            CUI.BuildInlineCog(rightRegion, {
                title = "Highlight Border Settings",
                anchorTo = _highlightPreview,
                chain = false,
                captureRegion = rightRegion,
                disabled = function() return (profile.highlightTextureType or 2) ~= 5 end,
                disabledTooltip = "Border Highlight Type",
                rows = {
                    {
                        type = "slider",
                        label = "Border Size",
                        min = 1,
                        max = 10,
                        step = 1,
                        get = function() return profile.highlightBorderSize or 4 end,
                        set = function(val)
                            profile.highlightBorderSize = val
                            ABAR:ApplyHighlightTextures()
                            PaintHighlightPreview(_highlightPreview)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Match Bar Border",
                        tooltip = "On bars with a textured border style, hovering lights up the button's own border instead of drawing lines.",
                        get = function() return profile.highlightBorderMatchBar or false end,
                        set = function(val)
                            profile.highlightBorderMatchBar = val
                            ABAR:ApplyHighlightTextures()
                        end,
                    },
                },
            })
        end
        cursorY = cursorY - height

        local function castAnimForced()
            local barList = ABAR.db.profile.bars
            if not barList then return false end
            for _, s in pairs(barList) do
                if s.buttonShape and s.buttonShape ~= "none" then return true end
            end
            return false
        end
        local castRow
        castRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Hide Casting Animations",
            tooltip = "This is the full overlay that swipes from right to left on the icon during its cast duration",
            disabled = castAnimForced,
            disabledTooltip = "This option requires a non-custom shaped action bar",
            rawTooltip = true,
            getValue = function() return profile.hideCastingAnimations or castAnimForced() end,
            setValue = function(val)
                profile.hideCastingAnimations = val
                -- ActionBarActionEventsFrame dies at file-load; ApplySettings owns casting animation visibility.
            end,
        }, {
            type = "toggle",
            text = "Show Highlight on Spell Cast",
            tooltip = "The highlight overlay that appears on a spell button while it is the active/current action. Disable to hide it.",
            rawTooltip = true,
            getValue = function() return profile.showCastHighlight ~= false end,
            setValue = function(val)
                profile.showCastHighlight = val
                ABAR:ApplyCheckedTextures()
                -- The Spell Cast Highlight cog dims with this toggle.
                CUI:RefreshPage()
            end,
        })
        -- Spell Cast Highlight cog: the checked highlight as the button's own
        -- border on bars with a textured style (BuildInlineCog returns nothing
        -- during the search pre-build).
        CUI.BuildInlineCog(castRow._rightRegion, {
            title = "Spell Cast Highlight",
            captureRegion = castRow._rightRegion,
            disabled = function()
                return profile.showCastHighlight == false
                    or (CUI.BlizzStyle.Get("actionbars") and true or false)
            end,
            disabledTooltip = function()
                if CUI.BlizzStyle.Get("actionbars") then
                    return CUI.DisabledTooltip(CUI.BlizzStyle.Label("actionbars"), "disabled")
                end
                return CUI.DisabledTooltip("Show Highlight on Spell Cast")
            end,
            rawTooltip = true,
            rows = {
                {
                    type = "toggle",
                    label = "Show as Border",
                    tooltip = "On bars with a textured border style, the active spell shows a colored border instead of the highlight fill.",
                    get = function() return profile.castHighlightBorder or false end,
                    set = function(val)
                        profile.castHighlightBorder = val
                        ABAR:ApplyCheckedTextures()
                    end,
                },
            },
        })
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height

        -------------------------------------------------------------------
        --  PROC GLOW EFFECT
        -------------------------------------------------------------------
        _, height = W:SectionHeader(hostFrame, SECTION_PROC_GLOW, cursorY)
        cursorY = cursorY - height

        local procSpec = GO.DropdownSpec(procGlowDesc, "Custom Proc Glow")
        local function AssistOff() return not (GetCVarBool and GetCVarBool("assistedCombatHighlight")) end
        -- Row 1: Custom Proc Glow | its color swatches.
        row, height = W:DualRow(hostFrame, cursorY, procSpec, { type = "label", text = "Glow Color" })
        if not CUI._prebuilding then
            local leftRegion = row._leftRegion
            GO.AttachInline(leftRegion, procGlowDesc, row._rightRegion)
            _procGlowPreview = CreatePreviewIcon(leftRegion)
            -- Joins the inline chain left of the glow cog.
            _procGlowPreview:ClearAllPoints()
            Pix.Point(
                _procGlowPreview,
                "RIGHT",
                leftRegion._lastInline or leftRegion._control,
                "LEFT",
                -12,
                0
            )
            leftRegion._lastInline = _procGlowPreview
            if _procGlowPreview._icon then
                local iconTex = GetNthActionButtonIcon(3)
                _procGlowPreview._icon:SetTexture(iconTex)
                _procGlowPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            -- Hidden (options closed, page left or rebuilt), the preview's glow
            -- leaves the glow driver; shown again, it restarts from the current values.
            _procGlowPreview:SetScript("OnHide", function(self)
                if self._glowOv then CUI.Glows.StopAllGlows(self._glowOv) end
            end)
            _procGlowPreview:SetScript("OnShow", UpdateProcGlowPreview)
            UpdateProcGlowPreview(_procGlowPreview)
            CUI.RegisterWidgetRefresh(function() UpdateProcGlowPreview(_procGlowPreview) end)
        end
        cursorY = cursorY - height

        -- Assisted Highlight: the three stock styles, then one entry per glow
        -- engine (the Shape Glow is not offered: shaped buttons take it by
        -- themselves, as the proc glow does).
        local assistValues = {
            [1] = "Glow Ring",
            [2] = "Button Overlay",
            [3] = "Ring + Overlay",
        }
        local assistOrder = { 1, 2, 3 }
        for idx, record in ipairs(mod.LOOP_GLOW_TYPES or {}) do
            if not record.shapeGlow then
                assistValues[100 + idx] = record.name
                assistOrder[#assistOrder + 1] = 100 + idx
            end
        end
        local function assistCustomSelected() return (profile.assistGlowType or 0) > 0 end
        local function RingOff()
            local style = (profile.assistGlowStyle == 0 and 1) or profile.assistGlowStyle or 1
            return AssistOff() or assistCustomSelected() or style == 2
        end
        local function OverlayOff()
            local style = (profile.assistGlowStyle == 0 and 1) or profile.assistGlowStyle or 1
            return AssistOff() or assistCustomSelected() or style == 1
        end

        -- Row 2: Assisted Highlight | Assisted Highlight Outset
        local assistRow
        assistRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Assisted Highlight",
            values = assistValues,
            order = assistOrder,
            tooltip = "How Blizzard's next-spell suggestion is drawn on the button. Button Overlay replaces the blue ring with a flat tint, leaving the button edge free for the proc glow; a glow style runs that glow in combat and shows the ring outside it.",
            disabled = AssistOff,
            disabledTooltip = "This option requires Blizzard's Assisted Highlight to be enabled",
            rawTooltip = true,
            getValue = function()
                local custom = profile.assistGlowType or 0
                local entries = mod.LOOP_GLOW_TYPES or {}
                if custom > 0 and entries[custom] then return 100 + custom end
                return (profile.assistGlowStyle == 0 and 1) or profile.assistGlowStyle or 1
            end,
            setValue = function(val)
                if val >= 100 then
                    profile.assistGlowType = val - 100
                else
                    profile.assistGlowType = 0
                    profile.assistGlowStyle = val
                end
                mod.UpdateAssistHighlights()
                PaintAssistGlowPreview(_assistGlowPreview)
                CUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Assisted Highlight Outset",
            min = -10,
            max = 30,
            step = 1,
            tooltip = "Moves the blue Assisted Highlight ring outward (or inward at negative values) so it no longer overlaps the proc glow on the same button. With Ring + Overlay the tint resizes along with it, so the two stay flush.",
            disabled = RingOff,
            disabledTooltip = "This option requires Glow Ring or Ring + Overlay",
            rawTooltip = true,
            getValue = function() return profile.assistGlowOutset or 0 end,
            setValue = function(val)
                profile.assistGlowOutset = val
                mod.UpdateAssistHighlights()
                PaintAssistGlowPreview(_assistGlowPreview)
            end,
        })
        if not CUI._prebuilding then
            local leftRegion = assistRow._leftRegion
            _assistGlowPreview = CreatePreviewIcon(leftRegion)
            _assistGlowPreview:ClearAllPoints()
            Pix.Point(_assistGlowPreview, "RIGHT", leftRegion._control, "LEFT", -12, 0)
            if _assistGlowPreview._icon then
                _assistGlowPreview._icon:SetTexture(GetNthActionButtonIcon(4))
                _assistGlowPreview._icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            -- The custom glow's colour, chained left of the preview icon; the
            -- class colour owns it while Use Class Color is on.
            leftRegion._lastInline = _assistGlowPreview
            CUI.BuildInlineSwatches(leftRegion, {
                {
                    tooltip = "Assisted Highlight Glow Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = profile.assistGlowColor or { r = 0.15, g = 0.5, b = 1 }
                        return color.r, color.g, color.b
                    end,
                    setValue = function(red, green, blue)
                        profile.assistGlowColor = { r = red, g = green, b = blue }
                        mod.UpdateAssistHighlights()
                        PaintAssistGlowPreview(_assistGlowPreview)
                    end,
                },
            }, {
                disabled = function()
                    return AssistOff() or not assistCustomSelected() or profile.assistGlowUseClassColor
                end,
                disabledTooltip = function()
                    if AssistOff() then
                        return "This option requires Blizzard's Assisted Highlight to be enabled"
                    end
                    if not assistCustomSelected() then
                        return "This option requires a custom Assisted Highlight glow to be selected"
                    end
                    return CUI.DisabledTooltip("Use Class Color", "disabled")
                end,
                rawTooltip = true,
            })

            -- Keep animated preview hosts out of the central glow driver while
            -- this page is hidden; restart them from the current values on show.
            _assistGlowPreview:SetScript("OnHide", function(self)
                if self._assistGlowOv then CUI.Glows.StopAllGlows(self._assistGlowOv) end
                self._assistPvType = nil
            end)
            _assistGlowPreview:SetScript("OnShow", PaintAssistGlowPreview)
            PaintAssistGlowPreview(_assistGlowPreview)
            CUI.RegisterWidgetRefresh(function() PaintAssistGlowPreview(_assistGlowPreview) end)
        end
        cursorY = cursorY - height

        -- Row 3: Overlay Opacity (+ overlay color) | Fit Ring to Cropped Buttons
        local overlayRow
        overlayRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Overlay Opacity",
            min = 0,
            max = 100,
            step = 1,
            tooltip = "Opacity of the Button Overlay tint.",
            disabled = OverlayOff,
            disabledTooltip = "This option requires the Button Overlay or Ring + Overlay style",
            rawTooltip = true,
            getValue = function() return profile.assistGlowOverlayAlpha or 30 end,
            setValue = function(val)
                profile.assistGlowOverlayAlpha = val
                mod.UpdateAssistHighlights()
                PaintAssistGlowPreview(_assistGlowPreview)
            end,
        }, {
            type = "toggle",
            text = "Fit Ring to Cropped Buttons",
            tooltip = "On Cropped bars, shapes the Assisted Highlight ring to the button instead of a square.",
            disabled = RingOff,
            disabledTooltip = "This option requires Glow Ring or Ring + Overlay",
            rawTooltip = true,
            getValue = function() return profile.assistGlowFitCropped or false end,
            setValue = function(val)
                profile.assistGlowFitCropped = val
                mod.UpdateAssistHighlights()
            end,
        })
        if not CUI._prebuilding then
            CUI.BuildInlineSwatches(overlayRow._leftRegion, {
                {
                    tooltip = "Button Overlay Color",
                    hasAlpha = false,
                    getValue = function()
                        local color = profile.assistGlowOverlayColor or { r = 0.15, g = 0.5, b = 1 }
                        return color.r, color.g, color.b
                    end,
                    setValue = function(red, green, blue)
                        profile.assistGlowOverlayColor = { r = red, g = green, b = blue }
                        mod.UpdateAssistHighlights()
                        PaintAssistGlowPreview(_assistGlowPreview)
                    end,
                },
            }, {
                disabled = OverlayOff,
                disabledTooltip = "This option requires the Button Overlay or Ring + Overlay style",
            })
        end
        cursorY = cursorY - height

        -- Row 4: the custom glow's colour source (its swatch sits beside the
        -- preview icon above).
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Use Class Color",
            disabled = function() return AssistOff() or not assistCustomSelected() end,
            disabledTooltip = "This option requires a custom Assisted Highlight glow to be selected",
            rawTooltip = true,
            getValue = function() return profile.assistGlowUseClassColor or false end,
            setValue = function(val)
                profile.assistGlowUseClassColor = val
                mod.UpdateAssistHighlights()
                PaintAssistGlowPreview(_assistGlowPreview)
                CUI:RefreshPage()
            end,
        }, CUI.BlankRowCfg())
        cursorY = cursorY - height

        return math.abs(cursorY)
    end

    return BuildAnimationsPage
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_InitAnimationsPage = InitAnimationsPage
