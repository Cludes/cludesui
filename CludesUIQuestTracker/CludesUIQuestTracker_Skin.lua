if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CludesUIQuestTracker_Skin.lua
--
-- Restyles Blizzard's ObjectiveTrackerFrame sub-trackers (headers, blocks,
-- progress bars, timer bars) via hooks only. Never SetScript on any tracker
-- frame; HookScript only. No frame-tree recursion.
--
-- Styling targets (match the legacy custom tracker exactly):
--   title color      = { r=1.00, g=0.91, b=0.47 }  gold
--   objective color  = { r=0.72, g=0.72, b=0.72 }  gray
--   completed color  = { r=0.25, g=1.00, b=0.35 }  green
--   section accent   = live CludesUI.CLUDES_GREEN
--   bar bg           = { r=0.15, g=0.15, b=0.15 } at 0.8 alpha
--   bar fill         = accent tint on Blizzard's default statusbar texture
--   timer fill       = { r=1.00, g=0.82, b=0.20 }
--   timer low fill   = { r=1.00, g=0.30, b=0.30 }
--   font             = CludesUI.GetFontPath("unitFrames")
--   shadow / outline = CludesUI.GetFontUseShadow / GetFontOutlineFlag
--   border           = PanelPP.CreateBorder 1px black, physical pixel perfect
-------------------------------------------------------------------------------
local _, mod = ...
local TrackerNS = mod.EQT

-- External weak-keyed table for block skin state (never write custom keys
-- onto Blizzard pool frames -- causes taint).
local _skinned = setmetatable({}, { __mode = "k" })

-- Stock styles (Blizzard Style / Classic WoW UI), latched once in InitSkin.
-- STOCK keeps Blizzard's own tracker art, fonts and POI icons: the skin passes
-- stand down and only the behaviour (visibility, click sinks, click-anywhere
-- headers, QoL) runs. Both stock styles draw the tracker the same way
-- (Blizzard's header bars included); CLASSIC only keeps its gold header
-- colour for any remaining GetHeaderRGB reader.
local STOCK, CLASSIC = false, false

-- Blizzard's native quest POI icons instead of our classified icons: the
-- user's toggle, or forced by either stock style.
local function StockIconsOn() return STOCK or TrackerNS.Cfg("showQuestIcons") end

-- Color helpers. All four user-facing text colors come from DB so they
-- follow the Colors section in the options page.
local function GetTitleRGB()
    local cfg = TrackerNS.DB()
    return cfg.titleR or 1.0, cfg.titleG or 0.910, cfg.titleB or 0.471
end
local function GetCompletedRGB()
    local cfg = TrackerNS.DB()
    return cfg.completedR or 0.251, cfg.completedG or 1.0, cfg.completedB or 0.349
end
local function GetFocusRGB()
    local cfg = TrackerNS.DB()
    return cfg.focusR or 0.871, cfg.focusG or 0.251, cfg.focusB or 1.0
end
local SUB_TRACKERS = {
    "ScenarioObjectiveTracker",
    "UIWidgetObjectiveTracker",
    "CampaignQuestObjectiveTracker",
    "QuestObjectiveTracker",
    "AdventureObjectiveTracker",
    "AchievementObjectiveTracker",
    "MonthlyActivitiesObjectiveTracker",
    "ProfessionsRecipeTracker",
    "BonusObjectiveTracker",
    "WorldQuestObjectiveTracker",
    "InitiativeTasksObjectiveTracker",
}

-- ScenarioObjectiveTracker and UIWidgetObjectiveTracker render their content through
-- Blizzard's shared UI-widget pool -- the same pool GameTooltip and AreaPOI tooltips
-- draw from. ANY method call on their child blocks taints that pool, and the taint
-- surfaces later as "attempt to compare a secret number value" in LayoutFrame.lua when
-- a tooltip lays out a widget set (e.g. hovering an AreaPOI on the world map). We only
-- ever skin their headers; block-level loops must skip them entirely.
local function SharesWidgetPool(trackerFrame)
    return trackerFrame == _G.ScenarioObjectiveTracker or trackerFrame == _G.UIWidgetObjectiveTracker
end

-- Shared font sizes -- read from DB so the options panel can tweak them.
-- Defaults are seeded in the loader's QT_DEFAULTS table.
local function GetTitleSize() return TrackerNS.Cfg("titleFontSize") or 13 end
local function GetObjSize() return TrackerNS.Cfg("objectiveFontSize") or 11 end
local function GetHeaderSize() return TrackerNS.Cfg("headerFontSize") or 13 end

-------------------------------------------------------------------------------
-- External weak-keyed flag tables. Never write custom fields onto Blizzard-
-- owned tables: the tracker iterates its own data tables (e.g. tracker.blocks
-- keyed by blockID) with pairs(), and any stray key becomes a "fake entry"
-- that breaks their MarkBlocksUnused logic. All idempotency flags live here.
-------------------------------------------------------------------------------
local _hookedTrackers = setmetatable({}, { __mode = "k" })
local _hookedBlocks = setmetatable({}, { __mode = "k" })
local _blockIcons = setmetatable({}, { __mode = "k" }) -- block -> our icon texture

-- External weak-keyed flag tables. Every "am I in a state?" bool / number
-- we used to write directly onto Blizzard-owned frames (block, tracker,
-- line, FontString, StatusBar, bar, etc.) lives here instead so Blizzard's
-- iteration of its own tables never sees our additions. This is the
-- canonical taint-avoidance pattern per CLAUDE.md.
local _blockFocus = setmetatable({}, { __mode = "k" }) -- block -> focus texture
local _masterHeaderCollapseHooked = false -- guards the SetCollapsed re-skin hook below

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function GetAccent()
    local eg = CludesUI and CludesUI.CLUDES_GREEN
    if eg then return eg.r, eg.g, eg.b end
    return 0.298, 0.788, 0.941
end

-- Player class color, via the shared CludesUI.GetClassColor() cache.
-- Falls back to white if the player's class token isn't known yet.
local function GetClassColorRGB()
    local cc = CludesUI and CludesUI._playerClass and CludesUI.GetClassColor(CludesUI._playerClass)
    if cc then return cc.r, cc.g, cc.b end
    return 1.0, 1.0, 1.0
end

-- Header text + minimize-button color, user-adjustable via the "Header
-- Color" swatch in Colors options: Class Color / Custom Color / Accent
-- Color. Applies uniformly to every header (the master "All Objectives"
-- header and every per-section header alike). Defaults to Accent Color
-- (headerUseAccent is treated as true unless explicitly set to false).
local function GetHeaderRGB()
    if CLASSIC then
        local num = _G.NORMAL_FONT_COLOR
        if num then return num.r, num.g, num.b end
        return 1.0, 0.82, 0.0
    end
    local cfg = TrackerNS.DB()
    if cfg.headerShowClassColor then return GetClassColorRGB() end
    if cfg.headerUseAccent ~= false then return GetAccent() end
    return cfg.headerR or 1.0, cfg.headerG or 1.0, cfg.headerB or 1.0
end

-- Section-divider line color, user-adjustable via the "Line Color" swatch in Colors
-- options: Class Color / Custom Color / Accent Color. Defaults to Accent Color
-- (lineUseAccent is treated as true unless explicitly set to false).
local function GetLineRGB()
    local cfg = TrackerNS.DB()
    if cfg.lineShowClassColor then return GetClassColorRGB() end
    if cfg.lineUseAccent ~= false then return GetAccent() end
    return cfg.lineR or 1.0, cfg.lineG or 1.0, cfg.lineB or 1.0
end

local function GetFont()
    local saved = _G._CUQT_DB
    local fontKey = saved and saved.profile and saved.profile.questTracker and saved.profile.questTracker.font
    if fontKey and fontKey ~= "__global" then
        if CludesUI and CludesUI.ResolveFontName then
            return CludesUI.ResolveFontName(fontKey) or "Fonts/FRIZQT__.TTF"
        end
    end
    if CludesUI and CludesUI.GetFontPath then
        return CludesUI.GetFontPath("questTracker") or "Fonts/FRIZQT__.TTF"
    end
    return "Fonts/FRIZQT__.TTF"
end

local function ApplyShadow(fontStr)
    if not fontStr then return end
    local useShadow = (CludesUI.GetFontUseShadow("questTracker")) and true or false
    -- 12.0.7: instance shadows no longer render; shadow must ride a FontObject.
    -- These are Blizzard objective-tracker strings, so capture and restore the
    -- current font face around PrimeFontShadow to preserve Blizzard's typeface.
    local _pf, _ps, _pfl = fontStr:GetFont()
    CludesUI.PrimeFontShadow(fontStr, useShadow)
    if _pf then fontStr:SetFont(_pf, _ps, _pfl) end
end

-- Registry of every FontString we've styled. Lets us re-template in bulk
-- when the user changes font path / outline / shadow settings.
local _eqtFontRegistry = setmetatable({}, { __mode = "k" })

-- Reapplies CUI font path with explicit size + outline + shadow.
-- If `size` is nil, preserves Blizzard's current size.
local function StyleFontStringSized(fontStr, size)
    if STOCK or not fontStr or not fontStr.GetFont then return end
    if not size then
        local _, current = fontStr:GetFont()
        size = current or 12
    end
    local success =
        pcall(fontStr.SetFont, fontStr, GetFont(), size, CludesUI.GetFontOutlineFlag("questTracker"))
    if not success then
        fontStr:SetFont("Fonts/FRIZQT__.TTF", size, CludesUI.GetFontOutlineFlag("questTracker"))
    end
    ApplyShadow(fontStr)
    _eqtFontRegistry[fontStr] = true
end

-- Convenience wrappers so every title / objective uses the shared sizes.
local function StyleFontString(fontStr) StyleFontStringSized(fontStr, nil) end
local function StyleTitleFS(fontStr) StyleFontStringSized(fontStr, GetTitleSize()) end
local function StyleObjectiveFS(fontStr) StyleFontStringSized(fontStr, GetObjSize()) end
local function StyleHeaderFS(fontStr) StyleFontStringSized(fontStr, GetHeaderSize()) end

-- Walk every FontString region on a frame (top-level only) and restyle it.
-- No recursion: child frames each go through their own skin call.
local function StyleAllFontStrings(widget)
    if not widget or not widget.GetRegions then return end
    for _, regionFrame in ipairs({ widget:GetRegions() }) do
        if regionFrame and regionFrame:GetObjectType() == "FontString" then StyleFontString(regionFrame) end
    end
end

-- Bulk re-template everything we've touched. Called when user changes font
-- settings in options.
function TrackerNS.RefreshFonts()
    for fontStr in pairs(_eqtFontRegistry) do
        if fontStr and fontStr.GetFont then
            local _, size = fontStr:GetFont()
            pcall(
                fontStr.SetFont,
                fontStr,
                GetFont(),
                size or 12,
                CludesUI.GetFontOutlineFlag("questTracker")
            )
            ApplyShadow(fontStr)
        end
    end
end

-- FORBIDDEN: calling ObjectiveTrackerFrame:Update() from addon execution,
-- in ANY shape -- synchronous, deferred via C_Timer, or combat-gated with a
-- regen retry. A forced Update() runs Blizzard's entire quest machinery in
-- our (tainted) execution context, and the Lua tables that machinery
-- materializes are served to secure code for the rest of the session:
-- QuestEventListener callback tables, cached quest/task/mapInfo tables, and structural
-- writes on the world map's data-provider objects. Secure map code reading any of them
-- turns tainted mid-flight, which surfaces as "blocked in combat ...
-- SetPassThroughButtons()" on every map pin refresh and secret-number compare errors in
-- tooltip layout. Field taint logs from two testers (2026-07-18) confirmed this end to
-- end; deferral does NOT launder taint (taint is execution-context, not call ancestry).
--
-- Consequence we accept instead: after a font-size change or a focus
-- change, Blizzard's cached block heights can be briefly stale (overlapping
-- text) until its next natural relayout (any quest event). Cosmetic and
-- self-healing; never reintroduce a forced Update() to fix it.

