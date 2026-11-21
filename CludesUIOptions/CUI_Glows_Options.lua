if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Glows_Options.lua -- Global Settings > Glows. A glow template (style,
--  color, Pixel Glow parameters) applied once to every active custom glow,
--  plus one card per module with every registered glow site as a full mirror
--  of its own page's controls (CludesUI.GlowOptions sites). Apply to All
--  only changes active custom glows; a row's or a module's Apply also turns
--  off glows on and replaces Blizzard Default, Solid and Blizzard Border.
--  Glows kept per icon, indicator or filter are listed as hints and never
--  taken by the template; a site's own confirm prompt runs as for an edit.
-------------------------------------------------------------------------------

local PAGE_GLOWS = "Glows"
local GLOBAL_KEY = "_CUIGlobal"

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

-- Session-only view state (never saved): expanded cards, cards hiding
-- their inactive glows, and a pending rebuild (see BuildGlowCard).
local _glExpanded, _glHideInactive = {}, {}
local _glRebuildQueued = false

-- Loads first in the options addon, before this file.
local GO = CludesUI.GlowOptions

-------------------------------------------------------------------------------
--  Template (account-wide; only ever a pattern, no module reads it)
-------------------------------------------------------------------------------
local TEMPLATE_DEFAULTS = { style = 1, mode = "default", lines = 8, thickness = 2, speed = 4 }

-- Read: the saved template, else the defaults. A read never writes, so a page
-- build (the hidden search pass included) saves nothing.
local function GlowTemplate() return CludesUIDB.glowTemplate or TEMPLATE_DEFAULTS end

-- Write: the saved template, made from the defaults on the first edit.
local function TemplateW()
    local t = CludesUIDB.glowTemplate
    if not t then
        t = CopyTable(TEMPLATE_DEFAULTS)
        CludesUIDB.glowTemplate = t
    end
    return t
end

local _templateDesc
local function TemplateDesc()
    if _templateDesc then return _templateDesc end
    -- Shape Glow is left out: almost no site can show it (it needs an icon shape).
    _templateDesc = {
        host = "icon",
        noNone = true,
        excludes = { [4] = true },
        caps = { mode = true, params = true, bg = true },
        get = function(f)
            local color = GlowTemplate()
            if f == "style" then
                return color.style or 1
            elseif f == "mode" then
                return color.mode or "default"
            elseif f == "color" then
                return color.r, color.g, color.b
            elseif f == "lines" then
                return color.lines
            elseif f == "thickness" then
                return color.thickness
            elseif f == "speed" then
                return color.speed
            elseif f == "bg" then
                return color.bg == true
            elseif f == "bgColor" then
                return color.bgR, color.bgG, color.bgB
            end
        end,
        set = function(f, a, b, c)
            local color = TemplateW()
            if f == "style" then
                color.style = a
            elseif f == "mode" then
                color.mode = a
                -- Custom without a picked color would apply nothing visible: seed gold.
                if a == "custom" and color.r == nil then
                    local d = CludesUI.Glows.DEFAULT_COLOR
                    color.r, color.g, color.b = d.r, d.g, d.b
                end
            elseif f == "color" then
                color.r, color.g, color.b = a, b, c
            elseif f == "lines" then
                color.lines = a
            elseif f == "thickness" then
                color.thickness = a
            elseif f == "speed" then
                color.speed = a
            elseif f == "bg" then
                color.bg = a and true or nil
            elseif f == "bgColor" then
                color.bgR, color.bgG, color.bgB = a, b, c
            end
        end,
    }
    return _templateDesc
end

-------------------------------------------------------------------------------
--  Sites
-------------------------------------------------------------------------------

-- Every registered site as { module, label, sub, desc, entry, nav }, per-bar
-- lists expanded. nav: where Open Settings goes (a list item's own, else the
-- entry); sub: the in-card group a row is listed under.
local function CollectSites()
    local result = {}
    for _, record in ipairs(GO.sites) do
        if record.list then
            for _, entry in ipairs(record.list() or {}) do
                result[#result + 1] = {
                    module = record.module,
                    label = entry.label,
                    sub = entry.sub or record.sub,
                    desc = entry.desc,
                    entry = record,
                    nav = entry.nav or record,
                }
            end
        elseif record.desc then
            result[#result + 1] = {
                module = record.module,
                label = record.label,
                sub = record.sub,
                desc = record.desc,
                entry = record,
                nav = record,
            }
        end
    end
    return result
