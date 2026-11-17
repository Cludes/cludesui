if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_GlowOptions.lua -- shared glow option controls. Each glow setting
--  is a SITE descriptor: host ("icon"/"bar"/"engine"), view or toShared/
--  fromShared/order for its saved style numbering, excludes, noneValue,
--  extras (Blizzard Default, Solid; one with a style renders, e.g. Blizzard
--  Border; one marked colored is drawn in the site's color, e.g. Solid
--  Border; one marked noColor always draws its own art untinted, e.g.
--  Blizzard Pandemic Border, so the color controls lock while it is picked),
--  caps {mode, params, bg}, defaultColor, get/set on its own keys
--  ("style", "mode", "color", "lines", "thickness", "speed", "bg", "bgColor"),
--  plus optional isOff, onChange, confirm, disabled, colorDisabled, cogRows,
--  and styleDisabled + styleDisabledTooltip (a whole sentence, shown as is):
--  a lock on the style alone -- the color swatches and the Pixel Glow cog stay
--  live, and the template leaves the site alone while it holds.

local GO = {}
CludesUI.GlowOptions = GO

-- The glow engine loads in the parent addon, before any options file.
local G = CludesUI.Glows

-- The options page pool (CludesUI_FramePool.lua, the options addon's first
-- file): a frame made below on a pool host is handed out again, reset to new,
-- when that host is built again. Captured once here.
local CreateFrame, PoolGen = CludesUI._Pool.CreateFrame, CludesUI._Pool.Gen

-------------------------------------------------------------------------------
--  Style value mapping
-------------------------------------------------------------------------------
local function NoneValue(desc)
    if desc.noneValue ~= nil then
        return desc.noneValue
    end
    return 0
end

-- Saved value -> shared index, or nil for None and the extras.
function GO.ToShared(desc, val)
    if val == nil or val == NoneValue(desc) then
        return nil
    end
    if desc.toShared then
        return desc.toShared(val)
    end
    if desc.view then
        return desc.view.toShared[val]
    end
    if type(val) == "number" and val >= 1 and val <= #G.STYLES then
        return val
    end
    return nil
end

-- Shared index -> saved value.
function GO.FromShared(desc, position)
    if desc.fromShared then
        return desc.fromShared(position)
    end
    if desc.view then
        return desc.view.fromShared[position]
    end
    return position
end

-- Shared index -> the nearest style this site both renders and offers (its view
-- or order can lack styles the host could draw), plus whether it changed.
function GO.Resolve(desc, position)
    local ex = desc._resolveEx
    if not ex then
        ex = {}
        for i = 1, #G.STYLES do
            if (desc.excludes and desc.excludes[i]) or GO.FromShared(desc, i) == nil then
                ex[i] = true
            end
        end
        desc._resolveEx = ex
    end
    return G.ResolveStyle(position, desc.host, ex)
end

local function StyleOffered(desc, position)
    local caps = G.HOSTS[desc.host or "icon"]
    return caps and caps[position] and not (desc.excludes and desc.excludes[position])
end