-- Physical-pixel-perfect 1px accent divider under each section header. Parented to
-- ObjectiveTrackerFrame (NOT the header) so collapse/expand animations on the header
-- don't drag our divider with them. Keyed by header so we only create one per section
-- (Quests, Professions, etc). Follows the canonical border pattern: DisablePixelSnap +
-- SetHeight via PP.perfect / effectiveScale.
local _headerDividers = setmetatable({}, { __mode = "k" })
local function EnsureAccentDivider(headerFrame)
    if STOCK or not headerFrame or not headerFrame.CreateTexture then return nil end
    local objectiveTracker = _G.ObjectiveTrackerFrame
    if not objectiveTracker or not objectiveTracker.CreateTexture then return nil end

    local isMasterHeader = (
        headerFrame == objectiveTracker.HeaderMenu or headerFrame == objectiveTracker.Header
    )

    -- Divider is visible only when the tracker itself is currently being
    -- rendered (Blizzard hides the tracker frame when it has no content). The
    -- master header is suppressed with alpha rather than Hide(), so an alpha-0
    -- header counts as not rendered too -- see ApplyMasterHeaderVisibility.
    local headerShown = headerFrame.IsShown
        and headerFrame:IsShown()
        and (not headerFrame.GetAlpha or headerFrame:GetAlpha() > 0)
    local isActive

    if isMasterHeader then
        -- The master header's own IsShown() already reflects whether the
        -- tracker has any module to display (Blizzard's
        -- ObjectiveTrackerFrameMixin:Update -> ShouldShowHeader(), verified
        -- against Gethe/wow-ui-source), so no block-scan is needed here.
        isActive = headerShown and objectiveTracker:IsShown()
    else
        -- Signals, ORed:
        --   tracker has any block, OR
        --   tracker is flagged as having contents (hasContents), OR
        --   tracker was displayed on the last layout pass (wasDisplayedLastLayout).
        -- Any of those == the section is still active. All false == fully hidden.
        -- Collapse keeps hasContents/wasDisplayedLastLayout true, so collapsed
        -- trackers still show their divider.
        local ownerFrame = headerFrame:GetParent()
        local hasAnyBlock = false
        if ownerFrame and ownerFrame.usedBlocks then
            for _, templateMap in pairs(ownerFrame.usedBlocks) do
                if type(templateMap) == "table" then
                    for _ in pairs(templateMap) do
                        hasAnyBlock = true
                        break
                    end
                    if hasAnyBlock then break end
                end
            end
        end
        -- The divider belongs to a section that is actually rendered. Require
        -- the header itself to be shown right now AND the tracker to have some
        -- current content signal. `wasDisplayedLastLayout` alone isn't enough
        -- because Blizzard doesn't always clear it when a section empties.
        local trackerShown = ownerFrame and ownerFrame.IsShown and ownerFrame:IsShown()
        local hasContentSignal = hasAnyBlock or (ownerFrame and ownerFrame.hasContents)
        isActive = headerShown and trackerShown and hasContentSignal
    end

    if not isActive then
        local texture = _headerDividers[headerFrame]
        if texture then texture:Hide() end
        return nil
    end
    local texture = _headerDividers[headerFrame]
    if not texture then
        texture = objectiveTracker:CreateTexture(nil, "OVERLAY")
        _headerDividers[headerFrame] = texture
    end
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 7, 0)
    texture:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", -1, 0)
    local PP_CORE = CludesUI and CludesUI.PP
    local PP_SEC = CludesUI and CludesUI.PanelPP
    if PP_SEC and PP_SEC.DisablePixelSnap then PP_SEC.DisablePixelSnap(texture) end
    local perfect = (PP_CORE and PP_CORE.perfect) or (PP_SEC and PP_SEC.mult) or 1
    local es = headerFrame.GetEffectiveScale and headerFrame:GetEffectiveScale() or 1
    local onePixel = (es and es > 0) and (perfect / es) or (PP_SEC and PP_SEC.mult) or 1
    texture:SetHeight(onePixel)
    local red, green, blue = GetLineRGB()
    texture:SetColorTexture(red, green, blue, 1)
    texture:Show()
    return texture
end

-------------------------------------------------------------------------------
-- Strip every Texture region on a frame except ones explicitly preserved.
-- Top-level only, never recurses. Leaves FontStrings alone.
-------------------------------------------------------------------------------
local function StripTextures(widget, keepSet)
    if not widget or not widget.GetRegions then return end
    keepSet = keepSet or {}
    -- IMPORTANT: hide via SetTexture("") only. SetTexture(nil) and SetAlpha(0) both
    -- taint Blizzard-owned textures. Tainted widget-pool textures cause arithmetic
    -- errors when the pool reuses them for tooltip/POI widgets later
    -- (Blizzard_UIWidgetTemplateTextWithState textHeight crashes).
    for _, regionFrame in ipairs({ widget:GetRegions() }) do
        if
            regionFrame
            and regionFrame:GetObjectType() == "Texture"
            and not keepSet[regionFrame]
            and regionFrame.SetTexture
        then
            regionFrame:SetTexture("")
        end
    end
end

-------------------------------------------------------------------------------
-- The master "All Objectives" header's MinimizeButton renders with a
-- different atlas than every per-section header's MinimizeButton by
-- default. Verified in-game (2026-07-24, via in-game atlas dump) rather
-- than guessed from source:
--   expanded (shows "-", click collapses)  -> UI-QuestTrackerButton-Secondary-Collapse
--   collapsed (shows "+", click expands)   -> UI-QuestTrackerButton-Secondary-Expand
-- Both confirmed as the atlas QuestObjectiveTracker's MinimizeButton (a known-good,
-- already-flat section header) uses in that state. The "-Pressed" pushed-state suffix
-- is directly confirmed for the expanded atlas and assumed (not separately dumped) for
-- the collapsed one, following that same observed Blizzard naming convention.
-------------------------------------------------------------------------------
local MASTER_MINBTN_ATLAS = {
    [false] = {
        normal = "UI-QuestTrackerButton-Secondary-Collapse",
        pushed = "UI-QuestTrackerButton-Secondary-Collapse-Pressed",
    },
    [true] = {
        normal = "UI-QuestTrackerButton-Secondary-Expand",
        pushed = "UI-QuestTrackerButton-Secondary-Expand-Pressed",
    },
}

local function SyncMasterMinimizeButtonLook(masterBtn, collapsed)
    if not masterBtn then return end
    if collapsed == nil then
        -- No known state (e.g. the very first InitSkin() skin pass, before
        -- any SetCollapsed call has fired) -- "All Objectives" is expanded
        -- by default on login, so assume expanded rather than guess wrong.
        collapsed = false
    end
    local style = MASTER_MINBTN_ATLAS[collapsed]
    if not style then return end
    local num = masterBtn.GetNormalTexture and masterBtn:GetNormalTexture()
    local p = masterBtn.GetPushedTexture and masterBtn:GetPushedTexture()
    if num then num:SetAtlas(style.normal) end
    if p then p:SetAtlas(style.pushed) end
end