end

-- Glows kept per entry in modules that register no hint of their own: added
-- at page build while the module is loaded, and only when no entry holds the
-- id yet (a module's own registration wins).
local ENTRY_GLOW_INFOS = {
    {
        id = "rf_bm_icon_glows",
        label = "Buff Manager Icon Glows",
        module = "CludesUIRaidFrames",
        page = "Buff Manager",
        info = {
            glyph = "icon",
            tooltip = "Icon Glow is set per indicator on the Buff Manager page. The template never changes it.",
            text = function() return CludesUI.L("Set per indicator") end,
        },
    },
    {
        id = "rf_dm_glows",
        label = "Debuff Manager Glows",
        module = "CludesUIRaidFrames",
        page = "Debuff Manager",
        info = {
            glyph = "icon",
            tooltip = "Icon Effects glows are set per filter and Frame Glow per tile on the Debuff Manager page. The template never changes them.",
            text = function() return CludesUI.L("Set per filter and tile") end,
        },
    },
    {
        id = "pab_icon_glows",
        label = "Player Aura Bars Icon Glows",
        module = "CludesUIUnitFrames",
        page = "Player Aura Bars",
        info = {
            glyph = "icon",
            tooltip = "Icon Effects glows are set per filter on each bar of the Player Aura Bars page. The template never changes them.",
            text = function() return CludesUI.L("Set per filter") end,
        },
    },
}

local function EnsureEntryGlowInfos()
    for _, entry in ipairs(ENTRY_GLOW_INFOS) do
        if CludesUI.ModuleNS(entry.module) then
            local have = false
            for i = 1, #GO.sites do
                if GO.sites[i].id == entry.id then
                    have = true
                    break
                end
            end
            if not have then GO.RegisterSite(entry) end
        end
    end
end

-- Info entries ({ info = { text, tooltip } }): no glow of their own, a hint
-- with a count and Go to Settings for glows kept per entry elsewhere.
local function CollectInfos()
    EnsureEntryGlowInfos()
    local result = {}
    for _, record in ipairs(GO.sites) do
        if record.info then
            result[#result + 1] = {
                module = record.module,
                label = record.label,
                sub = record.sub,
                info = record.info,
                nav = record,
            }
        end
    end
    return result
end

local function Blocked(site) return site.entry.blocked and site.entry.blocked() or false end

-- Can the template be written here at all (not locked by Blizzard Style or
-- its own settings page, and not a paramsOnly site: the Pixel Glow
-- parameters per-icon glows read, which the template never changes)?
local function CanTake(site)
    local desc = site.desc
    return not Blocked(site) and not desc.paramsOnly and not GO.StyleLocked(desc)
end

-- An active custom glow: what the template can change (the rest is hidden
-- until the card shows its inactive glows).
local function IsActive(site) return CanTake(site) and GO.IsCustomGlow(site.desc) end

local ST_GREY, ST_GREEN, ST_AMBER = { 0.5, 0.5, 0.5 }, { 0.30, 0.79, 0.94 }, { 0.88, 0.69, 0.31 }
-- The card summary wears the status dots' colors: amber "differ", green "all match".
local AMBER_CODE = CludesUI.HexColor(ST_AMBER[1], ST_AMBER[2], ST_AMBER[3])
local GREEN_CODE = CludesUI.HexColor(ST_GREEN[1], ST_GREEN[2], ST_GREEN[3])

-- Status of a site against the template: dot color, short word, tooltip text,
-- and whether it matches (one MatchesTemplate per evaluation).
local function SiteStatus(site, tbl)
    local desc = site.desc
    if Blocked(site) then return ST_GREY, CludesUI.L("Blizzard"), CludesUI.L("Blizzard Style"), false end
    if desc.paramsOnly then
        return ST_GREY,
            CludesUI.L("Per icon"),
            CludesUI.L(
                "The Pixel Glow settings this bar's per-icon glows use. The template never changes them."
            ),
            false
    end
    if not GO.IsCustomGlow(desc) then
        if GO.IsOff(desc) then return ST_GREY, CludesUI.L("Off"), CludesUI.L("Off"), false end
        return ST_GREY, CludesUI.L("Not custom"), CludesUI.L("Not a custom glow"), false
    end
    if GO.MatchesTemplate(desc, tbl) then
        return ST_GREEN, CludesUI.L("Matches"), CludesUI.L("Matches template"), true
    end
    local position, converted = GO.Resolve(desc, tbl.style or 1)
    if converted then
        return ST_AMBER,
            CludesUI.L("Differs"),
            CludesUI.Lf("Differs (template shows as %s)", CludesUI.L(CludesUI.Glows.STYLES[position].name)),
            false
    end
    return ST_AMBER, CludesUI.L("Differs"), CludesUI.L("Differs from template"), false
end

-- Would ApplyTo change this site? anyState: any unlocked site that differs
-- (off glows and extras included); otherwise active custom glows that differ.
local function Eligible(site, t, anyState)
    if anyState then
        if not CanTake(site) then return false end
    elseif not IsActive(site) then
        return false
    end
    return not GO.MatchesTemplate(site.desc, t)
end

-- One pass's refreshes: each distinct module refresh once (CDM bars share one
-- rebuild), the touched modules' cached pages dropped, this page rebuilt.
local function Settle(touched, refresh)
    for func in pairs(refresh) do
        func()
    end
    for module in pairs(touched) do
        CludesUI:InvalidateModulePageCache(module)
    end
    CludesUI:RefreshPage(true)