-- Saved values offered by the site, in its own order.
local function OrderedStyleValues(desc)
    local result = {}
    if desc.order then
        for _, val in ipairs(desc.order) do
            local position = GO.ToShared(desc, val)
            if position and StyleOffered(desc, position) then
                result[#result + 1] = val
            end
        end
    elseif desc.view then
        for _, i in ipairs(desc.view.ordered) do
            if StyleOffered(desc, desc.view.toShared[i]) then
                result[#result + 1] = i
            end
        end
    else
        for i = 1, #G.STYLES do
            if StyleOffered(desc, i) then
                result[#result + 1] = i
            end
        end
    end
    return result
end

-- values/order pair for a WidgetFactory dropdown.
function GO.StyleValues(desc)
    local values, sequence = {}, {}
    if not desc.noNone then
        local nv = NoneValue(desc)
        values[nv] = "None"
        sequence[#sequence + 1] = nv
    end
    if desc.extras then
        for _, posX in ipairs(desc.extras) do
            values[posX.value] = posX.label
            sequence[#sequence + 1] = posX.value
        end
    end
    local styles = G.STYLES
    for _, val in ipairs(OrderedStyleValues(desc)) do
        values[val] = styles[GO.ToShared(desc, val)].name
        sequence[#sequence + 1] = val
    end
    return values, sequence
end

-- The value a style control shows: the saved one, or for a saved style this
-- host cannot render, the style that actually renders.
local function DisplayValue(desc, values)
    local val = desc.get("style")
    if val == nil then
        return NoneValue(desc)
    end
    if values[val] ~= nil then
        return val
    end
    local position = GO.ToShared(desc, val)
    if position then
        local rv = GO.FromShared(desc, (GO.Resolve(desc, position)))
        if rv ~= nil and values[rv] ~= nil then
            return rv
        end
    end
    return NoneValue(desc)
end

-------------------------------------------------------------------------------
--  State
-------------------------------------------------------------------------------
function GO.IsOff(desc)
    if desc.isOff and desc.isOff() then
        return true
    end
    local val = desc.get("style")
    return val == nil or val == NoneValue(desc)
end

-- The site's own lock (desc.disabled: every control), or a style-only lock
-- (desc.styleDisabled: the style dropdown alone). Either keeps the template out.
function GO.StyleLocked(desc)
    if desc.disabled and desc.disabled() then
        return true
    end
    return (desc.styleDisabled and desc.styleDisabled()) and true or false
end

-- A real glow (not off, not an extra such as Blizzard Default or Solid).
-- paramsOnly sites (Pixel Glow parameters without a style of their own, e.g. a
-- CDM bar's pixelGlow* keys) always count as one.
function GO.IsCustomGlow(desc)
    if desc.paramsOnly then
        return true
    end
    if GO.IsOff(desc) then
        return false
    end
    return GO.ToShared(desc, desc.get("style")) ~= nil
end

-- The extra entry for the site's current value, if that value is one.
local function CurrentExtra(desc)
    if not desc.extras then
        return nil
    end
    local val = desc.get("style")
    for _, posX in ipairs(desc.extras) do
        if posX.value == val then
            return posX
        end
    end
    return nil
end

-- Something is drawn that takes a color: a custom glow, or a rendered extra
-- (x.style, e.g. Blizzard Border). Rendered extras are never template targets.
function GO.Renders(desc)
    if GO.IsCustomGlow(desc) then
        return true
    end
    if GO.IsOff(desc) then
        return false
    end
    local posX = CurrentExtra(desc)
    return posX ~= nil and posX.style ~= nil
end

-- The current value is an extra that takes no color (x.noColor): its art is
-- always drawn untinted, so the site's color controls lock.
local function NoColor(desc)
    local posX = CurrentExtra(desc)
    return posX ~= nil and posX.noColor == true
end

function GO.IsPixel(desc)
    if desc.paramsOnly then
        return true
    end
    return GO.IsCustomGlow(desc) and GO.ToShared(desc, desc.get("style")) == 1
end

-- Render spec for StartSpecGlow from the site's current values (one reused
-- table per descriptor).
function GO.Spec(desc)
    local s = desc._spec
    if not s then
        s = {}
        desc._spec = s
    end
    local posX = CurrentExtra(desc)
    s.style = GO.ToShared(desc, desc.get("style")) or (posX and posX.style) or 1
    s.excludes = desc.excludes
    local dc = desc.defaultColor
    local mode = desc.caps and desc.caps.mode and desc.get("mode") or "custom"
    local cr, cg, cb = desc.get("color")
    s.r, s.g, s.b = G.ResolveColor(mode, cr, cg, cb, dc and dc.r, dc and dc.g, dc and dc.b)
    local caps = desc.caps or {}
    if caps.params then
        s.lines, s.thickness, s.speed = desc.get("lines"), desc.get("thickness"), desc.get("speed")
    else
        s.lines, s.thickness, s.speed = nil, nil, nil
    end
    if caps.bg and desc.get("bg") then
        s.bg = true
        s.bgR, s.bgG, s.bgB = desc.get("bgColor")
    else
        s.bg, s.bgR, s.bgG, s.bgB = nil, nil, nil, nil
    end
    return s
end

-- Refresh the module, then this site's current preview (skipped once that
-- preview's page is gone: descriptors outlive page rebuilds).
function GO.Changed(desc)
    if desc.onChange then
        desc.onChange()
    end
    local popFrame = desc._previewFrame
    if desc._preview and popFrame and popFrame:IsVisible() then
        desc._preview()
    end
end

-------------------------------------------------------------------------------
--  Controls
-------------------------------------------------------------------------------

-- Lock reason for color controls while no glow is picked (a whole sentence).
local NO_STYLE_TIP = "This option requires a Glow Style other than None"
-- Lock reason for color controls while a noColor extra is picked.
local NO_COLOR_TIP = "This option requires a Glow Style that can be colored"

-- The style control's getter: None while off, else the displayed value.
local function StyleGetter(desc, values)
    return function()
        if desc.isOff and desc.isOff() then
            return NoneValue(desc)
        end
        return DisplayValue(desc, values)
    end
end

-- The style control's lock: the site's own disabled/disabledTooltip/rawTooltip,
-- widened by styleDisabled when the site has one (its sentence shows as is
-- while only the style is locked).
local function StyleLock(desc)
    if not desc.styleDisabled then
        return desc.disabled, desc.disabledTooltip, desc.rawTooltip
    end
    local function siteOff()
        return desc.disabled and desc.disabled()
    end
    return function()
        return GO.StyleLocked(desc)
    end, function()
        if not siteOff() then
            return desc.styleDisabledTooltip
        end
        local tt = desc.disabledTooltip
        if type(tt) == "function" then
            tt = tt()
        end
        return tt
    end, function()
        if not siteOff() then
            return true
        end
        local raw = desc.rawTooltip
        if type(raw) == "function" then
            raw = raw()
        end
        return raw
    end
end

-- DualRow half spec for the style dropdown.
function GO.DropdownSpec(desc, textValue, tooltip)
    local values, sequence = GO.StyleValues(desc)
    local lockFn, lockTip, lockRaw = StyleLock(desc)
    return {
        type = "dropdown",
        text = textValue or "Glow",
        values = values,
        order = sequence,
        tooltip = tooltip,
        disabled = lockFn,
        disabledTooltip = lockTip,
        rawTooltip = lockRaw,
        getValue = StyleGetter(desc, values),
        setValue = function(val)
            local function commit()
                desc.set("style", val)
                GO.Changed(desc)
                C_Timer.After(0, function()
                    CludesUI:RefreshPage()
                end)
            end
            if desc.confirm then
                desc.confirm(val, commit)
            else
                commit()
            end
        end,
    }
end

local function NotPixel(desc)
    return function()
        return not GO.IsPixel(desc)
    end
end

-- Cog edits refresh the page's widgets (status rows follow them) once per
-- frame, so a slider drag does not queue a refresh per tick.
local _cogRefreshQueued = false
local function CogChanged(desc)
    GO.Changed(desc)
    if _cogRefreshQueued then
        return
    end
    _cogRefreshQueued = true
    C_Timer.After(0, function()
        _cogRefreshQueued = false
        CludesUI:RefreshPage()
    end)
end

-- Pixel Glow cog rows (Lines / Thickness / Speed / Background), plus the
-- site's own extra rows. The Pixel Glow ones carry pixelRow (see PopupRows).
local function CogRows(desc)
    local rowList = {}
    local caps = desc.caps or {}
    local notPixel = NotPixel(desc)
    if caps.params then
        rowList[#rowList + 1] = {
            type = "slider",
            label = "Lines",
            min = 2,
            max = 16,
            step = 1,
            get = function()
                return desc.get("lines") or 8
            end,
            set = function(val)
                desc.set("lines", val)
                CogChanged(desc)
            end,
            disabled = notPixel,
            disabledTooltip = "Pixel Glow",
            pixelRow = true,
        }
        rowList[#rowList + 1] = {
            type = "slider",
            label = "Thickness",
            min = 1,
            max = desc.thicknessMax or 4,
            step = 1,
            get = function()
                return desc.get("thickness") or 2
            end,
            set = function(val)
                desc.set("thickness", val)
                CogChanged(desc)
            end,
            disabled = notPixel,
            disabledTooltip = "Pixel Glow",
            pixelRow = true,
        }
        rowList[#rowList + 1] = {
            type = "slider",
            label = "Speed",
            min = 1,
            max = 8,
            step = 1,
            get = function()
                return G.SpeedToUI(desc.get("speed"))
            end,
            set = function(val)
                desc.set("speed", G.SpeedFromUI(val))
                CogChanged(desc)
            end,
            disabled = notPixel,
            disabledTooltip = "Pixel Glow",
            pixelRow = true,
        }
    end
    if caps.bg then
        rowList[#rowList + 1] = {
            type = "toggle",
            label = "Background",
            get = function()
                return desc.get("bg") == true
            end,
            set = function(val)
                desc.set("bg", val and true or nil)
                CogChanged(desc)
            end,
            disabled = notPixel,
            disabledTooltip = "Pixel Glow",
            pixelRow = true,
        }
        rowList[#rowList + 1] = {
            type = "colorpicker",
            label = "Background Color",
            get = function()
                local r, g, b = desc.get("bgColor")
                return r or 0, g or 0, b or 0
            end,
            set = function(r, g, b)
                desc.set("bgColor", r, g, b)
                CogChanged(desc)
            end,
            disabled = function()
                return notPixel() or desc.get("bg") ~= true
            end,
            disabledTooltip = "Pixel Glow Background",
            pixelRow = true,
        }
    end
    if desc.cogRows then
        for _, r in ipairs(desc.cogRows) do
            rowList[#rowList + 1] = r
        end
    end
    return rowList
end

GO.CogRows = CogRows

-- Default/Custom/Class swatches as one BuildCogPopup row (off: when the
-- row is locked).
local function ColorRow(desc, off)
    local function modeAlpha(m)
        return function()
            return (desc.get("mode") == m) and 1 or 0.3
        end
    end
    local function pick(m)
        return function()
            desc.set("mode", m)
            GO.Changed(desc)
            CludesUI:RefreshPage()
        end
    end
    local dc = desc.defaultColor
    return {
        type = "multiswatch",
        label = "Glow Color",
        disabled = off,
        disabledTooltip = function()
            return NoColor(desc) and NO_COLOR_TIP or "a Glow Style"
        end,
        swatches = {
            {
                tooltip = "Default",
                refreshAlpha = modeAlpha("default"),
                onClick = pick("default"),
                getValue = function()
                    local c = G.DEFAULT_COLOR
                    return c.r, c.g, c.b, 1
                end,
            },
            {
                tooltip = "Custom Color",
                refreshAlpha = modeAlpha("custom"),
                getValue = function()
                    local r, g, b = desc.get("color")
                    return r or (dc and dc.r) or 1, g or (dc and dc.g) or 1, b or (dc and dc.b) or 1, 1
                end,
                setValue = function(r, g, b)
                    desc.set("color", r, g, b)
                    CogChanged(desc)
                end,
                -- Suite convention: an inactive custom swatch only selects custom mode.
                onClick = function(self)
                    if desc.get("mode") ~= "custom" then
                        desc.set("mode", "custom")
                        GO.Changed(desc)
                        CludesUI:RefreshPage()
                    elseif self._eabOrigClick then
                        self._eabOrigClick(self)
                    end
                end,
            },
            {
                tooltip = "Class Colored",
                refreshAlpha = modeAlpha("class"),
                onClick = pick("class"),
                getValue = function()
                    local c = CludesUI.GetClassColor(CludesUI._playerClass)
                    return c.r, c.g, c.b, 1
                end,
            },
        },
    }
end

-- Every glow control as BuildCogPopup rows, for sites whose whole glow setting
-- lives inside a cog: style dropdown, Default/Custom/Class swatches, pixel rows.
-- hidePixel: the Pixel Glow rows are left out, not greyed, while another style
-- is picked (row.hidden: the popup swaps its rows as the style changes).
function GO.PopupRows(desc, styleLabel, hidePixel)
    local values, sequence = GO.StyleValues(desc)
    local rowList = {}
    local off = function()
        return not GO.Renders(desc)
    end
    local lockFn, lockTip, lockRaw = StyleLock(desc)
    rowList[#rowList + 1] = {
        type = "dropdown",
        label = styleLabel or "Glow Style",
        values = values,
        order = sequence,
        ddWidth = 170,
        disabled = lockFn,
        disabledTooltip = lockTip,
        rawTooltip = lockRaw,
        get = StyleGetter(desc, values),
        set = function(val)
            local function commit()
                desc.set("style", val)
                GO.Changed(desc)
                CludesUI:RefreshPage()
            end
            if desc.confirm then
                desc.confirm(val, commit)
            else
                commit()
            end
        end,
    }
    local caps = desc.caps or {}
    if caps.mode then
        rowList[#rowList + 1] = ColorRow(desc, function()
            return off() or NoColor(desc)
        end)
    end
    local notPixel = hidePixel and NotPixel(desc) or nil
    for _, r in ipairs(CogRows(desc)) do
        if notPixel and r.pixelRow then
            r.hidden = notPixel
        end
        rowList[#rowList + 1] = r
    end
    return rowList
end

-- The Pixel Glow cog and the color swatches, chained left of the region's control (the cog closest).
-- rgn = the DualRow half-region holding the style dropdown; colorRgn = an
-- optional free half-region (a "Glow Color" label) that takes the swatches.
-- A style-only lock (desc.styleDisabled) leaves both live.
function GO.AttachInline(region, desc, colorRgn)
    if CludesUI._prebuilding or not region then
        return
    end
    local Pix = CludesUI.PanelPP
    local caps = desc.caps or {}
    local function siteOff()
        return desc.disabled and desc.disabled()
    end
    local function off()
        if siteOff() then
            return true
        end
        return not GO.Renders(desc)
    end
    -- colorDisabled: the site's color comes from elsewhere (NP Color by Type).
    -- A colored extra (Solid Border) draws nothing to style but takes the color;
    -- a noColor extra (Blizzard Pandemic Border) draws but never takes one.
    local function colorOff()
        if siteOff() then
            return true
        end
        if not GO.Renders(desc) then
            local posX = CurrentExtra(desc)
            if not (posX and posX.colored) then
                return true
            end
        end
        if NoColor(desc) then
            return true
        end
        return (desc.colorDisabled and desc.colorDisabled()) or false
    end
    -- Why the swatches are locked, as the sentence shown: the site's own
    -- requirement (resolved like its dropdown's), no glow to color, a style
    -- that takes no color, or a color that comes from elsewhere.
    local function colorLockTip()
        if siteOff() then
            return CludesUI.ResolveDisabledTip(desc)
        end
        if not GO.Renders(desc) then
            return CludesUI.DisabledTooltip(NO_STYLE_TIP)
        end
        if NoColor(desc) then
            return CludesUI.DisabledTooltip(NO_COLOR_TIP)
        end
        if desc.colorDisabledTooltip then
            return CludesUI.DisabledTooltip(desc.colorDisabledTooltip, "disabled")
        end
    end
    local level = region:GetFrameLevel() + 3
    -- Disabled swatches still explain themselves: a mouse blocker over them
    -- (from first to last) with the reason, shown while the color is locked.
    local function Blocker(first, last)
        local block = CreateFrame("Frame", nil, colorRgn or region)
        block:SetPoint("TOPLEFT", first, "TOPLEFT")
        block:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT")
        block:SetFrameLevel(level + 10)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function(self)
            local tipText = colorLockTip()
            if tipText then
                CludesUI.ShowWidgetTooltip(self, tipText)
            end
        end)
        block:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        return block
    end

    -- colorInCog: the row is too narrow for the swatches; they go in the cog.
    local colorInCog = desc.colorInCog and caps.mode

    local cog
    local rowList = CogRows(desc)
    if colorInCog then
        table.insert(rowList, 1, ColorRow(desc, colorOff))
    end
    if #rowList > 0 then
        local hasExtra = (desc.cogRows and #desc.cogRows > 0) or colorInCog
        cog = CludesUI.BuildInlineCog(region, {
            title = "Glow Settings",
            rows = rowList,
            captureRegion = region,
            disabled = function()
                if off() then
                    return true
                end
                return not hasExtra and not GO.IsPixel(desc)
            end,
            -- Whichever lock holds, as the sentence shown: the site's own
            -- requirement, else a glow to set (rows beyond Pixel's), else Pixel Glow.
            disabledTooltip = function()
                if siteOff() then
                    return CludesUI.ResolveDisabledTip(desc)
                end
                if hasExtra then
                    return CludesUI.DisabledTooltip(NO_STYLE_TIP)
                end
                return CludesUI.DisabledTooltip("Pixel Glow")
            end,
            rawTooltip = true,
        })
    end

    if colorInCog then
        -- The swatches are the cog's first row (above).
    elseif caps.mode then
        local srgn = colorRgn or region
        local customSw, defaultSw, classSw = CludesUI.BuildTrioColorSwatch(srgn, level, {
            getMode = function()
                return desc.get("mode") or "custom"
            end,
            setMode = function(m)
                desc.set("mode", m)
            end,
            getCustomRGB = function()
                local r, g, b = desc.get("color")
                local dc = desc.defaultColor
                return r or (dc and dc.r) or 1, g or (dc and dc.g) or 1, b or (dc and dc.b) or 1
            end,
            setCustomRGB = function(r, g, b)
                desc.set("color", r, g, b)
            end,
            -- Mode clicks: the trio's highlight and page status refresh via widget refresh.
            onChange = function()
                GO.Changed(desc)
                CludesUI:RefreshPage()
            end,
            hasClassColor = true,
            disabled = colorOff,
            overrideSize = 20,
        })
        local anchor = srgn._lastInline or srgn._control
        if anchor then
            -- 8 left of the cog when it shares this half, else 12 left of the control.
            Pix.Point(classSw, "RIGHT", anchor, "LEFT", (cog and srgn == region) and -8 or -12, 0)
        else
            Pix.Point(classSw, "RIGHT", srgn, "RIGHT", -20, 0)
        end
        Pix.Point(customSw, "RIGHT", classSw, "LEFT", -6, 0)
        Pix.Point(defaultSw, "RIGHT", customSw, "LEFT", -6, 0)
        srgn._lastInline = defaultSw
        -- An off glow has no color to set: the swatches take no clicks and the
        -- blocker over them explains why. The build and every refresh apply it.
        local block = Blocker(defaultSw, classSw)
        local function SyncColorLock()
            local o = colorOff()
            customSw:EnableMouse(not o)
            defaultSw:EnableMouse(not o)
            classSw:EnableMouse(not o)
            block:SetShown(o)
        end
        SyncColorLock()
        CludesUI.RegisterWidgetRefresh(SyncColorLock)
    end
end

-------------------------------------------------------------------------------
--  Preview
--  An icon (or a bar for bar hosts) with the site's glow, rendered through
--  the same call the live site uses, so the preview is the live look.
-------------------------------------------------------------------------------
local PREVIEW_ICON = 136197

function GO.BuildPreview(hostFrame, desc, options)
    if CludesUI._prebuilding or not hostFrame then
        return
    end
    options = options or {}
    local Pix = CludesUI.PanelPP
    local isBar = options.bar
    if isBar == nil then
        isBar = desc.host == "bar"
    end
    local wid = options.width or (isBar and 110 or 36)
    local hgt = options.height or (isBar and 16 or 36)

    local f = CreateFrame("Frame", nil, hostFrame)
    -- This build's dress of the preview: the descriptor keeps Refresh past later
    -- builds (desc._preview), which can dress these frames for another use.
    local dressGen = PoolGen(f)
    Pix.Size(f, wid, hgt)
    if options.anchor then
        Pix.Point(
            f,
            options.point or "RIGHT",
            options.anchor,
            options.relPoint or "LEFT",
            options.x or -8,
            options.y or 0
        )
    end
    local texture = f:CreateTexture(nil, "ARTWORK")
    texture:SetAllPoints()
    -- opts.icon: a texture, or a function re-read on every refresh.
    local iconFn = type(options.icon) == "function" and options.icon or nil
    if isBar then
        texture:SetColorTexture(0.2, 0.2, 0.2, 1)
    else
        texture:SetTexture((iconFn and iconFn()) or options.icon or PREVIEW_ICON)
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    -- 1px black edge (below the glow overlay, which sits one level higher).
    Pix.CreateBorder(f, 0, 0, 0, 1, 1, "OVERLAY", 6)

    local shade = CreateFrame("Frame", nil, f)
    shade:SetAllPoints(f)
    shade:SetFrameLevel(f:GetFrameLevel() + 2)
    shade:EnableMouse(false)
    shade._cuiGlowPreview = true -- exempt from CDM's Show Glows Only in Combat gate

    local function Refresh()
        -- Hidden: stays stopped until OnShow (a page refresh with the panel
        -- closed must not put it back into the glow driver). Dressed again
        -- by a later build: those frames are no longer this preview.
        if PoolGen(f) ~= dressGen or not f:IsVisible() then
            return
        end
        if iconFn and not isBar then
            texture:SetTexture(iconFn() or PREVIEW_ICON)
        end
        if not GO.Renders(desc) then
            G.StopGlow(shade)
            f:SetAlpha(0.3)
            return
        end
        f:SetAlpha(1)
        G.StartSpecGlow(shade, GO.Spec(desc), wid, hgt, desc.host, G.PANEL_EXTRA)
    end
    -- A hidden preview (options closed, page left or rebuilt) stops its glow,
    -- so it leaves the glow driver and a closed panel costs nothing; shown
    -- again (a cached page coming back), it restarts from the current values.
    f:SetScript("OnHide", function()
        G.StopGlow(shade)
    end)
    f:SetScript("OnShow", Refresh)
    -- Latest build only: descriptors outlive page rebuilds, a list would grow.
    desc._preview, desc._previewFrame = Refresh, f
    CludesUI.RegisterWidgetRefresh(Refresh)
    Refresh()
    return f, Refresh
end

-------------------------------------------------------------------------------
--  Flat key schema: <p>Color, <p>Lines, <p>Thickness, <p>Speed, <p>Background,
--  <p>BackgroundColor (colors as {r,g,b} tables). FlatGet / FlatSet cover these
--  six fields; each site keeps its own style and mode (their semantics differ).
--  defs: optional fallbacks under the same keys (a module's defaults table).
--  The key names come from the glow engine's CludesUI.Glows.FlatKeys.
-------------------------------------------------------------------------------
local FLAT_FIELDS = { color = true, lines = true, thickness = true, speed = true, bg = true, bgColor = true }
local function FlatKey(p, f)
    return FLAT_FIELDS[f] and G.FlatKeys(p)[f] or nil
end

function GO.FlatGet(t, p, f, defs)
    local key = FlatKey(p, f)
    if not (key and t) then
        return nil
    end
    local val = t[key]
    if val == nil and defs then
        val = defs[key]
    end
    if f == "bg" then
        return val == true
    end
    if f == "color" or f == "bgColor" then
        if type(val) == "table" then
            return val.r, val.g, val.b
        end
        return nil
    end
    return val
end

function GO.FlatSet(t, p, f, a, b, c)
    local key = FlatKey(p, f)
    if not (key and t) then
        return
    end
    if f == "color" or f == "bgColor" then
        t[key] = { r = a, g = b, b = c }
    else
        t[key] = a
    end
end

-------------------------------------------------------------------------------
--  Descriptor for the prefix key schema (CludesUI.Glows.PrefixKeys): the
--  aura managers' icon glows (RF Debuff/Buff Manager, Player Aura Bars).
--  getT returns the live settings table; style is a shared index, 0 = off.
-------------------------------------------------------------------------------
function GO.PrefixSite(getT, p, host, onChange, defColor)
    local key = G.PrefixKeys(p)
    local desc = {
        host = host,
        caps = { mode = true, params = true, bg = true },
        defaultColor = defColor or { r = 1.0, g = 0.776, b = 0.376 },
        onChange = onChange,
    }
    function desc.get(f)
        local t = getT()
        if not t then
            return nil
        end
        if f == "style" then
            return t[key.type] or 0
        elseif f == "mode" then
            return G.DeriveColorMode(t[key.mode], t[key.class])
        elseif f == "color" then
            return t[key.r], t[key.g], t[key.b]
        elseif f == "lines" then
            return t[key.lines]
        elseif f == "thickness" then
            return t[key.th]
        elseif f == "speed" then
            return t[key.speed]
        elseif f == "bg" then
            return t[key.bg] == true
        elseif f == "bgColor" then
            return t[key.bgR], t[key.bgG], t[key.bgB]
        end
    end
    function desc.set(f, a, b, c)
        local t = getT()
        if not t then
            return
        end
        if f == "style" then
            t[key.type] = a
        elseif f == "mode" then
            -- The legacy class flag stays in step for older readers of this table.
            t[key.mode] = a
            t[key.class] = (a == "class") or nil
        elseif f == "color" then
            t[key.r], t[key.g], t[key.b] = a, b, c
        elseif f == "lines" then
            t[key.lines] = a
        elseif f == "thickness" then
            t[key.th] = a
        elseif f == "speed" then
            t[key.speed] = a
        elseif f == "bg" then
            t[key.bg] = a and true or nil
        elseif f == "bgColor" then
            t[key.bgR], t[key.bgG], t[key.bgB] = a, b, c
        end
    end
    return desc
end

-------------------------------------------------------------------------------
--  Site registry (Global Settings > Glows)
--  group "module": one descriptor per module-level setting.
--  group "bar":    a provider returning the current list of per-bar
--                  descriptors (bars are created and removed at runtime).
-------------------------------------------------------------------------------
GO.sites = {}

-- entry = { id, label, module, page, section, highlight, group, sub,
--           desc = descriptor | nil, list = function() return { {label, sub, desc, nav}, ... } end }
-- nav = { page, section, highlight, preSelect } for a list item's Open Settings;
-- sub = the group heading the row is listed under on the Glows page card;
-- info = { text = fn, tooltip, glyph = "icon"/"bar" } instead of desc/list: a hint row with Go to Settings.
function GO.RegisterSite(record)
    for i = 1, #GO.sites do
        if GO.sites[i].id == record.id then
            GO.sites[i] = record
            return
        end
    end
    GO.sites[#GO.sites + 1] = record
end

-- The saved style value a template writes into a site, whether the site had
-- to take the nearest style it offers, and that style's shared index. nil for
-- a site that takes no template: a paramsOnly site (the Pixel Glow parameters
-- per-icon glows read, which the template never changes) or a style the site
-- cannot map.
function GO.TemplateValue(desc, t)
    if desc.paramsOnly then
        return nil, false
    end
    local position, converted = GO.Resolve(desc, t.style or 1)
    return GO.FromShared(desc, position), converted, position
end

-- Write a template (shared-index style + color + parameters) into a site.
-- Only an active custom glow is touched, unless anyState: then an off glow is
-- turned on and an extra (Blizzard Default, Solid, Blizzard Border) replaced.
-- A locked site (GO.StyleLocked) and a paramsOnly site are never written.
-- Writes directly: a caller acting for the user routes the style through the
-- site's own confirm first (see desc.confirm). Returns applied, converted.
function GO.ApplyTemplate(desc, t, anyState)
    if not anyState and not GO.IsCustomGlow(desc) then
        return false, false
    end
    if GO.StyleLocked(desc) then
        return false, false
    end
    local val, converted, position = GO.TemplateValue(desc, t)
    if val == nil then
        return false, false
    end
    local caps = desc.caps or {}
    desc.set("style", val)
    local tm = t.mode or "custom"
    if caps.mode then
        desc.set("mode", tm)
    end
    if tm == "custom" and t.r then
        desc.set("color", t.r, t.g, t.b)
    end
    -- Pixel parameters only go where the result is a Pixel Glow: for any other
    -- template style they are hidden in the template and would reset the site's.
    if caps.params and position == 1 then
        desc.set("lines", t.lines or 8)
        desc.set("thickness", t.thickness or 2)
        desc.set("speed", t.speed or 4)
    end
    if caps.bg and position == 1 then
        desc.set("bg", t.bg and true or nil)
        if t.bg then
            desc.set("bgColor", t.bgR or 0, t.bgG or 0, t.bgB or 0)
        end
    end
    return true, converted
end

-- Does the site already show what ApplyTemplate would write? An off glow or
-- an extra never does, nor a paramsOnly site (never a template target).
function GO.MatchesTemplate(desc, t)
    if desc.paramsOnly or not GO.IsCustomGlow(desc) then
        return false
    end
    local caps = desc.caps or {}
    local position = GO.Resolve(desc, t.style or 1)
    if GO.ToShared(desc, desc.get("style")) ~= position then
        return false
    end
    local mode = caps.mode and desc.get("mode") or "custom"
    if mode ~= (t.mode or "custom") then
        return false
    end
    if mode == "custom" and t.r then
        local r, g, b = desc.get("color")
        if r ~= t.r or g ~= t.g or b ~= t.b then
            return false
        end
    end
    if caps.params and position == 1 then
        if (desc.get("lines") or 8) ~= (t.lines or 8) then
            return false
        end
        if (desc.get("thickness") or 2) ~= (t.thickness or 2) then
            return false
        end
        if (desc.get("speed") or 4) ~= (t.speed or 4) then
            return false
        end
    end
    if caps.bg and position == 1 then
        if (desc.get("bg") == true) ~= (t.bg == true) then
            return false
        end
        -- ApplyTemplate writes the background color too.
        if t.bg then
            local br, bgg, bb = desc.get("bgColor")
            if (br or 0) ~= (t.bgR or 0) or (bgg or 0) ~= (t.bgG or 0) or (bb or 0) ~= (t.bgB or 0) then
                return false
            end
        end
    end
    return true
end

-------------------------------------------------------------------------------
--  BuildIconEffects: the ICON EFFECTS sections of the aura managers (Raid
--  Frames' Debuff Manager, Player Aura Bars): one section per entry of
--  opts.entries, each a Filters dropdown, an Icon Glow, a Border (with its
--  colour) and a Size, with a delete X on its title, then an "Add Icon
--  Effects Per-Filter" link. opts: entries, apply() (after a change),
--  addEntry() (appends an empty entry), filters(region, entry) (builds the
--  Filters dropdown), borderCfg(entry) (optional: a Border row to use instead
--  of the 0-4 slider), sizeMax (default 80), fontKey (default "options").
--  Returns the y below the link.
-------------------------------------------------------------------------------
function CludesUI.BuildIconEffects(widget, sy, opts)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PP or CludesUI.PanelPP
    if not (W and Pix) then
        return sy
    end
    local hh
    local MEDIA_MP = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    local entries = opts.entries

    local GO = CludesUI.GlowOptions

    -- One "ICON EFFECTS" section block per list entry.
    for bi = 1, #entries do
        local e = entries[bi]
        if not e.filters then
            e.filters = {}
        end

        local hdrRgn
        hdrRgn, hh = W:SectionHeader(widget, "ICON EFFECTS", sy)
        sy = sy - hh
        -- Remove X right after the section title text
        if hdrRgn then
            local del = CreateFrame("Button", nil, hdrRgn)
            del:SetSize(14, 14)
            if hdrRgn._label then
                del:SetPoint("LEFT", hdrRgn._label, "RIGHT", 8, 0)
            else
                del:SetPoint("BOTTOMRIGHT", hdrRgn, "BOTTOMRIGHT", 0, 6)
            end
            del:SetFrameLevel(hdrRgn:GetFrameLevel() + 2)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_MP .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            local blockIdx = bi
            del:SetScript("OnClick", function()
                table.remove(entries, blockIdx)
                opts.apply()
                CludesUI:RefreshPage(true)
            end)
        end

        -- Row 1: Filters | Icon Glow (shared glow controls)
        local glowDesc = GO.PrefixSite(function()
            return e
        end, "glow", "engine", opts.apply)
        -- The half next to Filters is too narrow for the color swatches.
        glowDesc.colorInCog = true
        local row
        row, hh = W:DualRow(widget, sy, {
            type = "dropdown",
            text = "Filters",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, GO.DropdownSpec(glowDesc, "Icon Glow"))
        sy = sy - hh
        opts.filters(row._leftRegion, e)
        GO.AttachInline(row._rightRegion, glowDesc)

        -- Row 2: Border (+ swatch, the DISPLAY-section Border style) | Size
        -- (icon size for the matched filters; 0 = the grid's own size).
        local bRow
        bRow, hh = W:DualRow(widget, sy, (opts.borderCfg and opts.borderCfg(e)) or {
            type = "slider",
            text = "Border",
            min = 0,
            max = 4,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return e.borderSize or 0
            end,
            setValue = function(val)
                e.borderSize = val
                opts.apply()
            end,
        }, {
            type = "slider",
            text = "Size",
            min = 0,
            max = opts.sizeMax or 80,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return e.size or 0
            end,
            setValue = function(val)
                e.size = (val and val > 0) and val or nil
                opts.apply()
            end,
        })
        sy = sy - hh
        do
            local region = bRow._leftRegion
            local swatch = CludesUI.BuildColorSwatch(region, bRow:GetFrameLevel() + 3, function()
                local c = e.borderColor or { r = 0, g = 0, b = 0 }
                return c.r or 0, c.g or 0, c.b or 0, 1
            end, function(r, g, b)
                e.borderColor = { r = r, g = g, b = b }
                opts.apply()
            end, false, 20)
            swatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
            region._lastInline = swatch
        end
    end

    -- "Add Icon Effects Per-Filter" accent text link (centered)
    do
        local ar, ag, ab = 1, 0.82, 0.30
        if CludesUI.GetAccentColor then
            ar, ag, ab = CludesUI.GetAccentColor()
        end
        local addBtn = CreateFrame("Button", nil, widget)
        addBtn:SetHeight(22)
        addBtn:SetPoint("TOP", widget, "TOP", 0, sy - 17)
        addBtn:SetFrameLevel(widget:GetFrameLevel() + 2)
        local labelFS = addBtn:CreateFontString(nil, "OVERLAY")
        local fp = (CludesUI.GetFontPath(opts.fontKey or "options")) or "Fonts\\FRIZQT__.TTF"
        labelFS:SetFont(fp, 16, "")
        labelFS:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        labelFS:SetText(CludesUI.L("Add Icon Effects Per-Filter"))
        labelFS:SetTextColor(ar, ag, ab)
        labelFS:SetAlpha(0.9)
        addBtn:SetWidth(labelFS:GetStringWidth() + 8)
        addBtn:SetScript("OnEnter", function()
            labelFS:SetAlpha(1)
        end)
        addBtn:SetScript("OnLeave", function()
            labelFS:SetAlpha(0.9)
        end)
        addBtn:SetScript("OnClick", function()
            opts.addEntry()
            CludesUI:RefreshPage(true)
        end)
        sy = sy - 17 - 22 - 8
    end
    return sy
end

-------------------------------------------------------------------------------
--  BuildFilterSidebar: the filter list down the right of the aura managers'
--  filter editors (Raid Frames' Buff Manager, Player Aura Bars): a row per
--  filter (accent bar and wash on the selected one; delete and rename icons
--  on every filter but a protected preset) and an Add Filter button. opts:
--  selected (the selected filter's id), onPick(id) (a row clicked),
--  onAdded(id) (a filter added), delete(id), rename(id, text), add(name) ->
--  the new filter, deleteMessage, renamePlaceholder(filter), apply() (after
--  a delete), rebuild() (the editor drawn again), input(popupOpts) (the
--  editor's text-input popup), accent ({ r, g, b }). Returns the scroll
--  frame, its child and the y below the last row.
-------------------------------------------------------------------------------
function CludesUI.BuildFilterSidebar(side, sideW, filters, opts)
    local MEDIA_FE = "Interface\\AddOns\\CludesUI\\media\\icons\\"
    local eg = opts.accent
    local sideScroll = CreateFrame("ScrollFrame", nil, side)
    sideScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -1)
    sideScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -1, 1)
    sideScroll:SetFrameLevel(side:GetFrameLevel() + 1)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetWidth(sideW - 2)
    sideScroll:SetScrollChild(sideChild)

    local fy = -4
    for idx = 1, #filters do
        local f = filters[idx]
        local isSel = (opts.selected == f.id)
        local frow = CreateFrame("Button", nil, sideChild)
        frow:SetHeight(26)
        frow:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, fy)
        frow:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, fy)
        frow:SetFrameLevel(sideChild:GetFrameLevel() + 1)
        local rbg = frow:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        local rl = CludesUI.MakeFont(frow, 12, nil, 1, 1, 1)
        rl:SetAlpha(isSel and 0.95 or 0.6)
        rl:SetPoint("LEFT", frow, "LEFT", 10, 0)
        rl:SetPoint("RIGHT", frow, "RIGHT", f.preset and -8 or -42, 0)
        rl:SetJustifyH("LEFT")
        rl:SetWordWrap(false)
        rl:SetText(CludesUI.L(f.name) or f.name)
        if isSel then
            local accent = frow:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, 26)
            accent:SetPoint("TOPLEFT", frow, "TOPLEFT", 0, 0)
            accent:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
        end
        frow:SetScript("OnEnter", function()
            if not isSel then
                rbg:SetColorTexture(1, 1, 1, 0.04)
            end
        end)
        frow:SetScript("OnLeave", function()
            rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        end)
        frow:SetScript("OnClick", function()
            opts.onPick(f.id)
            opts.rebuild()
        end)
        if not f.preset then
            -- Inline X (delete) + pencil (rename) -- the CDM preset-menu
            -- inline-button pattern (cui-close / cui-edit at 14px).
            local del = CreateFrame("Button", nil, frow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", frow, "RIGHT", -6, 0)
            del:SetFrameLevel(frow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_FE .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            del:SetScript("OnClick", function()
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Delete Filter"),
                    message = CludesUI.L(opts.deleteMessage),
                    confirmText = CludesUI.L("Delete"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function()
                        opts.delete(f.id)
                        opts.apply()
                        opts.rebuild()
                    end,
                })
            end)

            local edit = CreateFrame("Button", nil, frow)
            edit:SetSize(14, 14)
            edit:SetPoint("RIGHT", del, "LEFT", -4, 0)
            edit:SetFrameLevel(frow:GetFrameLevel() + 1)
            edit:SetAlpha(0.5)
            local ex = edit:CreateTexture(nil, "OVERLAY")
            ex:SetAllPoints()
            if ex.SetSnapToPixelGrid then
                ex:SetSnapToPixelGrid(false)
                ex:SetTexelSnappingBias(0)
            end
            ex:SetTexture(MEDIA_FE .. "cui-edit.png")
            edit:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Edit"))
            end)
            edit:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            edit:SetScript("OnClick", function()
                opts.input({
                    title = CludesUI.L("Rename Filter"),
                    placeholder = opts.renamePlaceholder(f),
                    confirmText = CludesUI.L("Rename"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function(textValue)
                        opts.rename(f.id, textValue)
                        opts.rebuild()
                    end,
                })
            end)
        end
        fy = fy - 27
    end
    local addFilterBtn = CludesUI.BuildPopupButton(sideChild, sideW - 16, 26, "Add Filter", function()
        opts.input({
            title = CludesUI.L("Add Filter"),
            message = CludesUI.L("Name the new filter."),
            confirmText = CludesUI.L("Add"),
            cancelText = CludesUI.L("Cancel"),
            onConfirm = function(textValue)
                local f = opts.add((textValue and textValue ~= "" and textValue) or CludesUI.L("New Filter"))
                if f then
                    opts.onAdded(f.id)
                end
                opts.rebuild()
            end,
        })
    end)
    addFilterBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, fy - 8)
    return sideScroll, sideChild, fy
end

-------------------------------------------------------------------------------
--  BuildFilterEditorShell: the window of an aura manager's filter editor: a
--  dimmer over the screen (a click on it closes the editor), the dialog
--  (width x height, at the popup scale) titled Edit Filters, a close X, and
--  Escape closing the editor alone. The editor is kept on owner[slot] while
--  shown; keepKey names the one kept frame the pool dresses again on every
--  open. Returns the dimmer and the dialog.
-------------------------------------------------------------------------------
function CludesUI.BuildFilterEditorShell(owner, slot, keepKey, width, height)
    local PoolKept, PoolOwned = CludesUI._Pool.Kept, CludesUI._Pool.Owned
    local dimmer = PoolKept(owner, keepKey, "Frame", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    -- Clicking off the popup closes the editor (the popup is mouse-enabled,
    -- so clicks on it never reach the dimmer).
    dimmer:SetScript("OnMouseDown", function()
        dimmer:Hide()
        owner[slot] = nil
    end)
    local dimTex = CludesUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()
    owner[slot] = dimmer

    local dialog = CreateFrame("Frame", nil, dimmer)
    dialog:SetSize(width, height)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    dialog:EnableMouse(true)
    local popBg = CludesUI.SolidTex(dialog, "BACKGROUND", 0.062, 0.070, 0.082, 1)
    popBg:SetAllPoints()
    CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, popBg)
    dialog:SetScale((CludesUI.GetPopupScale and CludesUI.GetPopupScale()) or 1)

    local title = CludesUI.MakeFont(dialog, 16, "", 1, 1, 1)
    title:SetPoint("TOP", dialog, "TOP", 0, -18)
    title:SetText(CludesUI.L("Edit Filters"))

    -- Close button (top-right): the borderless X (the boxed close-popup
    -- variant reads as a framed button here).
    do
        local close = CreateFrame("Button", nil, dialog)
        close:SetSize(19, 19)
        close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -13, -8)
        close:SetFrameLevel(dialog:GetFrameLevel() + 5)
        local closeIcon = close:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAllPoints()
        closeIcon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
        closeIcon:SetAlpha(0.40)
        closeIcon:SetSnapToPixelGrid(false)
        closeIcon:SetTexelSnappingBias(0)
        close:SetScript("OnEnter", function()
            closeIcon:SetAlpha(0.50)
        end)
        close:SetScript("OnLeave", function()
            closeIcon:SetAlpha(0.40)
        end)
        close:SetScript("OnClick", function()
            dimmer:Hide()
            owner[slot] = nil
        end)
    end

    -- Escape closes the editor alone: the key is swallowed here, so it never
    -- reaches the Escape proxy that would close the options window too.
    -- SetPropagateKeyboardInput is protected in combat, so the editor takes
    -- the keyboard only when built out of combat and stands aside in it. The
    -- capture is a frame of its own, owned by the popup outside its child
    -- list: a dress in combat cannot clear keyboard flags, so it leaves only
    -- that frame for the next dress out of combat, never the popup.
    if not InCombatLockdown() then
        local keyList = PoolOwned(dialog, "keys", "Frame", dialog)
        keyList:SetAllPoints(dialog)
        keyList:EnableKeyboard(true)
        keyList:SetPropagateKeyboardInput(true)
        keyList:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then
                return
            end
            self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then
                dimmer:Hide()
                owner[slot] = nil
            end
        end)
    end
    return dimmer, dialog
end

-------------------------------------------------------------------------------
--  BuildFilterSpellList: the spell checklist of the aura managers' filter
--  editors. lead is a list of { title, ids } groups drawn first, then one
--  class-coloured group per token of classOrder that byClass holds ids for;
--  empty groups are skipped. opts: spells (id -> on), label(id) (the spell's
--  name, or nil), removable(id), set(id, value) (writes and applies a toggle,
--  or a removal with nil), rebuild() (after a removal), emptyText, accent.
--  Toggles repaint the row in place, so the list keeps its scroll position.
--  Sizes child to fit.
-------------------------------------------------------------------------------
function CludesUI.BuildFilterSpellList(child, lead, byClass, classOrder, opts)
    local MEDIA_FE = "Interface\\AddOns\\CludesUI\\media\\icons\\"
    local eg, spells = opts.accent, opts.spells
    local y = 0

    local function Heading(text)
        local heading = CludesUI.MakeFont(child, 14, nil, 0.5, 0.5, 0.5)
        heading:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y - 10)
        heading:SetText(text)
        local rule = child:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetPoint("LEFT", heading, "RIGHT", 6, 0)
        rule:SetPoint("RIGHT", child, "RIGHT", -10, 0)
        rule:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        y = y - 30
    end

    local function RemoveButton(row, id)
        local del = CreateFrame("Button", nil, row)
        del:SetSize(14, 14)
        del:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        del:SetFrameLevel(row:GetFrameLevel() + 1)
        del:SetAlpha(0.5)
        local cross = del:CreateTexture(nil, "OVERLAY")
        cross:SetAllPoints()
        if cross.SetSnapToPixelGrid then
            cross:SetSnapToPixelGrid(false)
            cross:SetTexelSnappingBias(0)
        end
        cross:SetTexture(MEDIA_FE .. "cui-close.png")
        del:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
        end)
        del:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
        end)
        del:SetScript("OnClick", function()
            opts.set(id, nil)
            opts.rebuild()
        end)
    end

    local function Row(id, tint)
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 2, y)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", -2, y)
        row:SetFrameLevel(child:GetFrameLevel() + 1)
        local wash = row:CreateTexture(nil, "ARTWORK")
        wash:SetAllPoints()
        wash:SetColorTexture(1, 1, 1, 0)
        local box = CreateFrame("Frame", nil, row)
        box:SetSize(16, 16)
        box:SetPoint("LEFT", row, "LEFT", 6, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        local border = CludesUI.MakeRoundedBorder(box, 0.4, 0.4, 0.4, 0.6, boxBg)
        local fill = box:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        fill:SetColorTexture(eg.r, eg.g, eg.b, 1)
        CludesUI.RoundBody(box, fill, 2)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("LEFT", box, "RIGHT", 6, 0)
        local art = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
        if art then
            icon:SetTexture(art)
        end
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local canRemove = opts.removable(id)
        local label =
            CludesUI.MakeFont(row, 13, nil, tint and tint.r or 1, tint and tint.g or 1, tint and tint.b or 1)
        label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        label:SetPoint("RIGHT", row, "RIGHT", canRemove and -24 or -6, 0)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(opts.label(id) or ("Spell " .. tostring(id)))

        local on
        local function Paint()
            on = spells[id] and true or false
            if on then
                fill:Show()
            else
                fill:Hide()
            end
            if border and border.SetColor then
                if on then
                    border:SetColor(eg.r, eg.g, eg.b, 0.8)
                else
                    border:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
            label:SetAlpha(on and 0.9 or 0.45)
            icon:SetAlpha(on and 1 or 0.45)
            icon:SetDesaturated(not on)
        end
        Paint()
        row:SetScript("OnEnter", function()
            wash:SetColorTexture(1, 1, 1, 0.04)
        end)
        row:SetScript("OnLeave", function()
            wash:SetColorTexture(1, 1, 1, 0)
        end)
        row:SetScript("OnClick", function()
            opts.set(id, not on)
            Paint()
        end)
        if canRemove then
            RemoveButton(row, id)
        end
        y = y - 29
    end

    local function Group(title, ids, tint)
        if ids and #ids > 0 then
            Heading(title)
            for idx = 1, #ids do
                Row(ids[idx], tint)
            end
        end
    end

    for idx = 1, #lead do
        Group(lead[idx][1], lead[idx][2])
    end
    for idx = 1, #classOrder do
        local token = classOrder[idx]
        local ids = byClass[token]
        if ids and #ids > 0 then
            local tint = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            local title = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[token] or token
            Group(tint and ("|c" .. tint.colorStr .. title .. "|r") or title, ids, tint)
        end
    end
    if y == 0 then
        local empty = CludesUI.MakeFont(child, 12, nil, 1, 1, 1)
        empty:SetAlpha(0.4)
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -6)
        empty:SetText(opts.emptyText)
        y = -30
    end
    child:SetHeight(math.abs(y) + 10)
end

-------------------------------------------------------------------------------
--  BuildFilterDetail: the left pane of the aura managers' filter editors for
--  the selected filter sel: its name (with a Rename link unless it is a
--  preset), the Search Spells dropdown, the Add Spell ID button and the
--  scroll frame the spell checklist goes in. opts: searchIds() (ids the
--  search offers), label(id) (a spell's name, or nil), addPicked(id) and
--  addTyped(id) (true when the spell was added), rename(id, text),
--  renamePlaceholder, apply(), rebuild(), input(popupOpts). Returns the pane,
--  the scroll frame and its child.
-------------------------------------------------------------------------------
function CludesUI.BuildFilterDetail(dialog, sideW, popupW, sel, opts)
    local L = CludesUI.L
    local ar, ag, ab = 1, 0.82, 0.30
    if CludesUI.GetAccentColor then
        ar, ag, ab = CludesUI.GetAccentColor()
    end
    local function Added(ok)
        if ok then
            opts.apply()
            opts.rebuild()
        end
    end

    local pane = CreateFrame("Frame", nil, dialog)
    pane:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -44)
    pane:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -(sideW + 12), 12)
    pane:SetFrameLevel(dialog:GetFrameLevel() + 1)

    local title = CludesUI.MakeFont(pane, 13, nil, 1, 1, 1)
    title:SetAlpha(0.9)
    title:SetPoint("TOPLEFT", pane, "TOPLEFT", 2, -2)
    title:SetText(L(sel.name))
    if not sel.preset then
        local link = CreateFrame("Button", nil, pane)
        link:SetSize(54, 16)
        link:SetPoint("LEFT", title, "RIGHT", 10, 0)
        link:SetFrameLevel(pane:GetFrameLevel() + 2)
        local text = CludesUI.MakeFont(link, 11, nil, ar, ag, ab)
        text:SetAlpha(0.9)
        text:SetPoint("LEFT")
        text:SetText(L("Rename"))
        link:SetScript("OnEnter", function()
            text:SetAlpha(1)
        end)
        link:SetScript("OnLeave", function()
            text:SetAlpha(0.9)
        end)
        link:SetScript("OnClick", function()
            opts.input({
                title = L("Rename Filter"),
                placeholder = opts.renamePlaceholder,
                confirmText = L("Rename"),
                cancelText = L("Cancel"),
                onConfirm = function(textValue)
                    opts.rename(sel.id, textValue)
                    opts.rebuild()
                end,
            })
        end)
    end

    -- Search Spells: an action list (nothing in it is ever checked); a pick
    -- adds the spell and the editor is drawn again without it.
    local function SearchItems()
        local ids, items = opts.searchIds(), {}
        for idx = 1, #ids do
            local id = ids[idx]
            items[#items + 1] = {
                key = id,
                label = opts.label(id) or tostring(id),
                noCheck = true,
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id),
            }
        end
        table.sort(items, function(a, b)
            return tostring(a.label or a.key) < tostring(b.label or b.key)
        end)
        return items
    end
    local search = CludesUI.BuildVisOptsCBDropdown(
        pane,
        170,
        pane:GetFrameLevel() + 5,
        SearchItems,
        function()
            return false
        end,
        function(id, picked)
            if picked then
                Added(opts.addPicked(id))
            end
        end,
        nil,
        10,
        true
    )
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", pane, "TOPLEFT", 2, -23)
    -- One-shot title: a checkbox dropdown's checked-count summary ("None")
    -- reads wrong for a search, and every add draws the editor again.
    for _, region in ipairs({ search:GetRegions() }) do
        if region.SetText and region.GetText then
            region:SetText(L("Search Spells"))
            break
        end
    end

    local addId = CludesUI.BuildPopupButton(pane, 110, 24, "Add Spell ID", function()
        opts.input({
            title = L("Add Spell ID"),
            message = L("Enter the spell ID to add to this filter."),
            confirmText = L("Add"),
            cancelText = L("Cancel"),
            onConfirm = function(textValue)
                local id = tonumber(textValue or "")
                if id then
                    Added(opts.addTyped(id))
                end
            end,
        })
    end)
    addId:SetPoint("LEFT", search, "RIGHT", 8, 0)

    local scroll = CreateFrame("ScrollFrame", nil, pane)
    scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(popupW - sideW - 40)
    scroll:SetScrollChild(child)
    return pane, scroll, child
end