-------------------------------------------------------------------------------
-- Header skin: accent color + CUI font. Strips every decorative texture
-- region from the header; keeps the minimize button (+/-) and Text intact.
-------------------------------------------------------------------------------
local function SkinHeader(headerFrame, knownCollapsed)
    if not headerFrame then return end
    if not TrackerNS.Cfg("skinHeaders") then return end

    local minimizeBtn = headerFrame.MinimizeButton
    -- The stock styles (Blizzard Style and Classic WoW UI alike) keep the
    -- header exactly as Blizzard draws it (its header bar art, +/- buttons and
    -- text); only the click-anywhere hit rect below applies.
    if not STOCK then
        -- Named decorative regions we always want gone.
        -- Hide via SetTexture("") only (anti-taint pattern -- see StripTextures).
        for _, k in ipairs({
            "Background",
            "Line",
            "LineSheen",
            "LineGlow",
            "Divider",
            "Sheen",
            "Glow",
            "Stripe",
        }) do
            local region = headerFrame[k]
            if region and region.SetTexture then region:SetTexture("") end
        end

        -- Sweep anonymous Texture regions too. Preserve the minimize button's
        -- textures by skipping anything owned by header.MinimizeButton.
        local objectiveTracker = _G.ObjectiveTrackerFrame
        if
            minimizeBtn
            and objectiveTracker
            and (headerFrame == objectiveTracker.HeaderMenu or headerFrame == objectiveTracker.Header)
        then
            SyncMasterMinimizeButtonLook(minimizeBtn, knownCollapsed)
        end
        local keepSet = {}
        if minimizeBtn and minimizeBtn.GetRegions then
            for _, regionFrame in ipairs({ minimizeBtn:GetRegions() }) do
                keepSet[regionFrame] = true
            end
            if minimizeBtn.GetNormalTexture and minimizeBtn:GetNormalTexture() then
                keepSet[minimizeBtn:GetNormalTexture()] = true
            end
            if minimizeBtn.GetPushedTexture and minimizeBtn:GetPushedTexture() then
                keepSet[minimizeBtn:GetPushedTexture()] = true
            end
            if minimizeBtn.GetHighlightTexture and minimizeBtn:GetHighlightTexture() then
                keepSet[minimizeBtn:GetHighlightTexture()] = true
            end
        end
        StripTextures(headerFrame, keepSet)

        -- Tint the +/- minimize button with the header color. Desaturate
        -- first so the base atlas's built-in tint doesn't multiply with ours.
        if minimizeBtn then
            local red, green, blue = GetHeaderRGB()
            local function tint(texture)
                if not texture then return end
                if texture.SetDesaturated then texture:SetDesaturated(true) end
                if texture.SetVertexColor then texture:SetVertexColor(red, green, blue) end
            end
            tint(minimizeBtn.GetNormalTexture and minimizeBtn:GetNormalTexture())
            tint(minimizeBtn.GetPushedTexture and minimizeBtn:GetPushedTexture())
            tint(minimizeBtn.GetHighlightTexture and minimizeBtn:GetHighlightTexture())
            tint(minimizeBtn.GetDisabledTexture and minimizeBtn:GetDisabledTexture())
            if minimizeBtn.GetRegions then
                for _, regionTex in ipairs({ minimizeBtn:GetRegions() }) do
                    if regionTex:GetObjectType() == "Texture" then tint(regionTex) end
                end
            end
            -- WoW Forever's filter toggle beside it (nil on retail).
            local toggle = TrackerNS.FilterToggle
            if toggle and toggle:GetParent() == headerFrame then
                tint(toggle:GetNormalTexture())
                tint(toggle:GetPushedTexture())
                tint(toggle:GetHighlightTexture())
            end
        end

        if not STOCK then
            local textValue = headerFrame.Text
            if textValue then
                local red, green, blue = GetHeaderRGB()
                textValue:SetTextColor(red, green, blue)
                StyleHeaderFS(textValue)
            end

            -- Catch any other FontString regions on the header (subtitle, count text).
            StyleAllFontStrings(headerFrame)

            -- 1px divider beneath the header (Line Color: Class / Custom / Accent).
            EnsureAccentDivider(headerFrame)
        end -- not STOCK
    end -- not STOCK (outer)

    -- Click-anywhere-on-header: widen the NATIVE MinimizeButton's hit rect
    -- across the header, so a title click dispatches straight to Blizzard's
    -- own OnClick -- the identical path a bare +/- press takes.
    -- HARD RULE: no addon code may run in this click path. Forwarding via an
    -- overlay's Click() ran the collapse cascade from our execution and
    -- tainted the container's shared dispatch loop -- a field-confirmed
    -- injector (secret-aura GetAuraDataByIndex errors out of LayoutContents),
    -- and the taint survives zone changes, so combat/instance gating cannot
    -- close it. Do not reintroduce any overlay or click redirect here without
    -- fresh taint-log evidence. Blizzard never calls SetHitRectInsets on
    -- these buttons (source-verified), and the header frame is not
    -- mouse-enabled, so nothing fights or swallows this.
    if minimizeBtn and minimizeBtn.SetHitRectInsets then
        local headerW = headerFrame.GetWidth and headerFrame:GetWidth() or 0
        local headerH = headerFrame.GetHeight and headerFrame:GetHeight() or 0
        local btnW = minimizeBtn.GetWidth and minimizeBtn:GetWidth() or 0
        local btnH = minimizeBtn.GetHeight and minimizeBtn:GetHeight() or 0
        if headerW > 0 and btnW > 0 then
            -- Reserve the FilterButton's width while it is showing (master
            -- header only, hidden by default; anchored 2px left of the
            -- MinimizeButton). The widened rect still passes under it, but
            -- the filter is declared later at the same frame level, so it
            -- renders on top and keeps its own clicks; the reservation just
            -- shortens the extension (accepted: the leftmost ~20px of the
            -- header don't toggle while the filter is shown).
            local reserved = btnW
            local filter = headerFrame.FilterButton
            if filter and filter.IsShown and filter:IsShown() then
                reserved = reserved + ((filter.GetWidth and filter:GetWidth()) or 0) + 2
            end
            -- Negative inset expands the hit rect outward from that edge.
            -- Re-applied on every skin pass so it tracks header size changes
            -- (Edit Mode resize); clamped so a stale/short header can never
            -- leave a hit area hanging off the header into empty screen.
            local extendX = headerW - reserved
            if extendX < 0 then extendX = 0 end
            -- The button is shorter than the header (16 vs 26 on section
            -- headers), so match the header's height as well or the top and
            -- bottom few pixels of the title stay dead.
            local extendY = (headerH - btnH) / 2
            if extendY < 0 then extendY = 0 end
            minimizeBtn:SetHitRectInsets(-extendX, 0, -extendY, -extendY)
        end
    end
end
-- The Forever filter toggle re-skins its header once built.
TrackerNS.SkinHeader = SkinHeader

-------------------------------------------------------------------------------
-- Block skin: color quest title gold, objectives gray, completed green.
-- Objective lines live on block.lines[*] keyed by text; tint each line's
-- FontString according to its completion state each refresh via a hook on
-- the block's GetLine / AddObjective path where available.
-------------------------------------------------------------------------------
local function StyleObjectiveLine(line)
    if not line or not line.Text then return end
    StyleObjectiveFS(line.Text)
    if line.Dash then StyleObjectiveFS(line.Dash) end
    if line.GetRegions then StyleAllFontStrings(line) end
end

-------------------------------------------------------------------------------
-- Quest type icon system. Replaces Blizzard's per-block type icon with our
-- own atlas picks so the visuals match the rest of CUI.
-------------------------------------------------------------------------------
local QUEST_ICON_ATLAS = {
    normal = nil,
    campaign = "Crosshair_campaignquest_32",
    legendary = "Crosshair_legendaryquest_32",
    important = "Crosshair_important_48",
    recurring = "Crosshair_Recurring_48",
    daily = "Crosshair_Recurring_48",
    weekly = "Crosshair_Recurring_48",
    meta = "Crosshair_Wrapper_48",
}
local QUEST_TURNIN_ATLAS = {
    campaign = "Crosshair_campaignquestturnin_32",
    legendary = "Crosshair_legendaryquestturnin_32",
    important = "Crosshair_importantturnin_48",
    recurring = "Crosshair_Recurringturnin_48",
    daily = "Crosshair_Recurringturnin_48",
    weekly = "Crosshair_Recurringturnin_48",
    meta = "Crosshair_Wrapperturnin_48",
}
local QUEST_ICON_SIZE_OVERRIDE = {
    recurring = 18,
    daily = 18,
    weekly = 18,
    important = 22,
}
local QUEST_ICON_SIZE = 16

-- Cache of questID -> { key = "...", done = bool }. Computed ONCE per quest
-- the first time we see it, then refreshed only when the quest log itself
-- signals change (via QUEST_LOG_UPDATE / QUEST_REMOVED handled below).
-- Never called inline on the live skin path so secure quest-log APIs
-- can't leak taint into MoneyFrame / reward rendering on quest turn-in.
local _classifyCache = {}

local function _computeClassification(questID)
    if not questID or not C_QuestLog then return nil end
    local logIdx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
    local details = logIdx and C_QuestLog.GetInfo and C_QuestLog.GetInfo(logIdx)
    local cls = details and details.questClassification
    local freq = (details and details.frequency) or 0
    local done = C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) or false

    local blockKey = "normal"
    if C_CampaignInfo and C_CampaignInfo.IsCampaignQuest and C_CampaignInfo.IsCampaignQuest(questID) then
        blockKey = "campaign"
    elseif cls and Enum and Enum.QuestClassification then
        local QC = Enum.QuestClassification
        if cls == QC.Important then
            blockKey = "important"
        elseif cls == QC.Legendary then
            blockKey = "legendary"
        elseif cls == QC.Campaign then
            blockKey = "campaign"
        elseif cls == QC.Recurring then
            blockKey = "recurring"
        end
    end
    if blockKey == "normal" then
        if freq == 1 then
            blockKey = "daily"
        elseif freq == 2 then
            blockKey = "weekly"
        end
    end
    return { key = blockKey, done = done }
end

local function ClassifyQuest(questID)
    if not questID then return nil, false end
    local record = _classifyCache[questID]
    if not record then return nil, false end
    local blockKey = record.key
    if record.done and QUEST_TURNIN_ATLAS[blockKey] then return QUEST_TURNIN_ATLAS[blockKey], blockKey end
    return QUEST_ICON_ATLAS[blockKey], blockKey
end

-- Refresh the classify cache outside any skin / tracker-Update chain. Only driven by
-- quest-log events so secure-API reads never happen inside the debounced tracker Update
-- or block hover paths that surround MoneyFrame / reward rendering.
local function _refreshClassifyCache()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries) then return end
    local seenSet = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local details = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        local questId = details and details.questID
        if questId then
            seenSet[questId] = true
            _classifyCache[questId] = _computeClassification(questId)
        end
    end
    -- Drop stale entries for quests no longer in the log (turned in, etc.)
    for questId in pairs(_classifyCache) do
        if not seenSet[questId] then _classifyCache[questId] = nil end
    end
end