end

-- Apply the template to sites[first..]. A site with its own confirm
-- (desc.confirm: the prompt an edit of its style gets, such as a performance
-- warning when a glow turns on) goes through it exactly as an edit would.
-- When it prompts, the pass settles what it changed so far and stops;
-- accepting resumes at that site (confirmed = its index: not asked twice),
-- cancelling leaves it and the sites after it unchanged.
local function ApplyRun(sites, t, anyState, first, confirmed)
    local touched, refresh = {}, {}
    for i = first, #sites do
        local site = sites[i]
        local desc = site.desc
        if Eligible(site, t, anyState) then
            local val = GO.TemplateValue(desc, t)
            if val ~= nil and desc.confirm and i ~= confirmed then
                local inCall, passed = true, false
                desc.confirm(val, function()
                    if inCall then
                        passed = true
                    else
                        ApplyRun(sites, t, anyState, i, i)
                    end
                end)
                inCall = false
                if not passed then
                    Settle(touched, refresh)
                    return
                end
            end
            if GO.ApplyTemplate(desc, t, anyState) then
                if desc.onChange then refresh[desc.onChange] = true end
                touched[site.module] = true
            end
        end
    end
    Settle(touched, refresh)
end

-- Apply the template to the given sites: sites without a prompt first, so a
-- cancelled prompt holds back only the prompting sites after it.
local function ApplyTo(sites, t, anyState)
    local ordered = {}
    for _, site in ipairs(sites) do
        if not site.desc.confirm then ordered[#ordered + 1] = site end
    end
    for _, site in ipairs(sites) do
        if site.desc.confirm then ordered[#ordered + 1] = site end
    end
    ApplyRun(ordered, t, anyState, 1)
end

-- Counts what ApplyTo would change, for the confirm popup.
local function PreviewCounts(sites, t, anyState)
    local num, conv, turnOn = 0, 0, 0
    for _, site in ipairs(sites) do
        if Eligible(site, t, anyState) then
            num = num + 1
            local _, c = GO.TemplateValue(site.desc, t)
            if c then conv = conv + 1 end
            if not GO.IsCustomGlow(site.desc) then turnOn = turnOn + 1 end
        end
    end
    return num, conv, turnOn
end

-- anyState: a row's or a module's Apply (see Eligible).
local function ConfirmApply(sites, anyState)
    local t = GlowTemplate()
    local num, conv, turnOn = PreviewCounts(sites, t, anyState)
    if num == 0 then
        CludesUI:ShowInfoPopup({
            title = CludesUI.L("Apply Glow Template"),
            content = anyState and CludesUI.L(
                "Nothing to change: every glow here already matches the template."
            ) or CludesUI.L("Nothing to change: no active custom glow differs from the template."),
        })
        return
    end
    local msg = anyState and CludesUI.Lf("Apply the template to %d glow(s)?", num)
        or CludesUI.Lf("Apply the template to the %d active custom glow(s) listed here?", num)
    if turnOn > 0 then
        msg = msg
            .. "\n\n"
            .. CludesUI.Lf(
                "%d of them are off or use a Blizzard style and switch to the template glow.",
                turnOn
            )
    end
    if conv > 0 then
        msg = msg
            .. "\n\n"
            .. CludesUI.Lf("%d of them can't show the chosen style and use the closest one.", conv)
    end
    CludesUI:ShowConfirmPopup({
        title = CludesUI.L("Apply Glow Template"),
        message = msg,
        confirmText = CludesUI.L("Apply"),
        cancelText = CludesUI.L("Cancel"),
        onConfirm = function() ApplyTo(sites, t, anyState) end,
    })
end

-------------------------------------------------------------------------------
--  Rows
-------------------------------------------------------------------------------

-- A DualRow kept out of the search index: view controls and live counts are
-- no search results (a count would also go stale there). The flag is restored
-- even when the row errors.
local function UnindexedDualRow(W, hostFrame, cursorY, leftX, right)
    local prev = CludesUI._searchIndexSuppress
    CludesUI._searchIndexSuppress = true
    local success, row, height = pcall(W.DualRow, W, hostFrame, cursorY, leftX, right)
    CludesUI._searchIndexSuppress = prev
    if not success then error(row, 0) end
    return row, height
end

-- Round status dot left of a label half's text (the core's circle-mask dot).
local DOT_MASK = "Interface\\AddOns\\CludesUI\\media\\portraits\\circle_mask.tga"
local function StatusDot(region, color)
    local labelFS = region._label
    if not labelFS then return end
    local Pix = CludesUI.PanelPP
    local point, relTo, relPoint, posX, cursorY = labelFS:GetPoint(1)
    local dot = CreateFrame("Frame", nil, region)
    Pix.Size(dot, 8, 8)
    dot:SetPoint(point, relTo, relPoint, posX, cursorY)
    local texture = dot:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints()
    texture:SetColorTexture(color[1], color[2], color[3], 1)
    local mask = dot:CreateMaskTexture()
    mask:SetTexture(DOT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    labelFS:ClearAllPoints()
    Pix.Point(labelFS, "LEFT", dot, "RIGHT", 8, 0)
    labelFS:SetTextColor(color[1], color[2], color[3], 1)
    return texture
end

-- Why a site's Apply Template is greyed out, or nil when it would change it
-- (an off glow or an extra takes the template too). Manual edits apply live;
-- the button only exists for the template. matches: an already computed
-- MatchesTemplate result (nil = compute it here).
local function ApplyBlockedTip(site, t, matches)
    local desc = site.desc
    if desc.paramsOnly then return CludesUI.L("Per-icon glow settings: the template never changes them.") end
    if not CanTake(site) then
        -- A style-only lock names its own reason (its colors stay editable).
        if
            not Blocked(site)
            and not (desc.disabled and desc.disabled())
            and desc.styleDisabled
            and desc.styleDisabled()
        then
            return CludesUI.L(desc.styleDisabledTooltip)
        end
        return CludesUI.L("This glow is locked on its settings page.")
    end
    if matches == nil then matches = GO.MatchesTemplate(site.desc, t) end
    if matches then return CludesUI.L("Already matches the template.") end
    return nil
end

-- Light in-card group heading (a SectionHeader would split the card's search
-- section); inline search matches it by its text.
local SUB_H = 30
local function SubHeader(hostFrame, cursorY, textValue)
    local Pix = CludesUI.PanelPP
    local frame = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(frame, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, SUB_H)
    Pix.Point(frame, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, cursorY)
    local fontStr = CludesUI.MakeFont(frame, 11, nil, 1, 1, 1, 0.55)
    Pix.Point(fontStr, "BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 7)
    fontStr:SetText(textValue)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    Pix.Point(line, "LEFT", fontStr, "RIGHT", 10, 0)
    Pix.Point(line, "RIGHT", frame, "RIGHT", -20, 0)
    frame._labelText = textValue
    CludesUI._rowCounters[hostFrame] = 0
    return cursorY - SUB_H
end

-- Full-width rule between a card's control row and its glow rows.
local DIV_H = 11
local function CardDivider(hostFrame, cursorY)
    local Pix = CludesUI.PanelPP
    local frame = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(frame, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, DIV_H)
    Pix.Point(frame, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, cursorY)
    local line = frame:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.1)
    line:SetHeight(1)
    Pix.Point(line, "LEFT", frame, "LEFT", 20, 0)
    Pix.Point(line, "RIGHT", frame, "RIGHT", -20, 0)
    CludesUI._rowCounters[hostFrame] = 0
    return cursorY - DIV_H
end

-- Small drawn symbol left of an info row's label, styled like the card
-- glyphs (dark fill, accent edge): "icon" = one glowing button, "bar" =
-- three buttons with the middle one glowing.
local function InfoGlyph(region, kind)
    local labelFS = region._label
    if not (labelFS and kind) then return end
    local Pix = CludesUI.PanelPP
    local ACC = CludesUI.CLUDES_GREEN
    local point, relTo, relPoint, posX, cursorY = labelFS:GetPoint(1)
    local holderFrame = CreateFrame("Frame", nil, region)
    holderFrame:SetPoint(point, relTo, relPoint, posX, cursorY)
    local function Button(size, glow)
        local widget = CreateFrame("Frame", nil, holderFrame)
        Pix.Size(widget, size, size)
        local texture = widget:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints()
        texture:SetColorTexture(0.1, 0.1, 0.1, 1)
        if glow then
            CludesUI.MakeBorder(widget, ACC.r, ACC.g, ACC.b, 0.8, Pix)
        else
            CludesUI.MakeBorder(widget, 1, 1, 1, 0.15, Pix)
        end
        return widget
    end
    if kind == "bar" then
        Pix.Size(holderFrame, 32, 10)
        local prev
        for i = 1, 3 do
            local b = Button(10, i == 2)
            if prev then
                Pix.Point(b, "LEFT", prev, "RIGHT", 1, 0)
            else
                Pix.Point(b, "LEFT", holderFrame, "LEFT", 0, 0)
            end
            prev = b
        end
    else
        Pix.Size(holderFrame, 16, 16)
        Pix.Point(Button(16, true), "LEFT", holderFrame, "LEFT", 0, 0)
    end
    labelFS:ClearAllPoints()
    Pix.Point(labelFS, "LEFT", holderFrame, "RIGHT", 8, 0)
end

-- One info entry: label (hint as tooltip), its count, Go to Settings. The
-- count is written after the build: a count is no search result.
local function InfoRow(hostFrame, cursorY, W, entry)
    local details = entry.info
    local row, height = W:DualRow(
        hostFrame,
        cursorY,
        { type = "label", text = entry.label, tooltip = details.tooltip },
        CludesUI.BlankRowCfg()
    )
    if not CludesUI._prebuilding then
        local rrgn = row._rightRegion
        if details.text and rrgn._label then rrgn._label:SetText(details.text()) end
        InfoGlyph(row._leftRegion, details.glyph)
        local nav, module = entry.nav, entry.module
        if nav and nav.page then
            CludesUI.BuildInlineButton(
                rrgn,
                CludesUI.L("Go to Settings"),
                function()
                    CludesUI:NavigateToElementSettings(
                        module,
                        nav.page,
                        nav.section,
                        nav.preSelect,
                        nav.highlight
                    )
                end
            )
        end
    end
    return cursorY - height
end

-- One site: its own glow controls on the left, status + Apply + Open Settings
-- right. The status word is written after the build (no search result); its
-- tooltip rides the empty label from the start.
local function SiteRow(hostFrame, cursorY, W, site)
    local desc = site.desc
    local leftX
    if desc.paramsOnly then
        leftX = { type = "label", text = site.label }
    else
        leftX = GO.DropdownSpec(desc, site.label)
    end
    local color, short, long = SiteStatus(site, GlowTemplate())
    local statusCfg = CludesUI.BlankRowCfg()
    statusCfg.tooltip = long
    local row, height = W:DualRow(hostFrame, cursorY, leftX, statusCfg)
    if not CludesUI._prebuilding then
        local rrgn = row._rightRegion
        if rrgn._label then rrgn._label:SetText(short) end
        local dotTex = StatusDot(rrgn, color)
        local lrgn = row._leftRegion
        if desc.paramsOnly then
            -- A label half has no control to chain from: anchor the cog at the right edge.
            local Pix = CludesUI.PanelPP
            local anchor = CreateFrame("Frame", nil, lrgn)
            Pix.Size(anchor, 1, 1)
            Pix.Point(anchor, "RIGHT", lrgn, "RIGHT", -20, 0)
            lrgn._lastInline = anchor
            CludesUI.BuildInlineCog(
                lrgn,
                { title = "Pixel Glow Settings", rows = GO.CogRows(desc), captureRegion = lrgn }
            )
        else
            GO.AttachInline(lrgn, desc)
        end
        local nav, module = site.nav, site.module
        if nav and nav.page then
            CludesUI.BuildInlineButton(
                rrgn,
                CludesUI.L("Open Settings"),
                function()
                    CludesUI:NavigateToElementSettings(
                        module,
                        nav.page,
                        nav.section,
                        nav.preSelect,
                        nav.highlight
                    )
                end,
                { width = 104 }
            )
        end
        CludesUI.BuildInlineButton(
            rrgn,
            CludesUI.L("Apply Template"),
            function() ConfirmApply({ site }, true) end,
            {
                width = 110,
                disabled = function() return ApplyBlockedTip(site, GlowTemplate()) ~= nil end,
                disabledTooltip = function() return ApplyBlockedTip(site, GlowTemplate()) end,
                rawTooltip = true,
            }
        )
        -- Row edits only refresh widgets (no rebuild): keep the status current.
        CludesUI.RegisterWidgetRefresh(function()
            local c, s, l = SiteStatus(site, GlowTemplate())
            local labelFS = rrgn._label
            if labelFS then
                labelFS:SetText(s)
                labelFS:SetTextColor(c[1], c[2], c[3], 1)
            end
            if dotTex then dotTex:SetColorTexture(c[1], c[2], c[3], 1) end
            if rrgn._cfg then rrgn._cfg.tooltip = l end
        end)
    end
    return cursorY - height
end

-------------------------------------------------------------------------------
--  Cards
-------------------------------------------------------------------------------
local GL_GLYPH = "Interface\\AddOns\\CludesUI\\media\\textures\\melli.tga"

-- Card header summary: active glows and how many differ from the template.
local function CardSummary(entries, t)
    local isActive, differ = 0, 0
    for _, site in ipairs(entries) do
        if IsActive(site) then
            isActive = isActive + 1
            if not GO.MatchesTemplate(site.desc, t) then differ = differ + 1 end
        end
    end
    if isActive == 0 then return CludesUI.L("No active glows"), isActive end
    local tail
    if differ > 0 then
        tail = AMBER_CODE .. CludesUI.Lf("%d differ from template", differ) .. "|r"
    else
        tail = GREEN_CODE .. CludesUI.L("all match the template") .. "|r"
    end
    return CludesUI.Lf("%d active", isActive) .. ", " .. tail, isActive
end

-- Is every site of the card already matching or locked (nothing for its Apply)?
local function ModuleBlocked(tile)
    local t = GlowTemplate()
    for _, site in ipairs(tile.sites) do
        if not ApplyBlockedTip(site, t) then return false end
    end
    return true
end

-- Card body: a Hide Inactive toggle (off by default; greyed out when the card
-- has nothing inactive) and the module's Apply, then the rows grouped under
-- their sub headings. A card of hint rows only has neither.
local function BuildCardContent(hostFrame, cursorY, W, tile)
    local key = tile.key
    local showAll = _glHideInactive[key] ~= true
    local hasSites = #tile.sites > 0
    local row, height
    if hasSites then
        local inactive = #tile.sites - tile.active
        local leftX = {
            type = "toggle",
            text = CludesUI.Lf("Hide Inactive Glows (%d)", inactive),
            getValue = function() return _glHideInactive[key] == true end,
            setValue = function(val)
                _glHideInactive[key] = val or nil
                CludesUI:RefreshPage(true)
            end,
            disabled = function() return inactive == 0 end,
            disabledTooltip = CludesUI.L("Every glow in this module is active."),
            rawTooltip = true,
        }
        row, height = UnindexedDualRow(W, hostFrame, cursorY, leftX, CludesUI.BlankRowCfg())
        cursorY = cursorY - height
        if not CludesUI._prebuilding then
            CludesUI.BuildInlineButton(
                row._rightRegion,
                CludesUI.L("Apply Template to This Module"),
                function() ConfirmApply(tile.sites, true) end,
                {
                    width = 220,
                    disabled = function() return ModuleBlocked(tile) end,
                    disabledTooltip = CludesUI.L(
                        "Every glow in this module already matches the template or is locked on its settings page."
                    ),
                    rawTooltip = true,
                }
            )
        end
        cursorY = CardDivider(hostFrame, cursorY)
    end
    local lastSub
    -- Info entries lead the card (above any group) and never hide.
    for _, entry in ipairs(tile.infos) do
        if entry.sub and entry.sub ~= lastSub then cursorY = SubHeader(hostFrame, cursorY, entry.sub) end
        lastSub = entry.sub
        cursorY = InfoRow(hostFrame, cursorY, W, entry)
    end
    local isShown = 0
    for _, site in ipairs(tile.sites) do
        if showAll or IsActive(site) then
            if site.sub and site.sub ~= lastSub then cursorY = SubHeader(hostFrame, cursorY, site.sub) end
            lastSub = site.sub
            cursorY = SiteRow(hostFrame, cursorY, W, site)
            isShown = isShown + 1
        end
    end
    if hasSites and isShown == 0 then
        row, height = UnindexedDualRow(W, hostFrame, cursorY, {
            type = "label",
            text = CludesUI.L("No active glows. Turn off Hide Inactive Glows to edit the others."),
        }, CludesUI.BlankRowCfg())
        cursorY = cursorY - height
    end
    return cursorY
end

local function BuildTileList(sites, infos)
    local byModule, infosByModule, tiles = {}, {}, {}
    local t = GlowTemplate()
    for _, site in ipairs(sites) do
        local entries = byModule[site.module]
        if not entries then
            entries = {}
            byModule[site.module] = entries
        end
        entries[#entries + 1] = site
    end
    for _, entry in ipairs(infos) do
        local entries = infosByModule[entry.module]
        if not entries then
            entries = {}
            infosByModule[entry.module] = entries
        end
        entries[#entries + 1] = entry
    end
    for _, record in ipairs(CludesUI.ADDON_ROSTER) do
        local entries = byModule[record.folder]
        local infoList = infosByModule[record.folder]
        if (entries or infoList) and not record.comingSoon then
            entries = entries or {}
            local summary, isActive
            if #entries > 0 then
                summary, isActive = CardSummary(entries, t)
            else
                summary, isActive = CludesUI.L("Glows set per entry, which the template never changes"), 0
            end
            tiles[#tiles + 1] = {
                key = record.folder,
                folder = record.folder,
                display = record.display,
                desc = summary,
                active = isActive,
                sites = entries,
                infos = infoList or {},
                buildContent = BuildCardContent,
            }
        end
    end
    return tiles
end

local function BuildGlowCard(hostFrame, cursorY, W, tile)
    cursorY = CludesUI.BuildModuleCard(hostFrame, cursorY, W, tile, {
        -- Sites register only from loaded modules' option files.
        enabled = true,
        expanded = _glExpanded,
        descW = 560,
        -- The summary is live (counts): search indexes a fixed word instead.
        searchDesc = "Glows",
        glyph = function(heading, enabled)
            local Pix = CludesUI.PanelPP
            local ACC = CludesUI.CLUDES_GREEN
            local icon = CreateFrame("Frame", nil, heading)
            Pix.Size(icon, 18, 18)
            Pix.Point(icon, "LEFT", heading, "LEFT", 18, 0)
            CludesUI.MakeBorder(icon, ACC.r, ACC.g, ACC.b, enabled and 0.8 or 0.15, Pix)
            local texture = icon:CreateTexture(nil, "ARTWORK")
            Pix.Point(texture, "TOPLEFT", icon, "TOPLEFT", 3, -3)
            Pix.Point(texture, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", -3, 3)
            texture:SetTexture(GL_GLYPH)
            texture:SetVertexColor(1, 1, 1, enabled and 0.35 or 0.1)
        end,
    })
    -- A template or row edit can change the header summary, the inactive count
    -- and which rows show, on collapsed cards too. The summary text updates in
    -- place (a rebuild would close an open cog popup); a changed active count
    -- moves rows, so rebuild once.
    if #tile.sites > 0 and not CludesUI._prebuilding then
        CludesUI.RegisterWidgetRefresh(function()
            local summary, isActive = CardSummary(tile.sites, GlowTemplate())
            if summary ~= tile.desc and isActive == tile.active then
                if tile._descFS then tile._descFS:SetText(summary) end
                tile.desc = summary
            end
            if (summary ~= tile.desc or isActive ~= tile.active) and not _glRebuildQueued then
                _glRebuildQueued = true
                C_Timer.After(0, function()
                    _glRebuildQueued = false
                    if CludesUI:GetActivePage() == PAGE_GLOWS then CludesUI:RefreshPage(true) end
                end)
            end
        end)
    end
    return cursorY
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration)
-------------------------------------------------------------------------------
function _G._CUI_BuildGlowsPage(pageName, hostFrame, yOffset)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    local introHost = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(introHost, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, 62)
    Pix.Point(introHost, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, cursorY - 20)
    local intro = CludesUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    Pix.Point(intro, "TOPLEFT", introHost, "TOPLEFT", 0, -2)
    Pix.Point(intro, "TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(
        CludesUI.L("Set a glow once. Apply to All changes the active custom glows listed below.")
            .. "\n"
            .. CludesUI.L(
                "Module and row buttons also replace off glows, Blizzard Default, Blizzard Border and Solid Border."
            )
            .. "\n"
            .. CludesUI.L("Glows set per icon, indicator or filter keep their own settings.")
    )
    cursorY = cursorY - 66

    -- Template
    _, height = W:SectionHeader(hostFrame, "GLOW TEMPLATE", cursorY)
    cursorY = cursorY - height
    local tpl = TemplateDesc()
    local sites = CollectSites()
    local tplRow
    tplRow, height = W:DualRow(hostFrame, cursorY, GO.DropdownSpec(tpl, "Glow Style"), CludesUI.BlankRowCfg())
    cursorY = cursorY - height
    if not CludesUI._prebuilding then
        local lrgn = tplRow._leftRegion
        GO.AttachInline(lrgn, tpl)
        local preview = GO.BuildPreview(lrgn, tpl, { anchor = lrgn._lastInline, x = -12 })
        if preview then
            preview:SetFrameLevel(lrgn:GetFrameLevel() + 5)
            lrgn._lastInline = preview
        end
        CludesUI.BuildInlineButton(
            tplRow._rightRegion,
            CludesUI.L("Apply to All Active Glows"),
            function() ConfirmApply(sites) end,
            { width = 190 }
        )
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -- Module cards
    _, height = W:SectionHeader(hostFrame, "MODULE GLOWS", cursorY)
    cursorY = cursorY - height
    for _, tile in ipairs(BuildTileList(sites, CollectInfos())) do
        cursorY = BuildGlowCard(hostFrame, cursorY, W, tile)
    end

    return math.abs(cursorY)
end

-------------------------------------------------------------------------------
--  Deep-link pre-hook: a jump into this page (a search result) opens every
--  card and shows every row first, so the target row exists when the jump
--  looks for it (the Fonts and Textures pages do the same).
-------------------------------------------------------------------------------
do
    local origNav = CludesUI.NavigateToElementSettings
    function CludesUI:NavigateToElementSettings(moduleName, pageName, sectionName, preSelectFn, highlightText)
        -- The original refuses in combat: no page state changes then.
        if InCombatLockdown() then
            return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
        end
        if moduleName == GLOBAL_KEY and pageName == PAGE_GLOWS and (sectionName or highlightText) then
            local changed = false
            for _, record in ipairs(GO.sites) do
                local keyName = record.module
                if keyName and not _glExpanded[keyName] then
                    _glExpanded[keyName] = true
                    changed = true
                end
            end
            if next(_glHideInactive) then
                wipe(_glHideInactive)
                changed = true
            end
            if changed then CludesUI:InvalidatePageCache() end
        end
        return origNav(self, moduleName, pageName, sectionName, preSelectFn, highlightText)
    end
end
