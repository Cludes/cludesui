if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_BlizzardSkin_HUD.lua
--
--  Tooltip progress and status bars, UI widget status bars and the extra
--  action button.
--  Reads CludesUIBlizzardSkin.lua through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIBlizzardSkin.lua or an earlier CUI_BlizzardSkin_*.lua file
-- failed to load.
if not Inner or Inner.last ~= "TooltipVisibility" then return end

local GetFFD = Inner.GetFFD--
--  These are not WINDOWS -- no shell, no per-window style dropdown -- so they
--  live here rather than in a window pack.
--
--  The engine is resolved LAZILY. This file loads BEFORE
--  CludesUIBlizzardSkin_WindowEngine.lua (see the .toc), so ns.WSkin does
--  not exist at main-chunk time and a capture of it at the top of the file
--  would hand this block a nil engine. WS() below reads it on first use, so
--  there is no silent fallback to hand-rolled fonts and colors.
-------------------------------------------------------------------------------
; ------------------------------------------------------------------------------- --  Blizzard HUD reskins: tooltip progress/status bars, UI widget status bar --  covers, and the extra action button.
(function()
    local _WS
    local function WindowSkinNS()
        if _WS then return _WS end
        _WS = mod.WSkin
        -- Force the theme on first use: a tooltip bar on the very first hover
        -- can reach WSkin.Font before the engine's own PLAYER_LOGIN boot and
        -- hand SetFont a nil font path.
        if _WS and _WS.ResolveTheme and not (_WS.Theme and _WS.Theme.fontPath) then
            pcall(_WS.ResolveTheme)
        end
        return _WS
    end

    local FLAT = "Interface\\Buttons\\WHITE8X8"
    local _isSecretV = issecretvalue

    -- House font, with a REPAIR for nonsense sizes. A FontString created with
    -- no font object reports a garbage height (-1566.5 in the field), and any
    -- helper that PRESERVES the current size feeds that straight back, which
    -- surfaces as a flood of "Invalid font height (-1.000000): height must be
    -- > 0". An `or 11` fallback does NOT catch this -- the value is a number,
    -- just a nonsensical one -- so the test is on the SIGN.
    local function HouseFont(fontStr, white)
        if not fontStr or not fontStr.GetFont then return end
        local filePath, size, flags = fontStr:GetFont()
        if type(size) ~= "number" or size <= 0 then
            fontStr:SetFont(filePath or STANDARD_TEXT_FONT, 11, flags or "")
        end
        local W = WindowSkinNS()
        if W then
            if white then
                W.White(fontStr)
            else
                W.Font(fontStr)
            end
        elseif white and fontStr.SetTextColor then
            fontStr:SetTextColor(1, 1, 1)
        end
    end

    -- Tiny 1px BLACK outline. Deliberately not WSkin.AddBorder: that draws the
    -- themed accent border, which on a 15px bar is heavy chrome (the thing that
    -- kept getting rejected). Black at 1px reads as a crisp edge, not a frame.
    -- Idempotent via FFD; drawn on OVERLAY so the fill cannot cover it.
    local function ThinBorder(widget, inset)
        if not widget then return end
        local skinData = GetFFD(widget)
        if skinData.thinBorder then return end
        skinData.thinBorder = true
        -- Recorded as OURS: StripBarArt clears every texture on the bar, and
        -- these live on the bar.
        skinData.owned = skinData.owned or {}
        local idx = inset or 0
        local edges = {
            { "TOPLEFT", -idx, idx, "TOPRIGHT", idx, idx, true },
            { "BOTTOMLEFT", -idx, -idx, "BOTTOMRIGHT", idx, -idx, true },
            { "TOPLEFT", -idx, idx, "BOTTOMLEFT", -idx, -idx, false },
            { "TOPRIGHT", idx, idx, "BOTTOMRIGHT", idx, -idx, false },
        }
        for num = 1, #edges do
            local e = edges[num]
            local tex = widget:CreateTexture(nil, "OVERLAY", nil, 7)
            tex:SetColorTexture(0, 0, 0, 1)
            tex:SetPoint(e[1], widget, e[1], e[2], e[3])
            tex:SetPoint(e[4], widget, e[4], e[5], e[6])
            if e[7] then
                tex:SetHeight(1)
            else
                tex:SetWidth(1)
            end
            skinData.owned[tex] = true
        end
    end

    local function BarFill(barFrame)
        local W = WindowSkinNS()
        if W and W.ApplyBarFill then
            W.ApplyBarFill(barFrame)
        elseif barFrame.SetStatusBarColor then
            local ACC = CUI.CLUDES_GREEN or { r = 0.298, g = 0.788, b = 0.941 }
            barFrame:SetStatusBarColor(ACC.r * 0.8, ACC.g * 0.8, ACC.b * 0.8, 0.95)
        end
    end

    ---------------------------------------------------------------------------
    --  Tooltip progress + status bars.
    --
    --  Two different templates, both POOLED per tooltip, so the same bar frame
    --  comes back over and over and the skin has to survive reuse:
    --    TooltipProgressBarTemplate -- world quest / callings progress ("0%").
    --      A Frame wrapper whose .Bar is the StatusBar, with Border{Left,Mid,
    --      Right} and Left/RightDivider art and a .Bar.Label.
    --    TooltipStatusBarTemplate -- achievement category counts (the green
    --      201/295 bar). The StatusBar itself, with a .Text and one anonymous
    --      border texture. Its green comes from a SetStatusBarColor(0,1,0) in
    --      the template's OnLoad, so it MUST be re-colored per acquire.
    --
    --  Pools live on EACH tooltip (GameTooltip, EmbeddedItemTooltip, ...), so
    --  the hooks read the pool off the tooltip they were handed rather than
    --  assuming GameTooltip.
    ---------------------------------------------------------------------------
    -- `keepFill` is the live fill; OUR OWN textures are spared via FFD.
    --
    -- Without that second guard this wipes the trough and the border edges the
    -- moment a POOLED bar is reused: the first pass creates them (nothing to
    -- clear yet), the next pass clears them, and the bar renders once and then
    -- goes blank.
    local function StripBarArt(barFrame, keepFill)
        local owned = GetFFD(barFrame).owned
        -- Regions taken ONCE. select(i, bar:GetRegions()) inside the loop
        -- rebuilds the entire vararg every iteration.
        local regionList = { barFrame:GetRegions() }
        for idx = 1, #regionList do
            local region = regionList[idx]
            if region and region ~= keepFill and not (owned and owned[region]) and region.IsObjectType then
                if region:IsObjectType("Texture") and region:GetDrawLayer() ~= "HIGHLIGHT" then
                    -- CLEARED, not alpha'd: these bars flare on change through
                    -- animations that drive alpha every frame and win over a
                    -- SetAlpha(0). An animation can animate nothing.
                    if region.SetAtlas then region:SetAtlas("") end
                    if region.SetTexture then region:SetTexture("") end
                    region:SetAlpha(0)
                end
            end
        end
    end

    local function SkinBarCommon(barFrame, keyList)
        if not barFrame or barFrame:IsForbidden() or not barFrame.SetStatusBarTexture then return end
        -- Fill installed FIRST, then re-read, so the "clear everything that is
        -- not the fill" sweep below can never clear the live fill whatever art
        -- Blizzard happened to have there.
        barFrame:SetStatusBarTexture(FLAT)
        local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
        StripBarArt(barFrame, fillTex)
        for idx = 1, #keyList do
            local t = barFrame[keyList[idx]]
            if t and t.SetTexture then
                if t.SetAtlas then t:SetAtlas("") end
                t:SetTexture("")
                t:SetAlpha(0)
            end
        end
        local skinData = GetFFD(barFrame)
        if not skinData.hudTrough then
            -- OPAQUE and lighter than the widget covers' trough. These sit on
            -- the tooltip's own dark backplate rather than over the world, so
            -- 0.12 at 85% was invisible against it: an EMPTY bar (a world quest
            -- at 0%) read as a gap in the tooltip rather than as a bar. It
            -- needs to be legible with NO fill in it at all.
            local troughTex = barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            troughTex:SetColorTexture(0.22, 0.22, 0.22, 1)
            troughTex:SetAllPoints(barFrame)
            skinData.hudTrough = troughTex
            skinData.owned = skinData.owned or {}
            skinData.owned[troughTex] = true
            -- Same 1px black edge as the widget covers. NOT WSkin.AddBorder:
            -- the themed border is what made these read as thick chrome.
            ThinBorder(barFrame)
        end
        BarFill(barFrame)
    end

    local PROGRESS_ART = {
        "BorderLeft",
        "BorderRight",
        "BorderMid",
        "LeftDivider",
        "RightDivider",
    }

    local function SkinProgressBar(widget)
        local barFrame = widget and widget.Bar
        if not barFrame then return end
        SkinBarCommon(barFrame, PROGRESS_ART)
        HouseFont(barFrame.Label, true)
    end

    local function SkinStatusBar(barFrame)
        SkinBarCommon(barFrame, {})
        HouseFont(barFrame.Text, true)
    end

    local function SweepPool(pool, func)
        if not (pool and pool.EnumerateActive) then return end
        local success, iter = pcall(pool.EnumerateActive, pool)
        if success and iter then
            for frame in iter do
                pcall(func, frame)
            end
        end
    end

    -- Post-hooks on the ADD functions, not the SHOW ones: ShowProgressBar and
    -- ShowStatusBar both delegate to Add*, and only Add* runs for the second
    -- and later bars on one tooltip.
    if type(_G.GameTooltip_AddProgressBar) == "function" then
        hooksecurefunc("GameTooltip_AddProgressBar", function(self)
            if self then SweepPool(self.progressBarPool, SkinProgressBar) end
        end)
    end
    if type(_G.GameTooltip_AddStatusBar) == "function" then
        hooksecurefunc("GameTooltip_AddStatusBar", function(self)
            if self then SweepPool(self.statusBarPool, SkinStatusBar) end
        end)
    end

    ---------------------------------------------------------------------------
    --  UI widget status bars -- COVERS, never writes.
    --
    --  Widget values are SECRET inside instanced content. An insecure write
    --  anywhere in a widget tree resurfaces later as "attempt to compare a
    --  secret number value" out of LayoutFrame, far from the code that caused
    --  it. So Blizzard's bar is never touched: an CUI-owned StatusBar parented
    --  to UIParent is merely ANCHORED to it (a write on ours, none on theirs)
    --  and mirrors min/max/value/label through pcall. Any failed or secret read
    --  RETIRES that cover and Blizzard's own bar shows through again;
    --  retirement clears on PLAYER_ENTERING_WORLD.
    --
    --  Containers are DISCOVERED, not hardcoded: the bars in the field are
    --  mostly on NAMEPLATES (NamePlateN.UnitFrame.WidgetContainer.<anon>.Bar),
    --  not on any screen container. ObjectiveTrackerUIWidgetContainer is
    --  deliberately EXCLUDED -- its bars sit inside the tracker's clipped
    --  scrolling layout, where a UIParent-parented cover would float free.
    --
    --  PERFORMANCE (this subsystem caused a real CPU complaint once). The
    --  house standard is TWO separate promises: nothing at all while the
    --  setting is off, and event-driven -- never polled -- while it is on.
    --   - OFF means the events are never REGISTERED. The gate is at
    --     PLAYER_LOGIN, not inside the handlers: an early return in a live
    --     handler still pays for the registration and the dispatch. With the
    --     setting off, hudEv ends up with no events and no script at all.
    --   - There is NO TIMER. Sweeps run from the widget system's own events,
    --     coalesced to at most one per frame, plus a hook on each covered
    --     bar's own DisplayBarValue for the two cases that move a bar with no
    --     event to listen for (see Adopt).
    --   - children taken ONCE per frame, never select(i, f:GetChildren()) in a
    --     loop, which is O(n^2) and lethal on a container walk;
    --   - discovery is LOGIN/ZONE work and never hangs off a per-update event;
    --   - nameplates are tracked via NAME_PLATE_UNIT_ADDED/REMOVED, because
    --     C_NamePlate.GetNamePlates() allocates a fresh table on every call.
    ---------------------------------------------------------------------------
    local HUD = {
        covers = setmetatable({}, { __mode = "k" }), -- blizz bar -> our cover
        retired = setmetatable({}, { __mode = "k" }),
        plates = setmetatable({}, { __mode = "k" }),
        -- Containers a window pack handed us explicitly. Kept SEPARATE from
        -- `containers` because Discover() wipes that list on every zone, and
        -- these cannot be rediscovered -- they are nested inside a window, not
        -- children of UIParent.
        adopted = setmetatable({}, { __mode = "k" }),
        -- OUR OWN cover frames. Load-bearing since covers became children of
        -- Blizzard's frames: a cover is itself a StatusBar sitting inside a
        -- widget container, so without this the next sweep DISCOVERS IT as a
        -- bar to cover, and does so again every tick -- the bar visibly grows
        -- forever. Nothing in this set is ever treated as a Blizzard bar.
        owned = setmetatable({}, { __mode = "k" }),
        -- Bars whose own DisplayBarValue we have already hooked, so a re-adopt
        -- of a pooled bar cannot stack a second hook on it.
        hooked = setmetatable({}, { __mode = "k" }),
        containers = {},
        -- Foreign-set gate state. setIds = the widgetSetIDs currently owned by
        -- containers the sweep actually walks, rebuilt as a side-read of every
        -- sweep; setHooked = containers whose RegisterForWidgetSet is hooked
        -- (a mid-life re-registration books a sweep, which re-records);
        -- setIdsExact = whether every container's set id was readable last
        -- sweep. While false the gate stands down and every widget event
        -- sweeps, exactly as before the gate existed.
        setIds = {},
        setHooked = setmetatable({}, { __mode = "k" }),
        setIdsExact = false,
        -- Set at PLAYER_LOGIN only when the setting is on. Nothing here has
        -- run while this is false.
        installed = false,
        -- Minimum on-screen height for plate-hosted covers, cached from the
        -- setting (0 = off). Seeded at login, re-read only when the cog writes it.
        minPx = 0,
    }

    local NAMED_CONTAINERS = {
        "UIWidgetTopCenterContainerFrame",
        "UIWidgetBelowMinimapContainerFrame",
        "UIWidgetPowerBarContainerFrame",
        "UIWidgetCenterDisplayFrame",
    }

    -- Existing accounts get an EXPLICIT boolean seeded once by the
    -- blizzskin_widget_bars_seed_v1 migration (on only when Reskin Tooltips
    -- AND Reskin Popups and Menus are both on); nil survives only on fresh
    -- installs, where both of those masters default on too -- so nil = on.
    local function CoverEnabled() return not CludesUIDB or CludesUIDB.reskinWidgetBars ~= false end

    -- FORWARD DECLARATION, filled in far below. Adopt installs a hook that has
    -- to call the debounced refresh; that refresh cannot be written until
    -- Sweep exists, and Sweep cannot be written until Adopt does. A
    -- `local function Refresh` written below would NOT be in scope up here --
    -- the name would resolve to a nil global, and the pcall wrapped round the
    -- hook would swallow the failure without a word.
    local Refresh

    -- Read a value and reject it if it is secret. Returns ok, value. Reads
    -- resolve into a LOCAL before any comparison -- a getter called mid-`and`
    -- chain throws on the spot rather than being skipped.
    local function SafeRead(object, method)
        local func = object and object[method]
        if type(func) ~= "function" then return false end
        local success, a, button = pcall(func, object)
        if not success then return false end
        if _isSecretV then
            if a ~= nil and _isSecretV(a) then return false end
            if button ~= nil and _isSecretV(button) then return false end
        end
        return true, a, button
    end

    local function RetireCover(barFrame)
        local c = HUD.covers[barFrame]
        if c then
            c:Hide()
            HUD.covers[barFrame] = nil
        end
        HUD.retired[barFrame] = true
    end

    -- Blizzard's frame art extends BEYOND the bar's own rect: in
    -- UIWidgetTemplateStatusBar, BorderLeft sits at LEFT x=-8 and BorderRight at
    -- RIGHT x=+8, both useAtlasSize (so their HEIGHT is whatever the widget
    -- style ships), and GlowLeft/Right/Center anchor to those borders and PULSE
    -- through GlowPulseAnim. A cover sized to the bar rect therefore leaves a
    -- ring of Blizzard border art visible around it -- which is exactly what
    -- turned up on nameplate bars in game.
    --
    -- The MASK is a separate texture from the trough for a reason: the cover
    -- StatusBar keeps the bar's true rect so the fill proportion stays honest,
    -- while the mask alone spreads out to swallow the frame art. Textures are
    -- not clipped to their parent's bounds, so it can extend past the cover.
    --
    -- Anchored to the border TEXTURES when they exist, so it tracks whatever
    -- atlas size the style uses instead of guessing. Anchoring OUR texture to
    -- THEIRS is still a write on ours only -- the widget tree is untouched.
    -- Ceiling on the vertical overhang the cover will absorb. Blizzard's border
    -- run is a couple of px taller than the bar; a decorative END CAP atlas can
    -- be far taller, and following that is what made the bar giant.
    --
    -- Lowered 5 -> 2 because the bar read as chunky: at 5 a bar whose art is
    -- oversized ends up bar+10, and the pad is pure thickness. The real floor is
    -- Blizzard's own bar height -- the cover cannot go under that without
    -- exposing the art it exists to hide, and shrinking their bar would mean
    -- writing into the widget tree. 2 keeps the common border covered and
    -- refuses anything decorative; a 1px sliver on an unusual style is a better
    -- trade than a permanently fat bar.
    -- ONE small pad, everywhere. THIN IS THE PRIORITY.
    --
    -- A 10px "panel" pad was tried so the cover would fully occlude Blizzard's
    -- border art (31px of texture around a 15px bar) and it made the bars
    -- chunky -- for a benefit nobody asked for. The border art is mostly
    -- transparent padding; chasing its full extent buys nothing and costs
    -- height on every bar. 2px covers the drawn edge.
    --
    -- If a sliver of Blizzard's frame ever shows, raise THIS number -- do not
    -- reintroduce a per-context split. Thin beats perfectly occluded.
    local MAX_VPAD = 2
    -- Plain indexed read, passed BY ARGUMENT to pcall (no closure allocated).
    -- Field access on a widget frame can throw, so even fetching a texture
    -- reference off one has to be guarded.
    local function HUDGet(tbl, key) return tbl[key] end

    -- Anchor the COVER ITSELF out to Blizzard's border art, not to the bar's
    -- inner rect.
    --
    -- Two earlier builds got this wrong in opposite directions. Sizing the
    -- cover to the bar rect left Blizzard's border ring showing around it.
    -- Adding a wider MASK behind the cover hid the ring but produced a dark
    -- margin all the way round, because the fill only ever reached the inner
    -- rect -- which read as an even bigger border.
    --
    -- So the cover takes the whole footprint and the fill spans it. The fill
    -- then represents value/max across a rect ~8px wider each side than
    -- Blizzard's own, but nothing is left on screen to compare it against and
    -- the scale is internally consistent (0% empty, 100% full). A clean bar
    -- beats a technically-truer one wearing a frame.
    -- How much taller Blizzard's border art is than the bar it wraps, halved
    -- (the art is centered on the bar, so the overhang is split top and bottom).
    --
    -- MEASURED, not guessed. A /framestack over a live bar showed the real
    -- shape: the cover sits at frame level 8 over a Bar at level 6, so layering
    -- was never the problem -- but `Bar.BorderCenter` is its own texture and is
    -- TALLER than the Bar, so a cover matching the Bar's height leaves a thin
    -- line of it above and below. That is the "weird small outline".
    --
    -- Capped at MAX_VPAD because BorderLeft/BorderRight are useAtlasSize end
    -- CAPS whose atlas can be far larger than the bar; taking their full height
    -- is what produced the giant-bar round.
    local function VPad(barFrame)
        local okB, barH = pcall(barFrame.GetHeight, barFrame)
        if not okB or type(barH) ~= "number" or barH <= 0 then return 0 end
        local tallest = barH
        for _, key in ipairs({ "BorderCenter", "BorderLeft", "BorderRight" }) do
            local texOk, t = pcall(HUDGet, barFrame, key)
            if texOk and t then
                local okH, hgt = pcall(t.GetHeight, t)
                if okH and type(hgt) == "number" and hgt > tallest then tallest = hgt end
            end
        end
        local padding = (tallest - barH) / 2
        if padding < 0 then padding = 0 end
        if padding > MAX_VPAD then padding = MAX_VPAD end
        return padding
    end

    -- Minimum on-screen cover HEIGHT (real pixels) for PLATE-HOSTED bars, the cog
    -- on "Reskin Widget Bars". A nameplate carries its own scale, so a shrunken
    -- plate drags its widget bar and label down to unreadable; below the floor
    -- the cover SCALES up (label rides along). Growing past Blizzard's rect is
    -- safe only because HideBarArt alphas their art; the "never SMALLER" floor
    -- still stands. Panel bars never scale. 0 = OFF (mirror the rect exactly),
    -- and OFF is the default: opt-in, and it keeps instances -- where the plate
    -- lane is unregistered anyway -- at zero added cost.
    local DEFAULT_MIN_BAR_PX = 0
    local MAX_MIN_BAR_PX = 24
    -- Cap on the correction: a bar mid-fade at 1px would otherwise ask for a slab.
    local MAX_UPSCALE = 3

    -- Cached on HUD, never read per bar per pass (SyncCover can run every frame
    -- while a fill animates); the options cog re-reads it through the seam.
    local function ReadMinPx()
        local val = CludesUIDB and CludesUIDB.widgetBarMinSize
        if type(val) ~= "number" then return DEFAULT_MIN_BAR_PX end
        if val < 0 then return 0 end
        if val > MAX_MIN_BAR_PX then return MAX_MIN_BAR_PX end
        return val
    end

    -- Scale factor that lifts a plate cover to the floor; 1 = leave it alone
    -- (floor off, panel bar, or plate at readable scale).
    local function CoverScale(barFrame, cfg)
        local min = HUD.minPx
        if not (cfg.cuiPlate and type(min) == "number" and min > 0) then return 1 end
        local okH, hgt = pcall(barFrame.GetHeight, barFrame)
        if not okH or type(hgt) ~= "number" or hgt <= 0 then return 1 end
        local okE, es = pcall(barFrame.GetEffectiveScale, barFrame)
        if not okE or type(es) ~= "number" or es <= 0 then return 1 end
        local pixel = hgt * es
        if pixel <= 0 or pixel >= min then return 1 end
        local s = min / pixel
        if s > MAX_UPSCALE then s = MAX_UPSCALE end
        return s
    end

    local function AnchorCover(c, barFrame, padding)
        local s = CoverScale(barFrame, c)
        c:ClearAllPoints()
        if s <= 1 then
            -- EXACTLY the bar's rect. With their art hidden there is nothing to
            -- reach past, so no pad, no overhang, no slab.
            if c.cuiScale ~= 1 then
                c:SetScale(1)
                c.cuiScale = 1
            end
            c.cuiMin = HUD.minPx
            c:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
            c:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
            return
        end
        -- Scaled: CENTER to CENTER with an explicit size, never the two-corner
        -- anchor. Corner anchors DERIVE the size from the bar, so they would
        -- undo the scale as fast as it was applied -- the cover would render
        -- the same size as before with a bigger font in it. CENTER with zero
        -- offsets is the one anchor that needs no scale conversion, so the
        -- cover stays centred on the bar it mirrors and grows symmetrically.
        local okW, wid = pcall(barFrame.GetWidth, barFrame)
        local okH, hgt = pcall(barFrame.GetHeight, barFrame)
        if not (okW and okH) or type(wid) ~= "number" or type(hgt) ~= "number" or wid <= 0 or hgt <= 0 then
            if c.cuiScale ~= 1 then
                c:SetScale(1)
                c.cuiScale = 1
            end
            c.cuiMin = HUD.minPx
            c:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
            c:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
            return
        end
        c:SetScale(s)
        c.cuiScale = s
        c.cuiMin = HUD.minPx
        c:SetSize(wid, hgt)
        c:SetPoint("CENTER", barFrame, "CENTER", 0, 0)
    end

    local function BuildCover(barFrame, isPlate)
        -- Parented to the BAR'S OWN PARENT, not UIParent.
        --
        -- UIParent parenting was the original design ("write on ours, none on
        -- theirs") and it does not reliably draw on top: inside a toplevel
        -- window, Blizzard's subtree and a UIParent child are different
        -- branches, and matching strata + level+2 was NOT enough -- covers
        -- shown, sized and reading fine while the stock bars stayed visible
        -- underneath.
        --
        -- SetParent on OUR OWN frame is still not a write into the widget tree;
        -- nothing on a Blizzard frame is modified. It also makes the cover
        -- inherit their scale and show/hide for free.
        local pointOk, hostFrame = SafeRead(barFrame, "GetParent")
        local c = CreateFrame("StatusBar", nil, (pointOk and hostFrame) or UIParent)
        -- Anchored, never re-parented: position needs no polling because the
        -- anchor does it, including when a nameplate moves.
        c.cuiPad = VPad(barFrame)
        c.cuiScale = 1
        -- Plate-hosted covers are the only ones the size floor applies to.
        c.cuiPlate = isPlate and true or false
        AnchorCover(c, barFrame, c.cuiPad)
        c:SetStatusBarTexture(FLAT)
        -- OPAQUE trough, not the usual 0.85: this one has to hide Blizzard's
        -- bar and border underneath rather than merely sit behind our own fill.
        -- Spans the whole cover, so there is no dark margin anywhere.
        local troughTex = c:CreateTexture(nil, "BACKGROUND", nil, -1)
        troughTex:SetColorTexture(0.10, 0.10, 0.10, 1)
        troughTex:SetAllPoints(c)
        -- Font OBJECT, not a bare CreateFontString: a template-less string
        -- reports a garbage height that any size-preserving helper feeds back
        -- into SetFont.
        local labelText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        labelText:SetPoint("CENTER", c, "CENTER", 0, 0)
        c.cuiLabel = labelText
        HouseFont(labelText, true)
        BarFill(c)
        -- Tiny black outline on EVERY bar, by maintainer call. The earlier "no border"
        -- call was about the THEMED accent border, which is heavy on a 15px
        -- bar; a 1px black edge is what actually defines it.
        ThinBorder(c)

        return c
    end

    -- Blizzard's own bar art, alpha'd to nothing.
    --
    -- This replaces the occluder -- a dark rectangle painted over their frame,
    -- which never blended and read as a patch rather than a skin.
    --
    -- The "never write into a widget tree" rule is about VALUES: widget values
    -- are secret, and reading or comparing one throws. SetAlpha on a TEXTURE
    -- touches no value, no layout and no Lua field, so it does not put secret
    -- data anywhere near our code. Every read of theirs still goes through
    -- SafeRead, and the cover still retires on a secret value.
    --
    -- Re-asserted each sync: these bars are pooled and re-textured per widget.
    -- "Label" is in this list because the COVER draws that text itself, so
    -- Blizzard's is a duplicate sitting underneath. It only shows on strings
    -- with a DESCENDER -- "Friendly" hung a stray y below the bar while
    -- "Revered" looked clean -- because that is the only part reaching past the
    -- cover's bottom edge. Hiding a FontString is the same alpha write as a
    -- texture: no value, no layout, no Lua field.
    local ART = {
        "BGLeft",
        "BGRight",
        "BGCenter",
        "BorderLeft",
        "BorderRight",
        "BorderCenter",
        "Spark",
        "BackgroundGlow",
        "GlowLeft",
        "GlowRight",
        "GlowCenter",
        "Label",
    }
    -- Plate art on the widget FRAME (the bar's parent), outside the bar's own
    -- rect: UIWidgetTemplateStatusBar puts LabelBG and LabelBGDivider there.
    -- Stripping only the bar leaves them showing as a stray background around
    -- it. The frame-level Label is deliberately NOT touched -- it is a separate
    -- caption above the bar, not the duplicate of the bar's own text.
    local PARENT_ART = { "LabelBG", "LabelBGDivider" }
    -- Local copy: KidsOf is declared further down, and a `local function` is
    -- not in scope for code written above it -- the reference would resolve to
    -- a nil global and the pcall around it would swallow the failure silently.
    local function BarKids(frame) return { frame:GetChildren() } end
    local function HideBarArt(barFrame)
        for idx = 1, #ART do
            local texOk, t = pcall(HUDGet, barFrame, ART[idx])
            if texOk and t then pcall(t.SetAlpha, t, 0) end
        end
        local pointOk, hostFrame = SafeRead(barFrame, "GetParent")
        if pointOk and hostFrame then
            for idx = 1, #PARENT_ART do
                local texOk, t = pcall(HUDGet, hostFrame, PARENT_ART[idx])
                if texOk and t then pcall(t.SetAlpha, t, 0) end
            end
        end
        -- DIVIDER TICKS. Blizzard builds these at runtime
        -- (Blizzard_UIWidgetTemplateBase.lua) as ANONYMOUS child FRAMES of the
        -- bar, each holding a .Tex with a widgetstatusbar-bordertick atlas.
        -- Nothing named, so the key sweep above can never reach them and they
        -- survive as stray marks across the bar.
        --
        -- Our cover is parented to the bar's PARENT, not the bar, so it is
        -- never in this list -- no risk of hiding ourselves.
        local keyOk, childList = pcall(BarKids, barFrame)
        if keyOk and childList then
            for idx = 1, #childList do
                local texOk, t = pcall(HUDGet, childList[idx], "Tex")
                if texOk and t then pcall(t.SetAlpha, t, 0) end
            end
        end
    end

    local function SyncCover(barFrame, isPlate)
        if HUD.retired[barFrame] then return false end
        local c = HUD.covers[barFrame]
        if not c then return false end
        -- Pooled bars can migrate between hosts; keep the plate flag current.
        c.cuiPlate = isPlate and true or false

        local shownOk, isShown = SafeRead(barFrame, "IsVisible")
        if not shownOk then
            RetireCover(barFrame)
            return false
        end
        if not isShown then
            if c:IsShown() then c:Hide() end
            return false
        end

        local mmOk, mn, mx = SafeRead(barFrame, "GetMinMaxValues")
        local vOk, val = SafeRead(barFrame, "GetValue")
        if not (mmOk and vOk) then
            RetireCover(barFrame)
            return false
        end

        -- Change-guarded: a ticker re-issuing these ten times a second per bar
        -- is pure waste.
        local cn, cx = c:GetMinMaxValues()
        local changed = false
        if cn ~= mn or cx ~= mx then
            c:SetMinMaxValues(mn, mx)
            changed = true
        end
        if c:GetValue() ~= val then
            c:SetValue(val)
            changed = true
        end

        local blabel = barFrame.Label
        local txt
        if blabel then
            local tOk, t = SafeRead(blabel, "GetText")
            if tOk then txt = t end
        end
        txt = txt or ""
        if c.cuiLabel:GetText() ~= txt then
            c.cuiLabel:SetText(txt)
            changed = true
        end

        -- HideBarArt ONLY on change, never every tick.
        --
        -- It is by far the most expensive thing here: ~13 pcall'd field reads
        -- plus a children walk that allocates a table, and at 10Hz per bar that
        -- is pure waste in the steady state. Blizzard only re-textures a bar
        -- when its widget updates -- which is exactly when a value or label
        -- moves -- so a change IS the re-texture signal. Adopt() also hides at
        -- creation, so a bar is never left showing its own art.
        if changed then HideBarArt(barFrame) end

        -- Follow the bar if it is re-parented (these frames are POOLED, so a
        -- reused bar can land under a different option).
        local pOk, bp = SafeRead(barFrame, "GetParent")
        if pOk and bp and c:GetParent() ~= bp then c:SetParent(bp) end

        -- STRATA FIRST, THEN LEVEL. SetFrameStrata RESETS a frame's level, so
        -- the reverse order silently threw the level away on the first pass and
        -- only self-corrected on the next tick.
        local stOk, st = SafeRead(barFrame, "GetFrameStrata")
        if stOk and st and c:GetFrameStrata() ~= st then c:SetFrameStrata(st) end
        local lvlOk, lvl = SafeRead(barFrame, "GetFrameLevel")
        if lvlOk and type(lvl) == "number" then
            local wanted = lvl + 2
            if c:GetFrameLevel() ~= wanted then c:SetFrameLevel(wanted) end
        end

        -- Re-anchor only when the measured overhang actually changed: Blizzard
        -- re-textures these bars per widget style, and the border height can
        -- differ between one use of a pooled bar and the next.
        -- VPad re-measures four textures; the answer only moves if the bar's
        -- own height does, so it is cached against that.
        local hOk, curH = pcall(barFrame.GetHeight, barFrame)
        local padding = c.cuiPad
        if not hOk or curH ~= c.cuiPadH then
            padding = VPad(barFrame)
            c.cuiPadH = hOk and curH or nil
        end
        -- Second trigger, PLATE covers with the size floor ON only: the bar's
        -- effective scale moves with the plate while its local height does not.
        -- Panel bars and the floor-off default skip the probe entirely (this
        -- runs per bar per sweep, per frame while a fill animates). Thresholded:
        -- plate distance-scaling drifts continuously and an exact compare would
        -- re-anchor every frame.
        local es
        if c.cuiPlate and HUD.minPx > 0 then
            local esOk, curES = pcall(barFrame.GetEffectiveScale, barFrame)
            if esOk and type(curES) == "number" then es = curES end
        end
        local esMoved = (es ~= nil) ~= (c.cuiES ~= nil) or (es and c.cuiES and math.abs(es - c.cuiES) > 0.01)
        -- Third trigger: the floor itself (the cog's slider re-anchors live covers).
        if padding ~= c.cuiPad or esMoved or c.cuiMin ~= HUD.minPx then
            c.cuiPad = padding
            c.cuiES = es
            AnchorCover(c, barFrame, padding)
        end

        if not c:IsShown() then c:Show() end
        return true
    end

    -- The hook body runs INSIDE Blizzard's call stack, so anything thrown here
    -- surfaces as an error in THEIR widget update rather than ours. Every read
    -- inside Sweep is already pcall'd, but the wrapper is the cheap guarantee.
    --
    -- It asks for the DEBOUNCED refresh rather than syncing the bar on the
    -- spot, and that is load-bearing. DisplayBarValue is called from the
    -- middle of UIWidgetTemplateStatusBarMixin:Setup, which AFTERWARDS puts
    -- the glow textures back with SetAlpha(1). Syncing here would consume the
    -- value change -- and with it the HideBarArt trigger, which is
    -- change-guarded -- one step before the art that has to be hidden is
    -- restored, leaving the glows on show with nothing left to re-fire the
    -- hide. Next frame sees the finished widget, which is exactly where the
    -- old ticker saw it.
    local function OnBarValueDisplayed() pcall(Refresh) end

    local function Adopt(barFrame, isPlate)
        if not barFrame or HUD.retired[barFrame] then return end
        if HUD.covers[barFrame] then return end
        -- Never cover one of our own covers (see HUD.owned).
        if HUD.owned[barFrame] then return end
        if barFrame.IsForbidden and barFrame:IsForbidden() then return end
        -- Immediately, before the cover has values to show. Otherwise their bar
        -- is what you watch for the first few ticks while it animates in, which
        -- reads as the skin taking half a second to appear.
        HideBarArt(barFrame)
        local c = BuildCover(barFrame, isPlate)
        HUD.owned[c] = true
        HUD.covers[barFrame] = c

        -- FOLLOW THE BAR'S OWN UPDATE. This is what replaced the 0.1s ticker.
        --
        -- Two things move a widget bar with no event we could ever listen for,
        -- both visible in Blizzard_UIWidget* source:
        --   - a widget with hasTimer is re-processed by its own CONTAINER off
        --     a 1s C_Timer (UIWidgetContainerMixin:RegisterTimerWidget).
        --     UPDATE_UI_WIDGET does not fire for those ticks.
        --   - a fillMotionType other than Instant makes the bar set its OWN
        --     OnUpdate and walk displayedValue toward value over several
        --     frames (UIWidgetBaseStatusBarTemplateMixin:UpdateBar).
        -- Both funnel through DisplayBarValue, the single place the bar calls
        -- SetValue, so that is the update event the widget system actually
        -- has. Hooking it costs nothing when nothing moves and follows a
        -- smooth fill frame by frame when it does -- which is the whole shape
        -- a poll was faking.
        --
        -- hooksecurefunc on ONE FRAME'S method, not a write into the widget
        -- tree: no value is read, compared or stored, and it is the same call
        -- this addon already makes on GameTooltipStatusBar. pcall'd because a
        -- field access on a widget frame can throw on its own.
        if not HUD.hooked[barFrame] and type(barFrame.DisplayBarValue) == "function" then
            HUD.hooked[barFrame] = true
            pcall(hooksecurefunc, barFrame, "DisplayBarValue", OnBarValueDisplayed)
        end
    end

    -- Children as a TABLE, passed by argument to pcall. The obvious spelling,
    -- pcall(function() return { f:GetChildren() } end), allocates a closure on
    -- every frame of every walk.
    local function KidsOf(frame) return { frame:GetChildren() } end

    -- Walk a container for StatusBars. Depth-capped and children taken once.
    local function CollectBars(widget, depth, result, seen)
        if not widget or depth > 4 then return end
        if seen[widget] then return end
        seen[widget] = true
        if not widget.GetChildren then return end
        local okKids, childList = pcall(KidsOf, widget)
        if not okKids or not childList then return end
        for idx = 1, #childList do
            local childFrame = childList[idx]
            -- Skip OUR OWN covers entirely -- not collected, not descended
            -- into. They are StatusBars living inside Blizzard's frames, so
            -- without this the sweep covers its own covers, every tick.
            if childFrame and HUD.owned[childFrame] then childFrame = nil end
            if
                childFrame
                and childFrame.GetObjectType
                and not (childFrame.IsForbidden and childFrame:IsForbidden())
            then
                local texOk, t = pcall(childFrame.GetObjectType, childFrame)
                if texOk and t == "StatusBar" then
                    result[#result + 1] = childFrame
                else
                    CollectBars(childFrame, depth + 1, result, seen)
                end
            end
        end
    end

    -- Login / zone work ONLY. Never call this from a per-update event.
    local function Discover()
        wipe(HUD.containers)
        for idx = 1, #NAMED_CONTAINERS do
            local frame = _G[NAMED_CONTAINERS[idx]]
            if frame then HUD.containers[#HUD.containers + 1] = frame end
        end
        -- Any other UIParent child that is a widget container. Children taken
        -- ONCE; UIParent has a few hundred of them. GetChildren returns every
        -- child as its own value, so a UIParent holding thousands of frames
        -- (something in the session creating them without end) overflows the
        -- Lua stack: past the cap, or if the call fails anyway, only the named
        -- containers above and the adopted ones below are swept.
        local up = _G.UIParent
        local okC, numKids = false, nil
        if up and up.GetNumChildren then
            okC, numKids = pcall(up.GetNumChildren, up)
        end
        local keyOk, childList = false, nil
        if okC and type(numKids) == "number" and numKids <= 4000 then
            keyOk, childList = pcall(KidsOf, up)
        end
        if keyOk and childList then
            for idx = 1, #childList do
                local childFrame = childList[idx]
                if
                    childFrame
                    and childFrame.GetName
                    and not (childFrame.IsForbidden and childFrame:IsForbidden())
                then
                    local okN, num = pcall(childFrame.GetName, childFrame)
                    local pointOk, poolList = pcall(HUDGet, childFrame, "widgetPools")
                    local isWidget = (okN and type(num) == "string" and num:find("^UIWidget"))
                        or (pointOk and poolList ~= nil)
                    -- The tracker's own widget container is excluded on
                    -- purpose: its bars live inside a clipped scrolling layout,
                    -- so a UIParent-parented cover would float free of it.
                    if isWidget and not (okN and num == "ObjectiveTrackerUIWidgetContainer") then
                        HUD.containers[#HUD.containers + 1] = childFrame
                    end
                end
            end
        end
        -- Re-add anything a window pack adopted: the wipe above would otherwise
        -- drop them on the first zone change and they can never be rediscovered.
        for frame in pairs(HUD.adopted) do
            HUD.containers[#HUD.containers + 1] = frame
        end
    end

    -- Scratch tables reused across passes: a sweep can run every frame while a
    -- smooth fill animates, and two fresh tables per pass is needless churn
    -- for the GC.
    HUD.scratchBars, HUD.scratchSeen = {}, {}

    -- Mid-life set changes on a container we sweep (vigor set arming when the
    -- player mounts, a pooled plate container re-targeted) book a sweep, and
    -- that sweep re-records the registry. Named function, created once.
    local function OnWidgetSetRegistered()
        HUD.setIdsExact = false
        Refresh()
    end

    -- Record one container's widget-set id into the gate registry and make
    -- sure its re-registrations are hooked. Returns the running exactness:
    -- an unreadable id (or a secret one) means the registry cannot prove a
    -- foreign event foreign, so the gate must stand down. A container with NO
    -- set (nil id) stays exact -- no widget event can belong to it.
    local function NoteContainerSet(c, exactMatch)
        if not HUD.setHooked[c] then
            local okR, reg = pcall(HUDGet, c, "RegisterForWidgetSet")
            if okR then
                HUD.setHooked[c] = true
                if type(reg) == "function" then
                    pcall(hooksecurefunc, c, "RegisterForWidgetSet", OnWidgetSetRegistered)
                end
            end
        end
        local okS, spellRef = pcall(HUDGet, c, "widgetSetID")
        if not okS then return false end
        if spellRef == nil then return exactMatch end
        if (_isSecretV and _isSecretV(spellRef)) or type(spellRef) ~= "number" then return false end
        HUD.setIds[spellRef] = true
        return exactMatch
    end

    -- No CoverEnabled() check here on purpose. The setting is read ONCE, at
    -- login, and decides whether any of this is wired up at all; re-testing it
    -- per pass would only produce a half-state where the covers are still on
    -- screen but have stopped following their bars.
    local function Sweep()
        local live = 0
        local seen, barList = HUD.scratchSeen, HUD.scratchBars
        wipe(seen)
        wipe(barList)
        wipe(HUD.setIds)
        local exactMatch = true
        for idx = 1, #HUD.containers do
            exactMatch = NoteContainerSet(HUD.containers[idx], exactMatch)
            CollectBars(HUD.containers[idx], 0, barList, seen)
        end
        -- Everything collected past this index came from a plate container.
        local nStatic = #barList
        -- WIDGET CONTAINERS ONLY, never the whole plate. A nameplate base
        -- frame also hosts unit-frame trees (CludesUI's own health and cast
        -- bars are StatusBars parented under it), and a full walk adopts and
        -- art-strips those. The container is found by the same widgetPools
        -- probe Discover uses; with CUI nameplates off it sits one level down,
        -- under the Blizzard unit frame's WidgetContainer key instead.
        for backing in pairs(HUD.plates) do
            local okKids, childList = pcall(KidsOf, backing)
            if okKids and childList then
                for idx = 1, #childList do
                    local childFrame = childList[idx]
                    if childFrame and not (childFrame.IsForbidden and childFrame:IsForbidden()) then
                        local pointOk, poolList = pcall(HUDGet, childFrame, "widgetPools")
                        if pointOk and poolList ~= nil then
                            exactMatch = NoteContainerSet(childFrame, exactMatch)
                            CollectBars(childFrame, 0, barList, seen)
                        else
                            local okW, watchCount = pcall(HUDGet, childFrame, "WidgetContainer")
                            if
                                okW
                                and watchCount
                                and not (watchCount.IsForbidden and watchCount:IsForbidden())
                            then
                                exactMatch = NoteContainerSet(watchCount, exactMatch)
                                CollectBars(watchCount, 0, barList, seen)
                            end
                        end
                    end
                end
            else
                -- A plate whose children could not be read holds containers
                -- the registry cannot see: gate stands down.
                exactMatch = false
            end
        end
        HUD.setIdsExact = exactMatch
        for idx = 1, #barList do
            local isPlate = idx > nStatic
            Adopt(barList[idx], isPlate)
            if SyncCover(barList[idx], isPlate) then live = live + 1 end
        end
        -- Covers whose bar has gone away this pass.
        for barFrame, c in pairs(HUD.covers) do
            if not seen[barFrame] then
                local success, vis = SafeRead(barFrame, "IsVisible")
                if not success or not vis then
                    if c:IsShown() then c:Hide() end
                end
            end
        end
        return live
    end

    -- ONE sweep per frame, on the TRAILING edge. This is what the 0.1s ticker
    -- turned into.
    --
    -- Deferred rather than immediate for two independent reasons:
    --   - UPDATE_UI_WIDGET fires once per widget and several times in a frame
    --     when a set refreshes. Every one of those asking for a full container
    --     walk is the CPU complaint all over again; the flag collapses a burst
    --     into a single pass.
    --   - our handler and the widget container's own are both plain event
    --     registrations, so the order between them is registration order.
    --     Sweeping on the spot can read the value that is ABOUT to change,
    --     and the same event will not come round again to correct it. Landing
    --     after the frame's handlers have all run removes the race.
    --
    -- Flush is created once and reused: no closure is allocated per fire, so a
    -- burst of events costs one boolean test each. Written with `function
    -- Refresh` and no `local` because it FILLS IN the forward declaration far
    -- above -- adding `local` here would create a second, different upvalue
    -- and leave the hook in Adopt calling a nil.
    local pending = false
    local function Flush()
        pending = false
        Sweep()
    end
    function Refresh()
        if pending then return end
        pending = true
        if C_Timer then
            C_Timer.After(0, Flush)
        else
            Flush()
        end
    end

    -- Seam for window packs. Discover() only walks UIParent's DIRECT children,
    -- so a widget container nested inside a window is invisible to it -- and
    -- every PlayerChoice OPTION owns one (that is where the reputation bars on
    -- the weekly cartel picker come from). The pack that knows the frame hands
    -- it over here rather than the sweep guessing at window internals.
    --
    -- Defined AFTER Refresh on purpose: a `local function` is not in scope for
    -- a closure written above it, so declaring this any earlier would capture
    -- a nil global instead of the real Refresh.
    --
    -- PUBLISHED at login and only when the feature is on. The caller in
    -- WindowPacks already tests `type(adopt) ~= "function"`, so leaving it nil
    -- is the honest way to say the system is not running.
    local function HUDWidgetAdopt(boxHolder)
        if not boxHolder or HUD.adopted[boxHolder] then return end
        HUD.adopted[boxHolder] = true
        HUD.containers[#HUD.containers + 1] = boxHolder
        Refresh()
    end

    -- ONE frame, and at load it listens for PLAYER_LOGIN and nothing else.
    --
    -- The setting is not safe to read while this file is executing.
    -- CludesUIDB is a saved variable of the CludesUI addon, not this
    -- one, so what is in it at our main-chunk time depends on that addon's
    -- load order and on whatever defaults or migrations it applies at login --
    -- which is exactly why CoverEnabled() has to treat a nil DB as "on". The
    -- window packs have the same problem and answer it the same way: the
    -- engine's boot frame waits for PLAYER_LOGIN, and a pack whose style is
    -- "off" simply never installs.
    --
    -- So the gate is at LOGIN and it gates the REGISTRATION, not the handler.
    -- With the feature off this frame is left with no events and no OnEvent
    -- script, the window-pack seam is never published, and not one cover is
    -- built. That makes the toggle reload-bound, and the options panel asks
    -- for the reload.
    local hudEv = CreateFrame("Frame")
    hudEv:RegisterEvent("PLAYER_LOGIN")
    hudEv:SetScript("OnEvent", function(self, evt, unitToken)
        if evt == "PLAYER_LOGIN" then
            if not CoverEnabled() then
                -- Inert from here on: nothing left to fire, nothing to skip.
                self:UnregisterAllEvents()
                self:SetScript("OnEvent", nil)
                return
            end
            HUD.installed = true
            self:UnregisterEvent("PLAYER_LOGIN")
            self:RegisterEvent("PLAYER_ENTERING_WORLD")
            self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
            self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            self:RegisterEvent("UPDATE_UI_WIDGET")
            -- The full-refresh partner of UPDATE_UI_WIDGET: the container
            -- mixin registers BOTH, and re-processes every widget it owns on
            -- this one. Missing it left a whole set of bars unswept until
            -- something else happened to fire.
            self:RegisterEvent("UPDATE_ALL_UI_WIDGETS")
            CUI._HUDWidgetAdopt = HUDWidgetAdopt
            -- The options cog's write-through. Published on the same terms as
            -- the adopt seam -- at login, only with the feature on -- so with
            -- the reskin off it is nil and the cog is greyed out anyway.
            -- Re-reads the setting and books one refresh; SyncCover notices the
            -- floor moved and re-anchors every live cover.
            HUD.minPx = ReadMinPx()
            CUI._HUDWidgetSetMinSize = function()
                HUD.minPx = ReadMinPx()
                Refresh()
            end
            -- Looks redundant next to PLAYER_ENTERING_WORLD, which follows
            -- login and does the same two calls. Kept because it makes the
            -- install complete on its own: if the event order ever surprises
            -- us, the cost of being wrong here is the feature silently doing
            -- nothing until the first zone change, against one container walk
            -- per session for keeping it.
            Discover()
            Refresh()
        elseif evt == "PLAYER_ENTERING_WORLD" then
            -- Retirement is per-instance: a bar that handed back secret data
            -- in a delve is fine again in the open world.
            wipe(HUD.retired)
            -- Plate-hosted widget bars are an OPEN-WORLD surface by decision
            -- (2026-08-16): inside instanced content the plate lane is fully
            -- off -- both plate events unregistered (they never enter Lua),
            -- the plate set empty (sweeps walk no plates), and unwalked plate
            -- containers never reach the set registry, so their widget events
            -- die at the foreign-set gate. The rare over-a-plate mechanic bar
            -- simply renders Blizzard-default in instances. Re-registering on
            -- the way out is complete on its own: every plate fires ADDED
            -- after the loading screen, so the set repopulates naturally.
            if IsInInstance() then
                self:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
                self:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
                wipe(HUD.plates)
            else
                self:RegisterEvent("NAME_PLATE_UNIT_ADDED")
                self:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
            end
            Discover()
            Refresh()
        elseif evt == "NAME_PLATE_UNIT_ADDED" then
            local backing = unitToken
                and C_NamePlate
                and C_NamePlate.GetNamePlateForUnit
                and C_NamePlate.GetNamePlateForUnit(unitToken)
            if backing then
                HUD.plates[backing] = true
                Refresh()
            end
        elseif evt == "NAME_PLATE_UNIT_REMOVED" then
            -- No refresh: the cover is a child of the bar's parent, so it
            -- leaves the screen with the plate on its own.
            local backing = unitToken
                and C_NamePlate
                and C_NamePlate.GetNamePlateForUnit
                and C_NamePlate.GetNamePlateForUnit(unitToken)
            if backing then HUD.plates[backing] = nil end
        else
            -- UPDATE_UI_WIDGET / UPDATE_ALL_UI_WIDGETS. Discovery is NOT run
            -- from here: the first build of this system did, and that is
            -- precisely what caused the CPU complaint. Refresh is a flag test
            -- once the frame's pass is already booked.
            --
            -- Foreign-set gate: UPDATE_UI_WIDGET fires for EVERY widget
            -- update anywhere in the UI (tracker timers, scenario widgets,
            -- score frames), and most of those live in frames the sweep never
            -- walks -- each one bought a full container walk that could not
            -- find anything. The payload names its widget set, and Blizzard's
            -- own container gates on exactly this field, so an event whose
            -- set no swept container owns is skipped outright. Every doubt
            -- path (registry inexact, payload missing, unreadable or secret
            -- id) falls through to Refresh -- worst case is today's sweep.
            if evt == "UPDATE_UI_WIDGET" and HUD.setIdsExact and unitToken ~= nil then
                local okS, spellRef = pcall(HUDGet, unitToken, "widgetSetID")
                if
                    okS
                    and spellRef ~= nil
                    and not (_isSecretV and _isSecretV(spellRef))
                    and type(spellRef) == "number"
                    and not HUD.setIds[spellRef]
                then
                    return
                end
            end
            Refresh()
        end
    end)

    ---------------------------------------------------------------------------
    --  Extra action button (ExtraActionButton1).
    --
    --  A SECURE action button: TEXTURES AND TEXCOORDS ONLY. Never Show, Hide,
    --  SetParent or SetPoint the button itself, and never write a field onto
    --  it -- all state goes in the external FFD table.
    --
    --  Blizzard's `style` texture is ~256px of brass ring around a 52px icon,
    --  and it is RE-ASSIGNED for every ability granted (each carries its own
    --  frame art), so the strip runs on OnShow, on UPDATE_EXTRA_ACTIONBAR, and
    --  on a short sweep after each. It CLEARS rather than alphas, because the
    --  button's flash animation drives alpha and would restore it.
    ---------------------------------------------------------------------------
    -- Detach every mask from a texture. ExtraActionButtonTemplate binds an
    -- IconMask to the icon, and a masked texture REJECTS SetTexCoord (hard
    -- error, swallowed by the pcall'd crop -- the icon stayed uncropped). Mask
    -- removal writes to the icon's own mask list, never the secure button.
    -- GetNumMaskTextures is SecretReturnsForAspect: reject before looping.
    local function Unmask(texture)
        if not texture or type(texture.GetNumMaskTextures) ~= "function" then return end
        local okN, num = pcall(texture.GetNumMaskTextures, texture)
        if not okN then return end
        if _isSecretV and num ~= nil and _isSecretV(num) then return end
        if type(num) ~= "number" or num <= 0 then return end
        for idx = num, 1, -1 do
            local okM, m = pcall(texture.GetMaskTexture, texture, idx)
            if okM and m then pcall(texture.RemoveMaskTexture, texture, m) end
        end
    end

    local function StripExtraButton()
        local button = _G.ExtraActionButton1
        if not button or button:IsForbidden() then return end

        -- SCALE FIRST, ABOVE THE SKIN GATE. "Extra Action Button Size" is its
        -- own setting, and it used to sit below this gate -- so once the reskin
        -- defaulted OFF the slider would have silently done nothing for anyone
        -- on defaults. The two are independent settings and now behave that way.
        -- DEFAULT OFF (`== true`, not `~= false`): opt-in, by request. Nil means
        -- the user has never chosen, and that now means "leave Blizzard's
        -- button alone".
        if not (CludesUIDB and CludesUIDB.reskinExtraActionButton == true) then return end

        local skinData = GetFFD(button)
        local look = button.style
        if look then
            if look.SetAtlas then look:SetAtlas("") end
            if look.SetTexture then look:SetTexture("") end
            look:SetAlpha(0)
        end
        if button.icon then
            -- Square the icon and stretch it corner to corner: with the brass
            -- ring gone the 52px art would otherwise float inside a ~256px
            -- frame. These are writes on the icon TEXTURE, never on the secure
            -- button. Re-asserted every pass (Blizzard re-arts the button per
            -- granted ability; a one-shot anchor gets clobbered silently).
            button.icon:ClearAllPoints()
            button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
            button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
            -- Before the crop, never after: SetTexCoord on a masked texture
            -- throws, and the pcall around it would hide that it did nothing.
            Unmask(button.icon)
            pcall(button.icon.SetTexCoord, button.icon, 0.08, 0.92, 0.08, 0.92)
        end
        if not skinData.border then
            -- 1px black edge on its own host frame above the icon, the same
            -- stacking every squared item tile uses. NOT AddBorder: its border
            -- container renders below same-level ARTWORK regions, and the icon
            -- stretched over the full button rect would hide the edge entirely.
            local W = WindowSkinNS()
            if W and W.QualityBorder then
                W.QualityBorder(button, button.icon or button, 0, 0, 0)
                skinData.border = true
            end
        end
        -- Keybind and charge count are deliberately left in Blizzard's outlined
        -- number font: they sit over the icon, where the panel font is unreadable.
    end

    local extraButtonWatch = CreateFrame("Frame")
    local _eabUpdateHooked = false
    extraButtonWatch:RegisterEvent("PLAYER_LOGIN")
    extraButtonWatch:RegisterEvent("UPDATE_EXTRA_ACTIONBAR")
    extraButtonWatch:SetScript("OnEvent", function()
        -- Hook install is unconditional so a mid-session enable takes effect on
        -- the button's next show; the strip and its catch-up timers are gated
        -- here so the default-off state never allocates per event.
        local button = _G.ExtraActionButton1
        if button and not GetFFD(button).showHook then
            GetFFD(button).showHook = true
            button:HookScript("OnShow", StripExtraButton)
        end
        -- ExtraActionBar_Update is where Blizzard re-arts the button (runs from
        -- ActionBarController's own UPDATE_EXTRA_ACTIONBAR handler); hooking it
        -- runs after it by construction instead of racing registration order.
        -- StripExtraAction gates on the setting at its head, so this costs one
        -- call per grant while off.
        if not _eabUpdateHooked and type(_G.ExtraActionBar_Update) == "function" then
            _eabUpdateHooked = true
            hooksecurefunc("ExtraActionBar_Update", StripExtraButton)
        end
        if not (CludesUIDB and CludesUIDB.reskinExtraActionButton == true) then return end
        StripExtraButton()
        if C_Timer then
            C_Timer.After(0, StripExtraButton)
            C_Timer.After(0.3, StripExtraButton)
        end
    end)

    ---------------------------------------------------------------------------
    --  Zone ability button (ZoneAbilityFrame).
    --
    --  Same secure rules as the extra action button: TEXTURES AND TEXCOORDS
    --  ONLY, no field writes onto the button. Three differences that matter:
    --   - the frame art is `.Style` (capital S, not `style`) and is driven by a
    --     per-zone TEXTURE KIT, so it is re-atlased on every ZONE CHANGE, not
    --     only when an ability is granted;
    --   - the buttons are POOLED into .SpellButtonContainer, so there can be
    --     several and they must be walked with EnumerateActive;
    --   - each button also carries a UI-Quickslot2 NORMAL texture -- a ~64px
    --     bevel around a 40px icon. Clearing .Style alone leaves that socket
    --     ring behind, which is most of the chrome in the screenshot.
    ---------------------------------------------------------------------------
    local function StripZoneAbility()
        local frame = _G.ZoneAbilityFrame
        if not frame or frame:IsForbidden() then return end

        -- Shares the extra action button's toggle: both are granted-ability
        -- buttons and get identical treatment, so two settings was a
        -- distinction without a difference. DEFAULT OFF, by request.
        if not (CludesUIDB and CludesUIDB.reskinExtraActionButton == true) then return end

        local look = frame.Style
        if look then
            if look.SetAtlas then look:SetAtlas("") end
            if look.SetTexture then look:SetTexture("") end
            look:SetAlpha(0)
        end

        local sc = frame.SpellButtonContainer
        if not (sc and sc.EnumerateActive) then return end
        local okIter, iter = pcall(sc.EnumerateActive, sc)
        if not (okIter and iter) then return end
        for button in iter do
            if button and button.IsForbidden and not button:IsForbidden() then
                local skinData = GetFFD(button)
                -- Both spellings: .NormalTexture is the parentKey, and
                -- GetNormalTexture() is the button's own accessor. They are
                -- normally the same object, but clearing whichever exists costs
                -- nothing and covers a template that only has one.
                local nt = button.NormalTexture or (button.GetNormalTexture and button:GetNormalTexture())
                if nt then
                    if nt.SetAtlas then nt:SetAtlas("") end
                    if nt.SetTexture then nt:SetTexture("") end
                    nt:SetAlpha(0)
                end
                if button.Icon then
                    if not skinData.iconAnchored then
                        skinData.iconAnchored = true
                        button.Icon:ClearAllPoints()
                        button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
                        button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
                    end
                    pcall(button.Icon.SetTexCoord, button.Icon, 0.08, 0.92, 0.08, 0.92)
                end
                if not skinData.border then
                    -- Same border as the extra action button, so the two
                    -- granted-ability buttons match. Guarded by d.border, which
                    -- matters here because these buttons are POOLED and this
                    -- runs per zone change.
                    local W = WindowSkinNS()
                    if W and W.QualityBorder then
                        W.QualityBorder(button, button.Icon or button, 0, 0, 0)
                        skinData.border = true
                    end
                end
            end
        end
    end

    local zoneAbilityWatch = CreateFrame("Frame")
    zoneAbilityWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- The texture kit is per zone, so every zone crossing re-applies .Style.
    for _, event in ipairs({
        "ZONE_CHANGED",
        "ZONE_CHANGED_NEW_AREA",
        "ZONE_CHANGED_INDOORS",
        "SPELLS_CHANGED",
    }) do
        pcall(zoneAbilityWatch.RegisterEvent, zoneAbilityWatch, event)
    end
    zoneAbilityWatch:SetScript("OnEvent", function()
        -- Same shape as the extra action button's handler: hooks install
        -- unconditionally (the strip self-gates at near-zero cost), the strip
        -- and its catch-up timers only run with the feature ON -- zone changes
        -- are frequent, and default-off must not allocate on every one.
        local frame = _G.ZoneAbilityFrame
        if frame and not GetFFD(frame).zaHooks then
            GetFFD(frame).zaHooks = true
            frame:HookScript("OnShow", StripZoneAbility)
            -- The authoritative hook: this is the method that re-atlases
            -- .Style and refills the button pool.
            if type(frame.UpdateDisplayedZoneAbilities) == "function" then
                hooksecurefunc(frame, "UpdateDisplayedZoneAbilities", StripZoneAbility)
            end
        end
        if not (CludesUIDB and CludesUIDB.reskinExtraActionButton == true) then return end
        StripZoneAbility()
        if C_Timer then
            C_Timer.After(0, StripZoneAbility)
            C_Timer.After(0.3, StripZoneAbility)
        end
    end)
end)()

Inner.last = "HUD"