do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:RegisterEvent("QUEST_ACCEPTED")
    frame:RegisterEvent("QUEST_REMOVED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    local _pending = false
    -- The cache only feeds our custom icons. The stock styles never draw them
    -- (latched for the session): InitSkin unregisters this frame and blanks
    -- its registration so ResumeQTEvents never brings it back. The Show Quest
    -- Icons toggle can flip mid-session (its reload prompt can be declined),
    -- so the cache stays warm on the CludesUI look either way.
    frame:SetScript("OnEvent", function()
        if _pending or STOCK then return end
        _pending = true
        C_Timer.After(0.25, function()
            _pending = false
            if STOCK then return end
            _refreshClassifyCache()
        end)
    end)
    if not TrackerNS._eventFrames then TrackerNS._eventFrames = {} end
    if not TrackerNS._eventRegistrations then TrackerNS._eventRegistrations = {} end
    local position = #TrackerNS._eventFrames + 1
    TrackerNS._eventFrames[position] = frame
    TrackerNS._eventRegistrations[position] =
        { "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_ENTERING_WORLD" }
    TrackerNS._classifyFrameIdx = position
end

-- Hides Blizzard's built-in quest type icon(s) on a block (without
-- recursing into the block's children) and stamps ours on top.

local function ApplyQuestTypeIcon(questBlock)
    if not questBlock then return end

    -- "Show Quest Icons" on: Blizzard's native icons are shown instead, so
    -- never stamp our own custom icon (hide any we already created).
    if StockIconsOn() then
        if _blockIcons[questBlock] then _blockIcons[questBlock]:Hide() end
        return
    end

    local questId = questBlock.id
    if type(questId) ~= "number" then
        if _blockIcons[questBlock] then _blockIcons[questBlock]:Hide() end
        return
    end

    -- Suppress our custom icon when Blizzard's ItemButton or
    -- groupFinderButton is already visible on this block. Probe the block
    -- fields directly (the icon you SEE is Blizzard's, and our overlay
    -- texture is mouse-pass-through, so it eats the visual click target).
    local hasItem = (
        questBlock.ItemButton
        and questBlock.ItemButton.IsShown
        and questBlock.ItemButton:IsShown()
    )
        or (questBlock.itemButton and questBlock.itemButton.IsShown and questBlock.itemButton:IsShown())
    -- block.GroupFinderButton was probed here too until the /fstack evidence in the
    -- group-finder click fix proved it never exists (that same nil field left the
    -- button unraised and unclickable). rightEdgeFrame is what actually covers the
    -- group finder: it holds the LAST right-edge frame added, which is the group
    -- finder on a quest that has only that, and a quest with both is already caught
    -- by ItemButton above.
    local hasLFG = (
        questBlock.groupFinderButton
        and questBlock.groupFinderButton.IsShown
        and questBlock.groupFinderButton:IsShown()
    )
        or (
            questBlock.rightEdgeFrame
            and questBlock.rightEdgeFrame.IsShown
            and questBlock.rightEdgeFrame:IsShown()
        )
    if hasItem or hasLFG then
        if _blockIcons[questBlock] then _blockIcons[questBlock]:Hide() end
        return
    end

    local atlasName, blockKey = ClassifyQuest(questId)
    if not atlasName then
        if _blockIcons[questBlock] then _blockIcons[questBlock]:Hide() end
        return
    end

    local iconTex = _blockIcons[questBlock]
    if not iconTex then
        iconTex = questBlock:CreateTexture(nil, "OVERLAY")
        iconTex:SetPoint("TOPRIGHT", questBlock, "TOPRIGHT", -2, 3)
        _blockIcons[questBlock] = iconTex
    end
    -- Skip redundant SetAtlas/SetSize when the icon already matches.
    if iconTex._lastAtlas ~= atlasName then
        iconTex._lastAtlas = atlasName
        local size = QUEST_ICON_SIZE_OVERRIDE[blockKey] or QUEST_ICON_SIZE
        iconTex:SetSize(size, size)
        iconTex:SetAtlas(atlasName)
    end
    iconTex:SetAlpha(1)
    iconTex:Show()
end

-------------------------------------------------------------------------------
-- Focus highlight: color the super-tracked quest's block with the user's
-- focus color (default purple). One texture per block, cached in _blockFocus.
-------------------------------------------------------------------------------
-- Find the quest title FontString on a block. It's the first FontString
-- region in Blizzard's layout (confirmed via dump). Cached per-block so
-- hot paths (hover reassert) don't re-walk regions on every mouse event.
local _blockTitleFSCache = setmetatable({}, { __mode = "k" })
local function GetBlockTitleFS(questBlock)
    if not questBlock then return nil end
    local cached = _blockTitleFSCache[questBlock]
    if cached then return cached end
    if not questBlock.GetRegions then return nil end
    for _, regionTex in ipairs({ questBlock:GetRegions() }) do
        if regionTex.GetObjectType and regionTex:GetObjectType() == "FontString" then
            _blockTitleFSCache[questBlock] = regionTex
            return regionTex
        end
    end
    return nil
end

-- Super-tracked quest ID cache. Updated only on SUPER_TRACKING_CHANGED so hover
-- handlers don't hit C_SuperTrack.GetSuperTrackedQuestID on every mouse enter/leave.
local _superTrackedID = nil
local function GetSuperTrackedIDCached() return _superTrackedID end
do
    local scrollFrame = CreateFrame("Frame")
    scrollFrame:RegisterEvent("SUPER_TRACKING_CHANGED")
    scrollFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    scrollFrame:SetScript("OnEvent", function(_, event)
        -- The cached ID only colours our focus highlight, which the stock
        -- styles never paint.
        if not STOCK and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
            local ident = C_SuperTrack.GetSuperTrackedQuestID()
            _superTrackedID = (ident and ident ~= 0) and ident or nil
        end
        -- Super-tracking assigns a fresh POI button to the block.
        -- Defer one frame so Blizzard's assignment lands first. Nothing to
        -- suppress while native icons show, unless the hidden tracker needs
        -- the fresh button mouse-off.
        if event == "SUPER_TRACKING_CHANGED" and (not StockIconsOn() or TrackerNS._trackerMouseOff) then
            C_Timer.After(0, function()
                if not TrackerNS._SuppressAllPOIs then return end
                TrackerNS._SuppressAllPOIs()
            end)
        end
    end)
    if not TrackerNS._eventFrames then TrackerNS._eventFrames = {} end
    if not TrackerNS._eventRegistrations then TrackerNS._eventRegistrations = {} end
    local position = #TrackerNS._eventFrames + 1
    TrackerNS._eventFrames[position] = scrollFrame
    TrackerNS._eventRegistrations[position] = { "SUPER_TRACKING_CHANGED", "PLAYER_ENTERING_WORLD" }
    TrackerNS._superTrackFrameIdx = position
end

-- One-time layout setup for the title fontstring: font, anchors, width.
-- Called once per block from SkinBlock's full pass.
local function SetupTitleLayout(questBlock)
    if not questBlock then return end
    local fontStr = GetBlockTitleFS(questBlock)
    if not fontStr then return end
    StyleTitleFS(fontStr)
    if fontStr.SetWordWrap then fontStr:SetWordWrap(false) end
    if fontStr.SetNonSpaceWrap then fontStr:SetNonSpaceWrap(false) end
    -- Strip Blizzard's TOPLEFT+TOPRIGHT dual anchor so SetWidth works.
    if fontStr.GetNumPoints and fontStr:GetNumPoints() > 0 then
        local anchorPoint, relTo, relPoint, posX, posY = fontStr:GetPoint(1)
        if anchorPoint then
            fontStr:ClearAllPoints()
            fontStr:SetPoint(anchorPoint, relTo, relPoint, posX or 0, posY or 0)
        end
    end
    if fontStr.SetWidth then fontStr:SetWidth(220) end
end

-- WoW Forever wraps tracker titles in a difficulty color code while the
-- showQuestDifficultyColor CVar is on, and an inline code beats SetTextColor.
-- The focused title drops it; Blizzard sets every title again on the next
-- update, so the color comes back once the focus moves on.
local IS_FOREVER = CludesUI.IS_FOREVER
local function StripTitleColorCodes(fontStr)
    local textValue = fontStr:GetText()
    if not textValue or issecretvalue(textValue) or not textValue:find("|c", 1, true) then return end
    local plain = textValue:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    if plain ~= textValue then fontStr:SetText(plain) end
end

-- Title Difficulty Colors (WoW Forever; the Colors section's toggle) is the
-- game's own showQuestDifficultyColor option, which Blizzard's tracker and
-- quest log follow; the skin and the custom tracker read it here. Retail has
-- no quest title difficulty colors.
local function TitleDifficultyOn()
    if not IS_FOREVER then return false end
    return C_CVar.GetCVarBool("showQuestDifficultyColor") == true
end
-- A quest's difficulty color for the player's level, or nil.
local function QuestDifficultyRGB(questID)
    local color = GetDifficultyColor(C_PlayerInfo.GetContentDifficultyQuestForPlayer(questID))
    if color then return color.r, color.g, color.b end
end

-- Lightweight color-only refresh. Called on hover (OnEnter/OnLeave) and
-- from the stamped fast-path in SkinBlock.
local function ApplyFocusHighlight(questBlock)
    if not questBlock then return end
    local fontStr = GetBlockTitleFS(questBlock)
    if not fontStr then return end
    local questId = (type(questBlock.id) == "number") and questBlock.id or nil
    local isFocus = questId and (questId == GetSuperTrackedIDCached())
    local isDone = questId and C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questId)
    -- With Title Difficulty Colors off, a code Blizzard wrote while it was on
    -- stays in the title until Blizzard sets it again: it goes here too.
    local diff = TitleDifficultyOn()
    if IS_FOREVER and (isFocus or not diff) then StripTitleColorCodes(fontStr) end
    local red, green, blue
    if isFocus then
        red, green, blue = GetFocusRGB()
    elseif isDone then
        red, green, blue = GetCompletedRGB()
    else
        -- On: the quest's difficulty color, for a title Blizzard has not set
        -- again since the option came on (it carries no code yet).
        if diff and questId then
            red, green, blue = QuestDifficultyRGB(questId)
        end
        if not red then
            red, green, blue = GetTitleRGB()
        end
    end
    fontStr:SetTextColor(red, green, blue)
end

-- Shared with the custom tracker (Custom.lua) and the options.
TrackerNS.GetFont = GetFont
TrackerNS.GetTitleRGB, TrackerNS.GetCompletedRGB, TrackerNS.GetFocusRGB =
    GetTitleRGB, GetCompletedRGB, GetFocusRGB
TrackerNS.TitleDifficultyOn, TrackerNS.QuestDifficultyRGB = TitleDifficultyOn, QuestDifficultyRGB
TrackerNS.GetHeaderRGB, TrackerNS.GetLineRGB = GetHeaderRGB, GetLineRGB

-- Skip all skinning work when the tracker is force-hidden (M+, raid, arena).
-- Uses the cached suppression flag only (set by ApplySuppression /
-- UpdateVisibility). No per-call API queries.
local function ShouldSkipSkin() return TrackerNS.IsSuppressed and TrackerNS.IsSuppressed() end

-- Hook block line-add APIs once per block instance. Catches every line
-- Blizzard creates or recycles without walking children.
local function HookBlockLineMethods(questBlock)
    if _hookedBlocks[questBlock] then return end
    _hookedBlocks[questBlock] = true

    -- Blizzard changes the title text color on mouse enter (darkens it
    -- as hover feedback). Reassert our color from a post-hook so whatever
    -- gold/focus color we chose is what the player sees.
    local function reassertTitle()
        ApplyFocusHighlight(questBlock)
        -- Hover highlight swaps line colors too (WoW Forever's objective
        -- colors; nil on retail).
        local paint = TrackerNS.ColorObjectiveLines
        if paint then paint(questBlock) end
    end
    if questBlock.HookScript then
        questBlock:HookScript("OnEnter", reassertTitle)
        questBlock:HookScript("OnLeave", reassertTitle)
    end
    -- The HeaderButton (if present) often owns the hover script directly.
    if questBlock.HeaderButton and questBlock.HeaderButton.HookScript then
        questBlock.HeaderButton:HookScript("OnEnter", reassertTitle)
        questBlock.HeaderButton:HookScript("OnLeave", reassertTitle)
    end

    -- REMOVED: an OnClick post-hook here used to call
    -- C_SuperTrack.SetSuperTrackedQuestID(block.id) so a left-click also
    -- super-tracked the quest. Setting the super-track from addon (tainted)
    -- execution taints Blizzard's world-map super-track / AreaPOI refresh,
    -- surfacing later as a blocked Frame:SetPropagateMouseClicks() when the map
    -- builds POI pins (ADDON_ACTION_BLOCKED via QuestMapFrame_ShowQuestDetails).
    -- Blizzard's native block click already super-tracks the quest securely, so
    -- the hook was redundant; the focus highlight still follows the super-track
    -- via the SUPER_TRACKING_CHANGED handler.

    -- AddObjective / SetStringText hooks REMOVED (session 68 perf audit).
    -- SkinBlock already styles all fontstrings via GetRegions() walk +
    -- ProcessBlockChildren. These per-call hooks charged Blizzard's entire
    -- AddObjective/SetStringText execution to our addon in the profiler
    -- (11 + 14 = 25 calls per collapse, ~8ms attributed to us).
end

-- Ornamental atlas keywords: textures with these substrings in their atlas
-- name are decorative and should be hidden. Lookup table avoids 9x string.find.
local ORNAMENTAL_KEYWORDS = {
    evergreen = true,
    toast = true,
    filigree = true,
    parchment = true,
    bountiful = true,
    shimmer = true,
    sparkle = true,
    trackerheader = true,
    jailerstower = true,
}
local _ornamentalCache = setmetatable({}, { __mode = "k" })
local function IsOrnamentalAtlas(regionTex)
    local cached = _ornamentalCache[regionTex]
    if cached ~= nil then return cached end
    local atlasName = regionTex.GetAtlas and regionTex:GetAtlas()
    if type(atlasName) ~= "string" then
        _ornamentalCache[regionTex] = false
        return false
    end
    local l = atlasName:lower()
    for kw in pairs(ORNAMENTAL_KEYWORDS) do
        if l:find(kw, 1, true) then
            _ornamentalCache[regionTex] = true
            return true
        end
    end
    _ornamentalCache[regionTex] = false
    return false
end

-- Walk child frames of a block up to 3 levels deep. Strip ornamental
-- atlas textures and style objective fontstrings. Defined at file scope
-- so it's not recreated per SkinBlock call.
local function ProcessBlockChildren(widget, depth)
    if not widget or depth > 3 or not widget.GetChildren then return end

    for _, childFrame in ipairs({ widget:GetChildren() }) do
        if childFrame.GetObjectType then
            local success, otype = pcall(childFrame.GetObjectType, childFrame)
            if success then
                if (otype == "Frame" or otype == "Button") and not childFrame.Tooltip then
                    if childFrame.GetRegions then
                        for _, regionTex in ipairs({ childFrame:GetRegions() }) do
                            local ot = regionTex.GetObjectType and regionTex:GetObjectType()
                            if ot == "Texture" then
                                if IsOrnamentalAtlas(regionTex) then regionTex:SetTexture("") end
                            elseif ot == "FontString" then
                                StyleObjectiveFS(regionTex)
                            end
                        end
                    end
                    ProcessBlockChildren(childFrame, depth + 1)
                end
            end
        end
    end
end

local _suppressedPOIs = setmetatable({}, { __mode = "k" })

-- NEVER call :Hide() on a quest POI button, and never post-hook its :Show().
-- POIButtonTemplate wires <OnShow>/<OnHide> to POIButtonMixin, and those two
-- handlers do nothing but EventRegistry:RegisterCallback / UnregisterCallback
-- on "Supertracking.OnChanged". Running either from our (tainted) execution
-- writes into EventRegistry's shared callback table for that event, so every
-- other subscriber -- SuperTrackablePinMixin, VignetteDataProvider,
-- QuestDataProvider, WorldQuestDataProvider, DungeonEntranceDataProvider --
-- is then dispatched tainted on the next TriggerEvent. Observed fallout:
-- a blocked Frame:SetPropagateMouseClicks() while the world map acquires pins,
-- and secret-value errors when GameTooltip lays out a vignette widget set.
--
-- Alpha runs no script handler, so suppress with alpha + EnableMouse instead.
-- Blizzard's own UpdateButtonAlpha only touches NormalTexture/PushedTexture,
-- never the button frame, so it cannot undo this -- which is also why the old
-- Show hook is gone: Show() no longer un-suppresses anything.
local function ApplyPOISuppression(progressBar)
    progressBar:SetAlpha(0)
    progressBar:EnableMouse(false)
end

-- ObjectiveTrackerPOIButtonTemplate's AddAnim ends on alpha 1 (setToFinalAlpha),
-- and it is the only thing in Blizzard's code that writes the button frame's
-- alpha at all -- Pool_HideAndClearAnchors and POIButtonMixin:Reset() leave both
-- alpha and mouse state alone, so a pooled button is handed back out still
-- suppressed. That means current alpha says nothing about whether a fanfare is
-- about to un-hide the button, so queue the re-apply unconditionally and dedupe
-- on a pending timer instead. Re-arms itself if the animation is still running.
local _poiRepair = setmetatable({}, { __mode = "k" })

local function QueuePOIRepair(progressBar)
    if _poiRepair[progressBar] then return end
    _poiRepair[progressBar] = true
    C_Timer.After(0.35, function()
        _poiRepair[progressBar] = nil
        if StockIconsOn() then return end
        ApplyPOISuppression(progressBar)
        if progressBar.AddAnim and progressBar.AddAnim:IsPlaying() then QueuePOIRepair(progressBar) end
    end)
end

-- The fanfare fades the button in when a quest is put on the tracker
-- (accepted, or returned by the quest filter) and keeps the final alpha, so the
-- icon showed until the repair above. Its Alpha animation is given a target of
-- 0 instead: the fanfare still plays, invisibly, and ends hidden. A method
-- call on the animation, no hook and no script; once per button (weak table),
-- and back to 1 where the native icons are put back.
local _poiAnimMuted = setmetatable({}, { __mode = "k" })
local function SetPOIFanfareAlpha(animGroup, toAlpha)
    local anims = { animGroup:GetAnimations() }
    for i = 1, #anims do
        local a = anims[i]
        if a:GetObjectType() == "Alpha" then a:SetToAlpha(toAlpha) end
    end
end

-- A quest put on the tracker gets its POI button in the block's OnLayout,
-- after AddBlock, and that same pass draws the button and plays its fanfare,
-- so the AddBlock hook and the deferred sweep came too late for it (the
-- icon flashed). The block's GetPOIButton is the moment it takes the button:
-- suppressed there too, before either. Post-hook, once per block.
local _poiBlockHooked = setmetatable({}, { __mode = "k" })
local OnBlockGetPOIButton

local function SuppressPOI(questBlock)
    if not questBlock then return end

    if StockIconsOn() then
        -- Restore buttons we suppressed earlier in this session so flipping the
        -- setting on takes effect without waiting for the reload prompt.
        local progressBar = questBlock.poiButton
        if progressBar and _suppressedPOIs[progressBar] then
            _suppressedPOIs[progressBar] = nil
            progressBar:SetAlpha(1)
            progressBar:EnableMouse(true)
            local animGroup = progressBar.AddAnim
            if animGroup and _poiAnimMuted[animGroup] then
                _poiAnimMuted[animGroup] = nil
                SetPOIFanfareAlpha(animGroup, 1)
            end
        end
        return
    end

    if not _poiBlockHooked[questBlock] and questBlock.GetPOIButton then
        _poiBlockHooked[questBlock] = true
        hooksecurefunc(questBlock, "GetPOIButton", OnBlockGetPOIButton)
    end
    local progressBar = questBlock.poiButton
    if not progressBar then return end

    _suppressedPOIs[progressBar] = true
    ApplyPOISuppression(progressBar)
    local animGroup = progressBar.AddAnim
    if animGroup and not _poiAnimMuted[animGroup] then
        _poiAnimMuted[animGroup] = true
        SetPOIFanfareAlpha(animGroup, 0)
    end
    QueuePOIRepair(progressBar)
end

OnBlockGetPOIButton = function(questBlock)
    if STOCK or ShouldSkipSkin() then return end
    SuppressPOI(questBlock)
end

-------------------------------------------------------------------------------
-- Hidden-tracker mouse suppression. Every alpha-0 state (the combat
-- auto-hide, the user's visibility rules, mouseover idle) left the pooled
-- block buttons clickable: a click meant for the world opened the quest log
-- instead. The tracker's click sinks are a finite, NAMED set hung off each
-- block, so they are switched off by field name -- never by walking children
-- -- and only frames that were ON go into the weak set, so the restore can
-- never mouse-enable something Blizzard left off (a mouse-enabled alpha-0
-- tracker frame would be a screen-sized click-catcher). EnableMouse runs no
-- script handler and writes no Lua field: taint-free, and legal in combat
-- since none of these frames is protected. Blocks Blizzard hands out or
-- re-enables while the tracker is hidden come back through the AddBlock hook
-- and the deferred Update sweep, which re-apply the current state.
-- Scenario / UI-widget trackers are headers-only here (see SharesWidgetPool).
local _mouseOffSet = setmetatable({}, { __mode = "k" })

-- Records WHICH half was on (1 = clicks, 2 = motion, 3 = both) so the
-- restore puts back exactly that: an XML tooltip-only frame runs on motion
-- alone, and handing it clicks would make it a click sink it never was.
local function DisableMouse(frame)
    if not (frame and frame.IsMouseEnabled) or _mouseOffSet[frame] then return end
    local mode
    if frame.IsMouseClickEnabled and frame.IsMouseMotionEnabled then
        mode = (frame:IsMouseClickEnabled() and 1 or 0) + (frame:IsMouseMotionEnabled() and 2 or 0)
    else
        mode = frame:IsMouseEnabled() and 3 or 0
    end
    if mode == 0 then return end
    _mouseOffSet[frame] = mode
    frame:EnableMouse(false)
end
-- For frames built while the tracker is hidden (the Forever filter toggle).
TrackerNS.MouseOff = DisableMouse

-- One block's click sinks: the block frame itself (bonus blocks), the header
-- button (the quest log click), the item, group-finder and POI buttons, the
-- objective lines (hyperlinks) and every right-edge region with its bar.
local function ApplyBlockMouse(questBlock)
    DisableMouse(questBlock)
    DisableMouse(questBlock.HeaderButton)
    DisableMouse(questBlock.ItemButton)
    DisableMouse(questBlock.poiButton)
    local lines = questBlock.usedLines
    if type(lines) == "table" then
        for _, line in pairs(lines) do
            if type(line) == "table" then DisableMouse(line) end
        end
    end
    local regions = questBlock.addedRegions
    if type(regions) == "table" then
        for regionFrame in pairs(regions) do
            if type(regionFrame) == "table" then
                DisableMouse(regionFrame)
                DisableMouse(regionFrame.Bar)
            end
        end
    end
end

-- The scenario tracker's blocks are FIXED XML frames of the module
-- (parentArray FixedBlocks), not pool frames: the stage block carrying the
-- dungeon name and its tooltip, the objectives block, the challenge block
-- with its affix and status frames, the proving-grounds block, the maw and
-- delve buff containers, the scenario spell buttons. Switching THEIR mouse
-- off touches no shared-widget-pool frame; the UIWidget containers inside
-- them are left alone (see SharesWidgetPool).
local function ApplyScenarioMouse(sc)
    if not sc then return end
    if sc.ObjectivesBlock then ApplyBlockMouse(sc.ObjectivesBlock) end
    local stage = sc.StageBlock
    if stage then
        DisableMouse(stage)
        DisableMouse(stage.findGroupButton)
    end
    local collapseMark = sc.ChallengeModeBlock
    if collapseMark then
        DisableMouse(collapseMark)
        DisableMouse(collapseMark.StartedDepleted)
        DisableMouse(collapseMark.TimesUpLootStatus)
        DisableMouse(collapseMark.DeathCount)
        local pool = collapseMark.affixPool
        if pool and pool.EnumerateActive then
            for affix in pool:EnumerateActive() do
                DisableMouse(affix)
            end
        end
    end
    DisableMouse(sc.ProvingGroundsBlock)
    if sc.MawBuffsBlock then DisableMouse(sc.MawBuffsBlock.Container) end
    if sc.TieredEntranceTraitsBlock then DisableMouse(sc.TieredEntranceTraitsBlock.Container) end
    local spells = sc.spellFramePool
    if spells and spells.EnumerateActive then
        for scrollFrame in spells:EnumerateActive() do
            DisableMouse(scrollFrame.SpellButton)
        end
    end
end

-- Raise the block's right-edge buttons (quest item / group finder) above the
-- block itself. Blizzard acquires both the block and its right-edge frames from
-- the same module pool, so they are siblings on ContentsFrame at the *same*
-- frame level; the block then wins hit-testing and swallows the button's clicks.
--
-- Only the quest item button is stored under a named field
-- (block.ItemButton, Blizzard_QuestObjectiveTracker.lua). The group finder
-- button has no named field at all -- block.rightEdgeFrame holds just the last
-- one added, which is the item button whenever a quest has both. The complete
-- set is block.addedRegions (ObjectiveTrackerBlockMixin:OnAddedRegion), so walk
-- that and raise every Button in it. Objective lines, timer bars and progress
-- bars are Frames and stay untouched.
local function RaiseRightEdgeButtons(questBlock)
    local bl = questBlock.GetFrameLevel and questBlock:GetFrameLevel() or 0
    if questBlock.ItemButton and questBlock.ItemButton.SetFrameLevel then
        questBlock.ItemButton:SetFrameLevel(bl + 5)
    end
    local regions = questBlock.addedRegions
    if type(regions) ~= "table" then return end
    for regionFrame in pairs(regions) do
        if
            type(regionFrame) == "table"
            and regionFrame.SetFrameLevel
            and regionFrame.GetObjectType
            and regionFrame:GetObjectType() == "Button"
        then
            regionFrame:SetFrameLevel(bl + 5)
        end
    end
end

local function SkinBlock(questBlock)
    if not questBlock then return end
    -- Stock styles: Blizzard's block art, fonts and POI icons stay untouched
    -- (the stock title keeps its right-edge anchor, so the item and group
    -- finder buttons need no raise either).
    if STOCK or ShouldSkipSkin() then return end

    -- Suppress POI on every entry -- Blizzard may assign a new pooled
    -- poiButton to the block between skin passes.
    SuppressPOI(questBlock)

    -- Also on every entry: a block can gain a right-edge button after it was
    -- first skinned (a quest becomes groupable, an item is granted), and the
    -- pooled Init/Reset paths reset the level back to the block's.
    RaiseRightEdgeButtons(questBlock)

    -- Skip blocks already fully skinned. The heavy work (strip textures,
    -- style fontstrings, walk children) only needs to happen once per block.
    -- Quest type icons and focus highlight are cheap and re-applied below.
    if _skinned[questBlock] then
        ApplyQuestTypeIcon(questBlock)
        ApplyFocusHighlight(questBlock)
        return
    end

    HookBlockLineMethods(questBlock)

    -- Strip named decorative textures by key.
    for _, k in ipairs({
        "Background",
        "HeaderBackground",
        "Stripe",
        "Sheen",
        "Glow",
        "Highlight",
        "ShineTop",
        "ShineBottom",
    }) do
        local region = questBlock[k]
        if region and region.SetTexture then region:SetTexture("") end
    end

    -- Single GetRegions() walk: strip remaining textures AND style fontstrings
    -- in one pass instead of two separate walks.
    local myIcon = _blockIcons[questBlock]
    if questBlock.GetRegions then
        for _, regionTex in ipairs({ questBlock:GetRegions() }) do
            local ot = regionTex.GetObjectType and regionTex:GetObjectType()
            if ot == "Texture" then
                if regionTex ~= myIcon and regionTex.SetTexture then regionTex:SetTexture("") end
            elseif ot == "FontString" then
                StyleFontString(regionTex)
            end
        end
    end

    -- Item button (quest item) count FontString if present.
    if questBlock.itemButton and questBlock.itemButton.Count then
        StyleFontString(questBlock.itemButton.Count)
    end

    -- Replace Blizzard's quest-type icon with ours, based on the quest's
    -- classification / frequency / turn-in state.
    ApplyQuestTypeIcon(questBlock)

    -- One-time title layout (font, anchor strip, width constraint).
    SetupTitleLayout(questBlock)

    -- Focus color for super-tracked / completed / normal quest.
    ApplyFocusHighlight(questBlock)

    -- Strip ornamental textures + style objective fontstrings on child frames.
    ProcessBlockChildren(questBlock, 0)

    _skinned[questBlock] = true
end

-------------------------------------------------------------------------------
-- Re-skin every block a tracker has already populated. Safe to call any time
-- (idempotent via the _eqtBlockSkinned / _eqtBarSkinned flags on each frame).
-------------------------------------------------------------------------------
local function SkinExistingBlocks(trackerFrame)
    if STOCK or not trackerFrame then return end

    -- Refresh the accent divider under this tracker's header on every pass
    -- so collapsed/re-expanded states always keep a visible divider.
    if trackerFrame.Header then EnsureAccentDivider(trackerFrame.Header) end

    -- Never touch shared-widget-pool trackers' blocks (see SharesWidgetPool).
    -- The header/divider above is safe; the block loop below is not.
    if SharesWidgetPool(trackerFrame) then return end

    -- Collect the blocks in use. Blizzard's usedBlocks is keyed by template
    -- string, and each entry is a sub-table keyed by blockID -> block. Iterate
    -- two levels. No geometry reads here: block rects turn secret once our
    -- execution is tainted, and nothing below depends on visual order.
    local ordered = {}
    if trackerFrame.usedBlocks then
        for _, templateMap in pairs(trackerFrame.usedBlocks) do
            if type(templateMap) == "table" then
                for _, questBlock in pairs(templateMap) do
                    if type(questBlock) == "table" and questBlock.GetTop then
                        ordered[#ordered + 1] = questBlock
                    end
                end
            end
        end

        for _, questBlock in ipairs(ordered) do
            SkinBlock(questBlock)
        end

        -- Style objective lines (and WoW Forever's objective colors).
        local paint = TrackerNS.ColorObjectiveLines
        for _, questBlock in ipairs(ordered) do
            if questBlock.lines then
                for _, line in pairs(questBlock.lines) do
                    StyleObjectiveLine(line)
                end
            end
            if paint then paint(questBlock) end
        end
    end
end

-------------------------------------------------------------------------------
-- The custom topModulePadding write-and-fight system (TightenTopAnchor and its
-- successor) has been removed. We no longer touch
-- ObjectiveTrackerFrame.topModulePadding at all -- Blizzard's own default governs the
-- gap between the header and the first module, in and out of combat, with zero taint
-- surface. The master header is now skinned and shown in place instead of being
-- squeezed out, so there is nothing left to compensate for.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Master "All Objectives" header visibility. SkinHeader() above is always
-- applied to it in InitSkin(); this only controls visibility, driven by the
-- "hideAllObjectivesHeader" option so the user can opt into showing it.
-- Defaults to hidden (nil in DB reads as hidden) -- see ShouldHideMasterHeader.
--
-- Suppressed with alpha, never Hide() -- same pattern as ApplyPOISuppression above, and
-- layout-equivalent (the container spaces the first module by topModulePadding alone).
-- ObjectiveTrackerFrameMixin:Update() calls self.Header:Show() before the container layout,
-- so a Hide() must be fought from an OnShow script that taints the whole pass.
-- ScenarioObjectiveTracker lays out first, and its LayoutContents call to ShouldShowMawBuffs
-- -> C_UnitAuras.GetAuraDataByIndex hard-errors while tainted: the pass unwinds before
-- DirtiableMixin clears self.dirty, nothing schedules another, and it freezes until /reload.
-------------------------------------------------------------------------------
-- Default is "hidden" (true) when the DB key is unset. `~= false` treats
-- nil the same as true, while still honoring an explicit user choice of
-- false (i.e. "show it").
-- The stock styles default to shown, as Blizzard draws it: with no CludesUI
-- background behind the tracker, a hidden header would leave its reserved slot
-- as an empty band above the first section.
local function ShouldHideMasterHeader()
    local val = TrackerNS.Cfg("hideAllObjectivesHeader")
    if val == nil then return not TrackerNS.Blizz() end
    return val ~= false
end
TrackerNS.ShouldHideMasterHeader = ShouldHideMasterHeader

local function ApplyMasterHeaderVisibility()
    local objectiveTracker = _G.ObjectiveTrackerFrame
    if not objectiveTracker then return end
    local headerFrame = objectiveTracker.HeaderMenu or objectiveTracker.Header
    if not headerFrame then return end

    local hide = ShouldHideMasterHeader()
    headerFrame:SetAlpha(hide and 0 or 1)
    -- The header frame takes no mouse input of its own, but the collapse-all
    -- button would still be clickable while invisible.
    local minimizeBtn = headerFrame.MinimizeButton
    -- Never back on while the tracker is alpha-hidden (EQT.ApplyTrackerMouse
    -- brings it back with the tracker).
    if minimizeBtn and minimizeBtn.EnableMouse then
        minimizeBtn:EnableMouse(not hide and not TrackerNS._trackerMouseOff)
    end

    EnsureAccentDivider(headerFrame)
end
TrackerNS.ApplyMasterHeaderVisibility = ApplyMasterHeaderVisibility

-------------------------------------------------------------------------------
-- Hook a single sub-tracker.
-------------------------------------------------------------------------------
local function HookTracker(trackerFrame)
    if not trackerFrame then return end
    if _hookedTrackers[trackerFrame] then return end
    _hookedTrackers[trackerFrame] = true

    -- ScenarioObjectiveTracker and UIWidgetObjectiveTracker: only skin the
    -- header. Their child frames (blocks, progress bars, widget containers)
    -- share Blizzard's widget pool with tooltip/AreaPOI widgets. ANY method
    -- call on those frames taints the pool, causing secret-value arithmetic
    -- errors when GameTooltip processes widget sets later (LayoutFrame.lua
    -- "attempt to compare a secret number value" via GameTooltip_ClearWidgetSet).
    if SharesWidgetPool(trackerFrame) then
        if trackerFrame.Header then SkinHeader(trackerFrame.Header) end
        if trackerFrame.Update then
            -- The divider work is DEFERRED, never run inside this post-hook: the
            -- hook fires mid ObjectiveTrackerContainer:Update(), between module
            -- updates, and inline texture creation/anchoring against the
            -- Blizzard header left the rest of that container pass tainted --
            -- ScenarioObjectiveTracker:LayoutContents then hit
            -- ShouldShowMawBuffs -> GetAuraDataByIndex (RequiresUnitAuraAccess)
            -- from tainted execution and hard-errored under aura secrecy,
            -- aborting the flush before Blizzard cleared its dirty flag (the
            -- tracker froze until /reload; Curse Surge field repro, isolated by
            -- deferring only this call). Same dirty-flag + After(0) shape as the
            -- generic branch below; QueueResize only touches our own bg frame.
            local _dividerDirty = false
            local _scMouseDirty = false
            hooksecurefunc(trackerFrame, "Update", function(self)
                -- Hidden tracker: affix / spell frames this pass acquired come
                -- out mouse-off too (deferred: no frame work inline in a
                -- module Update post-hook).
                if
                    TrackerNS._trackerMouseOff
                    and trackerFrame == _G.ScenarioObjectiveTracker
                    and not _scMouseDirty
                then
                    _scMouseDirty = true
                    C_Timer.After(0, function()
                        _scMouseDirty = false
                        if TrackerNS._trackerMouseOff then ApplyScenarioMouse(_G.ScenarioObjectiveTracker) end
                    end)
                end
                -- Stock styles: no background to resize, no divider.
                if STOCK or ShouldSkipSkin() then return end
                if TrackerNS.QueueResize then TrackerNS.QueueResize() end
                if self.Header and not _dividerDirty then
                    _dividerDirty = true
                    C_Timer.After(0, function()
                        _dividerDirty = false
                        if ShouldSkipSkin() then return end
                        if self.Header then EnsureAccentDivider(self.Header) end
                    end)
                end
            end)
        end
        return
    end

    if trackerFrame.Header then
        SkinHeader(trackerFrame.Header)
        -- The stock styles have nothing to re-apply on a toggle: headers are
        -- fixed-size, so the hit rect set above holds. No hook, so none of our
        -- code enters the collapse chain.
        if trackerFrame.Header.SetCollapsed and not STOCK then
            hooksecurefunc(trackerFrame.Header, "SetCollapsed", function(self)
                if ShouldSkipSkin() then return end
                SkinHeader(self)
            end)
        end
    end

    if trackerFrame.AddBlock then
        hooksecurefunc(trackerFrame, "AddBlock", function(_, questBlock)
            -- A block handed out while the tracker is alpha-hidden must not
            -- come out clickable; independent of the skin (runs suppressed too).
            if questBlock and TrackerNS._trackerMouseOff then ApplyBlockMouse(questBlock) end
            if ShouldSkipSkin() then return end
            if questBlock then _skinned[questBlock] = nil end
            SkinBlock(questBlock)
        end)
    end

    -- tracker.Update hook REPLACED with lightweight dirty flag (session 68).
    -- The old hooksecurefunc charged Blizzard's entire Update() (10 calls
    -- per collapse, full layout pass each) to our addon in the profiler.
    -- Now we just set a flag and defer the work to a single pass.
    local _updateDirty = false
    if trackerFrame.Update then
        hooksecurefunc(trackerFrame, "Update", function()
            if _updateDirty then return end
            -- Suppressed (M+ / raid tools) or a stock style: no skin work, but
            -- a hidden tracker still needs the blocks this pass touched mouse-off.
            if (STOCK or ShouldSkipSkin()) and not TrackerNS._trackerMouseOff then return end
            _updateDirty = true
            C_Timer.After(0, function()
                _updateDirty = false
                local skip = STOCK or ShouldSkipSkin()
                local mouseOff = TrackerNS._trackerMouseOff
                -- WoW Forever's objective colors (nil on retail).
                local paint = TrackerNS.ColorObjectiveLines
                local colorLines = paint and TrackerNS.ObjColorsWanted()
                if skip and not mouseOff then return end
                if not skip then
                    if trackerFrame.Header then EnsureAccentDivider(trackerFrame.Header) end
                    if TrackerNS.QueueResize then TrackerNS.QueueResize() end
                end
                if trackerFrame.usedBlocks then
                    for _, templateMap in pairs(trackerFrame.usedBlocks) do
                        if type(templateMap) == "table" then
                            for _, questBlock in pairs(templateMap) do
                                if type(questBlock) == "table" then
                                    if not skip then
                                        SuppressPOI(questBlock)
                                        if colorLines then paint(questBlock) end
                                    end
                                    -- Blizzard's own Update re-enables bonus
                                    -- blocks; this lands after it.
                                    if mouseOff then ApplyBlockMouse(questBlock) end
                                end
                            end
                        end
                    end
                end
            end)
        end)
    end

    -- ContentsFrame:HookScript("OnSizeChanged") REMOVED: HookScript injects
    -- addon code into Blizzard's execution context, tainting ANY secure call
    -- chain that triggers a layout resize (e.g. dropdown menus at M+ end).
    -- The deferred tracker.Update hook + event handlers already call
    -- QueueResize, so this was purely redundant belt-and-suspenders.

    -- Skin blocks that already exist before our hooks were installed.
    -- Run immediately for blocks already populated, then once more
    -- deferred to catch late-populated blocks from Blizzard's init.
    if STOCK then return end
    SkinExistingBlocks(trackerFrame)
    C_Timer.After(0.5, function() SkinExistingBlocks(trackerFrame) end)
end

-------------------------------------------------------------------------------
-- Collect every tracker Blizzard exposes. Prefer the authoritative MODULES
-- table on ObjectiveTrackerFrame; fall back to named globals so late-loaded
-- sub-trackers are still caught.
-------------------------------------------------------------------------------
local function EachTracker(func)
    local seenSet = {}

    local objectiveTracker = _G.ObjectiveTrackerFrame
    local modules = objectiveTracker and (objectiveTracker.modules or objectiveTracker.MODULES)
    if modules then
        for _, t in ipairs(modules) do
            if t and not seenSet[t] then
                seenSet[t] = true
                func(t)
            end
        end
    end

    for _, name in ipairs(SUB_TRACKERS) do
        local t = _G[name]
        if t and not seenSet[t] then
            seenSet[t] = true
            func(t)
        end
    end
end

-- Sweep all tracker blocks and suppress any unsuppressed POI buttons.
-- Called from SUPER_TRACKING_CHANGED (deferred) to catch fresh POIs
-- that Blizzard assigns when the player clicks a quest on the map.
TrackerNS._SuppressAllPOIs = function()
    local mouseOff = TrackerNS._trackerMouseOff
    EachTracker(function(trackerFrame)
        -- Shared-widget-pool trackers have no quest POI buttons and touching
        -- their blocks taints the tooltip widget pool (see SharesWidgetPool).
        if SharesWidgetPool(trackerFrame) then return end
        if not trackerFrame.usedBlocks then return end
        for _, templateMap in pairs(trackerFrame.usedBlocks) do
            if type(templateMap) == "table" then
                for _, questBlock in pairs(templateMap) do
                    if type(questBlock) == "table" then
                        SuppressPOI(questBlock)
                        -- A POI freshly assigned to a hidden tracker.
                        if mouseOff then ApplyBlockMouse(questBlock) end
                    end
                end
            end
        end
    end)
end

-- One tracker's share of the mouse-off sweep: its header minimize button and
-- the blocks now in use (shared-widget-pool trackers: headers only, see
-- SharesWidgetPool).
local function TrackerMouseOff(trackerFrame)
    local headerFrame = trackerFrame.Header
    if headerFrame then DisableMouse(headerFrame.MinimizeButton) end
    if SharesWidgetPool(trackerFrame) or not trackerFrame.usedBlocks then return end
    for _, templateMap in pairs(trackerFrame.usedBlocks) do
        if type(templateMap) == "table" then
            for _, questBlock in pairs(templateMap) do
                if type(questBlock) == "table" then ApplyBlockMouse(questBlock) end
            end
        end
    end
end

-- Tracker-wide mouse switch, driven by the Visibility file on every alpha
-- edge (combat auto-hide, visibility rules, mouseover idle and hover). OFF
-- sweeps the blocks now in use plus the module and master header buttons;
-- later blocks ride the AddBlock hook and the Update sweep. ON restores
-- exactly the frames the weak set holds -- wherever Blizzard's pools moved
-- them since -- and nothing else; the master minimize button then follows
-- its own hide rule again (SkinHeader keeps it off while the header is
-- hidden by option). Both directions early-out when already applied, so a
-- visibility pass on an unchanged state costs one field read.
TrackerNS.ApplyTrackerMouse = function(enabled)
    if enabled then
        if not TrackerNS._trackerMouseOff then return end
        TrackerNS._trackerMouseOff = nil
        for frame, mode in pairs(_mouseOffSet) do
            _mouseOffSet[frame] = nil
            if mode == 3 or not frame.SetMouseClickEnabled then
                frame:EnableMouse(true)
            elseif mode == 1 then
                pcall(frame.SetMouseClickEnabled, frame, true)
            else
                pcall(frame.SetMouseMotionEnabled, frame, true)
            end
        end
        -- The master minimize button follows its own hide rule again (a
        -- header pass while hidden may have found it already off).
        local objectiveTracker = _G.ObjectiveTrackerFrame
        local mainTracker = objectiveTracker and (objectiveTracker.HeaderMenu or objectiveTracker.Header)
        local mb = mainTracker and mainTracker.MinimizeButton
        if mb and mb.EnableMouse and TrackerNS.ShouldHideMasterHeader then
            mb:EnableMouse(not TrackerNS.ShouldHideMasterHeader())
        end
        return
    end
    if TrackerNS._trackerMouseOff then return end
    TrackerNS._trackerMouseOff = true
    EachTracker(TrackerMouseOff)
    ApplyScenarioMouse(_G.ScenarioObjectiveTracker)
    local objectiveTracker = _G.ObjectiveTrackerFrame
    local mainTracker = objectiveTracker and (objectiveTracker.HeaderMenu or objectiveTracker.Header)
    if mainTracker then
        DisableMouse(mainTracker.MinimizeButton)
        DisableMouse(mainTracker.FilterButton)
    end
    -- WoW Forever's filter toggle (nil on retail).
    DisableMouse(TrackerNS.FilterToggle)
end

-- Custom tracker (WoW Forever): Blizzard's tracker stays shown but alpha 0 and
-- click-through, never skinned. No Hide(): its OnHide relayouts the right
-- managed frame container from our execution. Blocks are laid out before
-- AddBlock, so the hook catches their lines and right-edge buttons too.
function TrackerNS.MuteBlizzardTracker()
    local objectiveTracker = _G.ObjectiveTrackerFrame
    if not objectiveTracker then return end
    objectiveTracker:SetAlpha(0)
    -- Blizzard (Edit Mode, managed frames) and unlock mode set alpha back.
    hooksecurefunc(objectiveTracker, "SetAlpha", function(self, a)
        if a ~= 0 then self:SetAlpha(0) end
    end)
    TrackerNS.ApplyTrackerMouse(false)
    local function hook(trackerFrame)
        if _hookedTrackers[trackerFrame] or SharesWidgetPool(trackerFrame) or not trackerFrame.AddBlock then
            return
        end
        _hookedTrackers[trackerFrame] = true
        hooksecurefunc(trackerFrame, "AddBlock", function(_, questBlock)
            if questBlock then ApplyBlockMouse(questBlock) end
        end)
    end
    EachTracker(hook)
    if objectiveTracker.AddModule then
        hooksecurefunc(objectiveTracker, "AddModule", function(_, module)
            if not module then return end
            C_Timer.After(0, function()
                hook(module)
                TrackerMouseOff(module)
            end)
        end)
    end
end

-------------------------------------------------------------------------------
-- Entry point called from the loader after Blizzard_ObjectiveTracker loads.
-------------------------------------------------------------------------------
function TrackerNS.InitSkin()
    STOCK = TrackerNS.Blizz()
    CLASSIC = TrackerNS.Classic()
    -- Stock styles (fixed until reload): the classify cache has no reader and
    -- the super-track frame needs only SUPER_TRACKING_CHANGED (the hidden
    -- tracker's POI mouse-off). Blanking their registration lists keeps
    -- ResumeQTEvents from re-registering what is dropped here.
    if STOCK and TrackerNS._eventFrames then
        local ci = TrackerNS._classifyFrameIdx
        local castFrame = ci and TrackerNS._eventFrames[ci]
        if castFrame then
            castFrame:UnregisterAllEvents()
            TrackerNS._eventRegistrations[ci] = {}
        end
        local si = TrackerNS._superTrackFrameIdx
        local scrollFrame = si and TrackerNS._eventFrames[si]
        if scrollFrame then
            scrollFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
            TrackerNS._eventRegistrations[si] = { "SUPER_TRACKING_CHANGED" }
        end
    end
    local objectiveTracker = _G.ObjectiveTrackerFrame
    if objectiveTracker then
        -- Skin the master "All Objectives" header + minimize button the same
        -- way section headers (Quests / Achievements / etc) are skinned,
        -- instead of hiding it. Whether it's actually shown is a separate,
        -- user-controlled toggle -- see ApplyMasterHeaderVisibility().
        local mainHeader = objectiveTracker.HeaderMenu or objectiveTracker.Header
        if mainHeader then
            SkinHeader(mainHeader)
            -- Blizzard's own MinimizeButton OnClick calls SetCollapsed(), which
            -- reassigns the button's textures for the new collapsed/expanded state --
            -- overwriting the look we just synced from Quests. hooksecurefunc fires
            -- after that (possibly protected) call completes, back in normal addon
            -- execution, so re-running SkinHeader here carries no taint (same pattern
            -- HookTracker already uses for every per-section header below).
            if mainHeader.SetCollapsed and not _masterHeaderCollapseHooked and not STOCK then
                _masterHeaderCollapseHooked = true
                hooksecurefunc(mainHeader, "SetCollapsed", function(self, collapsed)
                    if ShouldSkipSkin() then return end
                    SkinHeader(self, collapsed)
                end)
            end
        end
        ApplyMasterHeaderVisibility()

        -- ApplyMasterHeaderVisibility() above ran before ObjectiveTrackerFrame has any
        -- content -- otf:IsShown() is still false at InitSkin() time
        -- (Blizzard_ObjectiveTracker has just loaded, no quest data yet), so
        -- EnsureAccentDivider's active-check for the master header evaluates false and
        -- the divider stays hidden. otf itself never actually goes through a Hide->Show
        -- transition once populated (it's structurally shown throughout, just empty),
        -- so an OnShow hook can't catch this. Re-run once after PLAYER_ENTERING_WORLD,
        -- deferred so the tracker has had a chance to populate with real quest data
        -- first. Mirrors the existing PLAYER_ENTERING_WORLD + C_Timer.After debounce
        -- pattern used elsewhere in this file (see _refreshClassifyCache above).
        do
            local reentry = CreateFrame("Frame")
            reentry:RegisterEvent("PLAYER_ENTERING_WORLD")
            reentry:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_ENTERING_WORLD")
                C_Timer.After(0.25, ApplyMasterHeaderVisibility)
            end)
        end

        -- Strip the parchment / nine-slice background behind the whole tracker.
        -- The stock styles keep Blizzard's panel (Edit Mode Opacity drives it).
        if not STOCK then
            if objectiveTracker.NineSlice then objectiveTracker.NineSlice:Hide() end
            StripTextures(objectiveTracker)
        end
    end

    EachTracker(HookTracker)

    -- otf.modules is still empty here (Blizzard registers its container after
    -- PLAYER_ENTERING_WORLD) and addons add their modules at any time, so hook
    -- each module as it joins, one frame later so no work runs inside AddModule.
    -- A module joining a hidden tracker comes out mouse-off like the rest.
    if objectiveTracker and objectiveTracker.AddModule then
        hooksecurefunc(objectiveTracker, "AddModule", function(_, module)
            if not module or _hookedTrackers[module] then return end
            C_Timer.After(0, function()
                HookTracker(module)
                if TrackerNS._trackerMouseOff then TrackerMouseOff(module) end
            end)
        end)
    end

    -- Re-skin on tracker refresh events. Each of these fires when Blizzard
    -- re-populates blocks; we piggy-back to catch newly-pooled-but-not-yet-
    -- hooked children and to reapply fonts/colors Blizzard just reset.
    -- The stock styles build no background, so the frame is never created
    -- (and never enrolled for ResumeQTEvents).
    if not STOCK then
        local eventName = CreateFrame("Frame")
        eventName:RegisterEvent("QUEST_LOG_UPDATE")
        eventName:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
        eventName:RegisterEvent("SCENARIO_UPDATE")
        eventName:RegisterEvent("SCENARIO_CRITERIA_UPDATE")
        eventName:RegisterEvent("TRACKED_ACHIEVEMENT_LIST_CHANGED")
        eventName:RegisterEvent("TRACKED_RECIPE_UPDATE")
        eventName:RegisterEvent("SUPER_TRACKING_CHANGED")
        -- Quest events just need a BG resize. Block skinning is handled by
        -- AddBlock/AddObjective/GetProgressBar/GetTimerBar hooks, so we no
        -- longer need to walk the entire tracker tree on every event. No combat
        -- catch-up event needed here either -- there is no addon-owned padding
        -- state left to re-correct after PLAYER_REGEN_ENABLED.
        eventName:SetScript("OnEvent", function(_, event)
            -- Resize only. A forced ObjectiveTrackerFrame:Update() used to run
            -- here on SUPER_TRACKING_CHANGED; removed -- see the FORBIDDEN
            -- comment near the top of this file. Focus-change layout staleness
            -- self-heals on Blizzard's next natural update.
            if TrackerNS.QueueResize then TrackerNS.QueueResize() end
        end)
        if not TrackerNS._eventFrames then TrackerNS._eventFrames = {} end
        if not TrackerNS._eventRegistrations then TrackerNS._eventRegistrations = {} end
        local position = #TrackerNS._eventFrames + 1
        TrackerNS._eventFrames[position] = eventName
        TrackerNS._eventRegistrations[position] = {
            "QUEST_LOG_UPDATE",
            "QUEST_WATCH_LIST_CHANGED",
            "SCENARIO_UPDATE",
            "SCENARIO_CRITERIA_UPDATE",
            "TRACKED_ACHIEVEMENT_LIST_CHANGED",
            "TRACKED_RECIPE_UPDATE",
            "SUPER_TRACKING_CHANGED",
        }
    end -- not STOCK

    -- OTF.Update / ObjectiveTracker_Update hooks REMOVED (session 68).
    -- They only called QueueResize, which is already triggered by
    -- the deferred tracker.Update dirty-flag and event handlers above.
    -- Each hooksecurefunc charged Blizzard's full OTF:Update() to us.

    TrackerNS.RestyleAll = function()
        -- Clear skin stamps so the full strip+restyle runs again
        EachTracker(function(tbl)
            if tbl.usedBlocks then
                for _, templateMap in pairs(tbl.usedBlocks) do
                    if type(templateMap) == "table" then
                        for _, questBlock in pairs(templateMap) do
                            if type(questBlock) == "table" then _skinned[questBlock] = nil end
                        end
                    end
                end
            end
            if tbl.Header then SkinHeader(tbl.Header) end
            SkinExistingBlocks(tbl)
        end)
        -- Master "All Objectives" header isn't part of EachTracker's module
        -- list (it belongs to ObjectiveTrackerFrame itself), so re-skin it
        -- explicitly to pick up header-color changes.
        local otfMaster = _G.ObjectiveTrackerFrame
        local mainHeader = otfMaster and (otfMaster.HeaderMenu or otfMaster.Header)
        if mainHeader then SkinHeader(mainHeader) end
        -- Font/color size changes resize existing FontStrings in place, so Blizzard's
        -- cached block heights can be stale until its next natural relayout (any quest
        -- event). We deliberately do NOT force an ObjectiveTrackerFrame:Update() -- see
        -- the FORBIDDEN comment near the top of this file for the taint post-mortem.
    end

    -- Live-update headers, blocks and progress bar fills when the user
    -- changes the UI accent color in Global Settings (nothing reads the
    -- accent under the stock styles).
    if not STOCK and CludesUI and CludesUI.RegAccent then
        CludesUI.RegAccent({
            type = "callback",
            fn = function()
                if TrackerNS.RestyleAll then TrackerNS.RestyleAll() end
            end,
        })
    end
end
