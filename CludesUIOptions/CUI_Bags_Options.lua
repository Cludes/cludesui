if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Bags_Options.lua
--  Enhanced Bags Module Options for CludesUI
--  Registers the Bags module and builds the options UI
-------------------------------------------------------------------------------

if not CludesUI._ModuleNS["CludesUIBags"] then
    return
end -- module disabled: no options page

-- DB creation + login seeding live in CludesUIBags_DB.lua (resident; this
-- file is LoadOnDemand and only builds the options page).
local saved = CludesUI._bagsDB

-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, the options addon's first file), which hands a
-- kept page its previous build's frames back reset to new; on any other
-- parent it is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

CludesUI.AtOptionsLogin(function()

    CludesUI:RegisterModule("CludesUIBags", {
        title = "Bags",
        description = "Enhanced inventory system with sidebar categories, item levels, and quality borders.",
        searchTerms = "bags inventory items slots reagent categories columns sidebar",
        pages = { "Bags", "Bank" },
        buildPage = function(page, hostFrame, yOffset)
            if page == "Bank" then
                local okB, resB = pcall(function()
                    local W = CludesUI.Widgets
                    local posY = yOffset
                    local hgt, _
                    -- The Bags module namespace: its bank display resolver
                    local BagsNS = CludesUI._ModuleNS["CludesUIBags"]

                    local function RefreshBank()
                        local bank = _G.CUI_BankFrame
                        if bank and bank.RefreshBank then
                            bank:RefreshBank()
                        end
                    end

                    -- Info label
                    do
                        local fontFile = (CludesUI.GetFontPath("bags")) or "Fonts\\FRIZQT__.TTF"
                        local infoFrame = CreateFrame("Frame", nil, hostFrame)
                        infoFrame:SetSize(hostFrame:GetWidth(), 34)
                        infoFrame:SetPoint("TOP", hostFrame, "TOP", 0, posY - 10)
                        infoFrame._isSpacer = true
                        local line1 = infoFrame:CreateFontString(nil, "OVERLAY")
                        line1:SetFont(fontFile, 15, "")
                        line1:SetTextColor(1, 1, 1, 0.75)
                        line1:SetPoint("TOP", infoFrame, "TOP", 0, 0)
                        line1:SetJustifyH("CENTER")
                        line1:SetText(
                            CludesUI.L(
                                "Right-click a tab in the bank sidebar to rename it or set its deposit filters."
                            )
                        )
                        local line2 = infoFrame:CreateFontString(nil, "OVERLAY")
                        line2:SetFont(fontFile, 15, "")
                        line2:SetTextColor(1, 1, 1, 0.75)
                        line2:SetPoint("TOP", line1, "BOTTOM", 0, -2)
                        line2:SetJustifyH("CENTER")
                        line2:SetText(
                            CludesUI.L(
                                "Window scale, icon zoom and item level settings are shared with the Bags page."
                            )
                        )
                        posY = posY - 50
                    end

                    _, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
                    posY = posY - hgt

                    -- Bank Display: a view over bankListView + bankCompactView (List wins when both are set)
                    _, hgt = W:DualRow(hostFrame, posY, {
                        type = "segmented",
                        text = "Bank Display",
                        tooltip = "How items are arranged in the bank window.",
                        values = { grid = "Grid", list = "List", compact = "Compact" },
                        order = { "grid", "list", "compact" },
                        getValue = function()
                            return BagsNS.BankDisplayMode(saved.profile)
                        end,
                        setValue = function(val)
                            if val == BagsNS.BankDisplayMode(saved.profile) then
                                return
                            end
                            saved.profile.bankListView = (val == "list")
                            saved.profile.bankCompactView = (val == "compact")
                            -- Bags page rows depend on this; rebuild it on next visit
                            CludesUI:InvalidateModulePageCache("CludesUIBags")
                            -- Hide Empty Slots When Grouped greys in List View
                            CludesUI:RefreshPage()
                            CludesUI:ShowConfirmPopup({
                                title = "Reload Required",
                                message = "Bank display changed. A UI reload is needed to apply.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload = true,
                            })
                        end,
                    }, CludesUI.BlankRowCfg())
                    posY = posY - hgt

                    _, hgt = W:SectionHeader(hostFrame, "GROUPING", posY)
                    posY = posY - hgt

                    -- Nest by Expansion | Group by Category
                    _, hgt = W:DualRow(hostFrame, posY, {
                        type = "toggle",
                        text = "Nest by Expansion",
                        tooltip = "In the OneBank and OneWarbank views, split the grid under expansion headers, newest first. Per-tab views are unaffected.",
                        getValue = function()
                            return saved.profile.bankNestByExpansion == true
                        end,
                        setValue = function(val)
                            saved.profile.bankNestByExpansion = val and true or false
                            RefreshBank()
                            CludesUI:RefreshPage()
                        end,
                    }, {
                        type = "toggle",
                        text = "Group by Category",
                        tooltip = "Split items by category -- Armor, Consumables, Professions and so on -- using the same category list, order and renames as the All Items bag view. Nests inside the expansion headers when Nest by Expansion is also on. Categories that split further do so automatically: gear by equipment slot, Professions and Trade Goods by profession and material type.",
                        getValue = function()
                            return saved.profile.bankGroupByCategory == true
                        end,
                        setValue = function(val)
                            saved.profile.bankGroupByCategory = val and true or false
                            RefreshBank()
                            CludesUI:RefreshPage()
                        end,
                    })
                    posY = posY - hgt

                    _, hgt = W:SectionHeader(hostFrame, "SIDEBAR", posY)
                    posY = posY - hgt

                    _, hgt = W:DualRow(hostFrame, posY, {
                        type = "toggle",
                        text = "Category Sidebar",
                        tooltip = "List item categories in the bank sidebar the way the bags sidebar does -- groups such as The Armory with Weapons and Armor under them. Selecting one filters the grid to that category. Categories that split further list their parts as a third level while selected: Professions by profession, Armor by equipment slot, Trade Goods by material. Spans your character bank and warband together, so a category shows everything you own.",
                        getValue = function()
                            return saved.profile.bankCategorySidebar == true
                        end,
                        setValue = function(val)
                            saved.profile.bankCategorySidebar = val and true or false
                            RefreshBank()
                            CludesUI:RefreshPage()
                        end,
                    }, {
                        type = "toggle",
                        text = "Hide Bank Tabs in Sidebar",
                        tooltip = "Drop the individual Tab 1 / Tab 2 / Warbank Tab entries once the category list is doing the navigating. The consolidated views stay. Note that right-clicking a tab entry is the only way to rename a tab or change its deposit filters, so leave this off if you still need that.",
                        disabled = function()
                            return saved.profile.bankCategorySidebar ~= true
                        end,
                        disabledTooltip = "Turn on Category Sidebar first, or the sidebar would have nothing left to navigate with.",
                        getValue = function()
                            return saved.profile.bankHideTabsInSidebar == true
                        end,
                        setValue = function(val)
                            saved.profile.bankHideTabsInSidebar = val and true or false
                            RefreshBank()
                        end,
                    })
                    posY = posY - hgt

                    _, hgt = W:DualRow(hostFrame, posY, {
                        type = "toggle",
                        text = "Hide Empty Slots When Grouped",
                        tooltip = "While either grouping toggle is on, drop the trailing block of empty slots so the view only shows items. Turn this off to keep the free slots visible for depositing.",
                        disabled = function()
                            return saved.profile.bankListView == true
                                or not (
                                    saved.profile.bankNestByExpansion or saved.profile.bankGroupByCategory
                                )
                        end,
                        disabledTooltip = function()
                            if saved.profile.bankListView == true then
                                return "The List View never shows empty slots."
                            end
                            return "Turn on Nest by Expansion or Group by Category first; the flat view has nowhere to move empty slots to."
                        end,
                        rawTooltip = true,
                        getValue = function()
                            return saved.profile.bankHideEmptyWhenNested == true
                        end,
                        setValue = function(val)
                            saved.profile.bankHideEmptyWhenNested = val and true or false
                            RefreshBank()
                        end,
                    }, CludesUI.BlankRowCfg())
                    posY = posY - hgt

                    -- auto deposit/withdraw (not on wow forever: no warband bank there).
                    -- account-wide, so a shared profile never moves anyone's gold
                    local AutoGold = BagsNS and BagsNS.AutoGold
                    if AutoGold then
                        _, hgt = W:SectionHeader(hostFrame, "WARBAND GOLD", posY)
                        posY = posY - hgt
                        local goldRow
                        goldRow, hgt = W:DualRow(hostFrame, posY, {
                            type = "toggle",
                            text = "Auto Deposit/Withdraw",
                            tooltip = "When you open the bank, gold moves between this character and your warband bank so the character keeps the Amount. Gold above it is deposited, and gold missing is withdrawn, as far as the warband bank holds it. Applies to all characters.",
                            getValue = function()
                                return AutoGold.Enabled()
                            end,
                            setValue = function(val)
                                AutoGold.Set("bagAutoGold", val and true or nil)
                                CludesUI:RefreshPage()
                            end,
                        }, {
                            type = "input",
                            text = "Amount",
                            inputStyle = "popup",
                            inputJustify = "CENTER",
                            placeholder = "Amount",
                            inputWidth = 110,
                            tooltip = "The gold each character keeps on hand when the bank opens. Leave it empty to move nothing.",
                            disabled = function()
                                return not AutoGold.Enabled()
                            end,
                            disabledTooltip = "Turn on Auto Deposit/Withdraw first.",
                            getValue = function()
                                local g = AutoGold.Target()
                                return g and tostring(g) or ""
                            end,
                            setValue = function(textValue)
                                -- Digits only, so 5,000 and 5000g read as 5000; empty clears it.
                                local g = tonumber((textValue or ""):gsub("%D", ""), 10)
                                AutoGold.Set("bagAutoGoldAmount", g and math.min(g, 9999999) or nil)
                            end,
                        })
                        posY = posY - hgt
                        if not CludesUI._prebuilding then
                            CludesUI.BuildInlineCog(goldRow._leftRegion, {
                                title = "Auto Deposit/Withdraw",
                                disabled = function()
                                    return not AutoGold.Enabled()
                                end,
                                disabledTooltip = "Auto Deposit/Withdraw",
                                rows = {
                                    {
                                        type = "toggle",
                                        label = "Post Result to Chat",
                                        tooltip = "Posts a chat line with the amount each time gold is deposited or withdrawn.",
                                        get = function()
                                            return AutoGold.ChatEnabled()
                                        end,
                                        set = function(val)
                                            AutoGold.Set("bagAutoGoldChat", val and true or nil)
                                        end,
                                    },
                                },
                            })
                        end
                    end

                    -- offline bank. account-wide, like the data it saves
                    local Offline = BagsNS and BagsNS.Offline
                    if Offline then
                        _, hgt = W:SectionHeader(hostFrame, "OFFLINE BANK", posY)
                        posY = posY - hgt
                        _, hgt = W:DualRow(hostFrame, posY, {
                            type = "toggle",
                            text = "Offline Bank",
                            tooltip = CludesUI.IS_FOREVER
                                    and "Saves each character's bags and bank when you see them. Use the person button by the bags or bank title to see another character's bags or bank, and Bank in the bags sidebar for their bank, from anywhere. Applies to all characters."
                                or "Saves each character's bags and bank, and the warband bank, when you see them. Use the person button by the bags or bank title to see another character's bags or bank, and Bank in the bags sidebar for their bank or the warband bank, from anywhere. Applies to all characters.",
                            getValue = function()
                                return Offline.Enabled()
                            end,
                            setValue = function(val)
                                Offline.Set("bagOfflineBank", val)
                            end,
                        }, {
                            type = "toggle",
                            text = "Tooltip Item Counts",
                            tooltip = CludesUI.IS_FOREVER
                                    and "Item tooltips list how many of that item each of your characters has in their bags and bank. Applies to all characters."
                                or "Item tooltips list how many of that item each of your characters has in their bags and bank, plus the warband bank. Applies to all characters.",
                            getValue = function()
                                return Offline.CountsEnabled()
                            end,
                            setValue = function(val)
                                Offline.Set("bagTooltipCounts", val)
                            end,
                        })
                        posY = posY - hgt
                    end

                    _, hgt = W:Spacer(hostFrame, posY, 20)
                    posY = posY - hgt
                    return math.abs(posY)
                end) -- end pcall
                if not okB then
                    print("|cffff0000[Bank Options ERROR]|r " .. tostring(resB))
                end
                return okB and resB or 0
            end

            if page ~= "Bags" then
                return
            end

            local success, result = pcall(function()
                local W = CludesUI.Widgets
                local Pix = CludesUI.PanelPP
                local posY = yOffset
                local hgt, _

                local function ResetAndRefreshBagLayout()
                    local bags = _G.CUI_Bags
                    if not bags then
                        return
                    end
                    bags._asCols = nil
                    bags._asMaxGridW = nil
                    bags._asMaxH = nil
                    if bags.RefreshInventory then
                        bags:RefreshInventory()
                    end
                end

                -- slot size / spacing: the sliders fire every step while dragging,
                -- so the windows lay out once per frame at most
                local relayoutQueued = false
                local function Relayout()
                    relayoutQueued = false
                    ResetAndRefreshBagLayout()
                    local bank = _G.CUI_BankFrame
                    if bank and bank:IsVisible() and bank.RefreshBank then
                        bank:RefreshBank()
                    end
                end
                local function RelayoutSoon()
                    if relayoutQueued then
                        return
                    end
                    relayoutQueued = true
                    C_Timer.After(0, Relayout)
                end

                local BagsNS = CludesUI._ModuleNS["CludesUIBags"]
                -- Bag Style value: "grid" | "list" | "compact" (any other saved value reads as Grid)
                local function BagDisplayValue()
                    local m = saved.profile.bagDisplayMode
                    return (m == "list" or m == "compact") and m or "grid"
                end
                -- The Display sections are only built while the bags or the bank use
                -- that display: Grid and Compact share one, List has its own.
                local bagList = BagDisplayValue() == "list"
                local anyGrid = not bagList or saved.profile.bankListView ~= true
                local anyList = bagList or saved.profile.bankListView == true
                -- Slot Size, Slot Spacing and Slot Background only draw in Grid and
                -- Compact: they grey out while the bags and the bank both use List
                local function NoSlotGrid()
                    return BagDisplayValue() == "list" and BagsNS.BankDisplayMode(saved.profile) == "list"
                end
                local NO_SLOT_GRID =
                    "This option requires the Grid or Compact display in the bags or the bank"

                ---------------------------------------------------------------------------
                --  LAYOUT
                ---------------------------------------------------------------------------
                _, hgt = W:SectionHeader(hostFrame, "LAYOUT", posY)
                posY = posY - hgt

                -- Bag Style | Default Selected Bag | Window Scale | Frame Strata |
                -- Slot Size | Slot Spacing | Auto-Size to Fit (not in List) |
                -- Background Color | Background Opacity | Slot Background, two per row
                local layoutSlots = {
                    {
                        type = "segmented",
                        text = "Bag Style",
                        values = { grid = "Grid", list = "List", compact = "Compact" },
                        order = { "grid", "list", "compact" },
                        getValue = function()
                            return BagDisplayValue()
                        end,
                        setValue = function(val)
                            if val == BagDisplayValue() then
                                return
                            end
                            saved.profile.bagDisplayMode = val
                            CludesUI:RefreshPage(true)
                            CludesUI:ShowConfirmPopup({
                                title = "Reload Required",
                                message = "Bag display changed. A UI reload is needed to apply.",
                                confirmText = "Reload Now",
                                cancelText = "Later",
                                reload = true,
                            })
                        end,
                    },
                    {
                        type = "dropdown",
                        text = "Default Selected Bag",
                        tooltip = "Which view bags open to by default.",
                        values = { all = "All Items", onebag = "OneBag", multibag = "MultiBag" },
                        order = { "all", "onebag", "multibag" },
                        getValue = function()
                            local t = saved.profile.bagDefaultBagType
                            if t == "all" or t == "onebag" or t == "multibag" then
                                return t
                            end
                            return saved.profile.bagDefaultOneBag and "onebag" or "all"
                        end,
                        setValue = function(val)
                            saved.profile.bagDefaultBagType = val
                            if _G.CUI_Bags and _G.CUI_Bags:IsVisible() and _G.CUI_Bags.RefreshInventory then
                                _G.CUI_Bags:RefreshInventory()
                            end
                            CludesUI:RefreshPage()
                        end,
                    },
                    {
                        type = "slider",
                        text = "Window Scale",
                        min = 50,
                        max = 150,
                        step = 5,
                        getValue = function()
                            return math.floor((saved.profile.bagScale or 1) * 100 + 0.5)
                        end,
                        setValue = function(val)
                            saved.profile.bagScale = val / 100
                            local s = val / 100
                            if _G.CUI_Bags then
                                _G.CUI_Bags:SetScale(s)
                            end
                            if _G.CUI_BagsReagent then
                                _G.CUI_BagsReagent:SetScale(s)
                            end
                            if _G.CUI_BagsWindow then
                                _G.CUI_BagsWindow:SetScale(s)
                            end
                            local bank = _G.CUI_BankFrame
                            if bank and bank:IsVisible() then
                                bank:SetScale(s)
                            end
                        end,
                    },
                    -- Unset reads the retired Allow Windows Over Bags (BagFrameStrata)
                    {
                        type = "dropdown",
                        text = "Frame Strata",
                        tooltip = "Controls the order that overlapping elements display in. Set higher to show above other elements.",
                        values = CludesUI.FRAME_STRATA_LABELS,
                        order = CludesUI.FRAME_STRATA_ORDER_BASE,
                        getValue = function()
                            return BagsNS.BagFrameStrata()
                        end,
                        setValue = function(val)
                            saved.profile.bagFrameStrata = val
                            if _G.CUI_Bags and _G.CUI_Bags.ApplyWindowLayering then
                                _G.CUI_Bags:ApplyWindowLayering()
                            end
                        end,
                    },
                    {
                        type = "slider",
                        text = "Slot Size",
                        min = 24,
                        max = 56,
                        step = 1,
                        tooltip = "Size of each item slot in bags and bank.",
                        disabled = NoSlotGrid,
                        disabledTooltip = NO_SLOT_GRID,
                        getValue = function()
                            return saved.profile.bagSlotSize or 34
                        end,
                        setValue = function(val)
                            saved.profile.bagSlotSize = val
                            RelayoutSoon()
                        end,
                    },
                    {
                        type = "slider",
                        text = "Slot Spacing",
                        min = 0,
                        max = 12,
                        step = 1,
                        tooltip = "Space between item slots in bags and bank.",
                        disabled = NoSlotGrid,
                        disabledTooltip = NO_SLOT_GRID,
                        getValue = function()
                            return saved.profile.bagSlotSpacing or 4
                        end,
                        setValue = function(val)
                            saved.profile.bagSlotSpacing = val
                            RelayoutSoon()
                        end,
                    },
                }
                -- The List display has no Auto-Size to Fit (its rows take the grip-set width)
                if not bagList then
                    layoutSlots[#layoutSlots + 1] = {
                        type = "toggle",
                        text = "Auto-Size to Fit",
                        -- WoW Forever and the Compact display fit the content, with no normal-size floor
                        tooltip = (CludesUI.IS_FOREVER or saved.profile.bagDisplayMode == "compact")
                                and "Grow the bag window (more columns + taller, keeping its shape) so all of the active tab's slots are visible without scrolling. It only grows while open -- switching to a bigger tab enlarges it, smaller tabs keep the size -- and resets when you close the bags."
                            or "Grow the bag window (more columns + taller, keeping its shape) so all of the active tab's slots are visible without scrolling. It only grows while open -- switching to a bigger tab enlarges it, smaller tabs keep the size -- and resets when you close the bags. Never smaller than your normal size.",
                        getValue = function()
                            return saved.profile.bagAutoSize == true
                        end,
                        setValue = function(val)
                            saved.profile.bagAutoSize = val
                            ResetAndRefreshBagLayout()
                        end,
                    }
                end
                -- background color/opacity and slot background, same for bags and bank
                local function ApplyBackgrounds()
                    local bags, bank = _G.CUI_Bags, _G.CUI_BankFrame
                    if bags then
                        BagsNS.ApplyWindowBackground(bags.bg, bags.bgOverlay)
                    end
                    if bank then
                        BagsNS.ApplyWindowBackground(bank._bg, bank._bgOverlay)
                    end
                end
                layoutSlots[#layoutSlots + 1] = {
                    type = "colorpicker",
                    text = "Background Color",
                    hasAlpha = true,
                    tooltip = "The tint over the bag and bank window backgrounds. Its opacity sets how strong the tint is.",
                    getValue = function()
                        local c = saved.profile.bagBgColor
                        if c then
                            return c.r, c.g, c.b, c.a or 0.25
                        end
                        return 0, 0, 0, 0.25
                    end,
                    setValue = function(r, g, b, a)
                        saved.profile.bagBgColor = { r = r, g = g, b = b, a = a }
                        ApplyBackgrounds()
                    end,
                }
                layoutSlots[#layoutSlots + 1] = {
                    type = "slider",
                    text = "Background Opacity",
                    min = 0,
                    max = 100,
                    step = 5,
                    tooltip = "How see-through the bag and bank window backgrounds are. Items, the header and the sidebar stay as they are.",
                    getValue = function()
                        return saved.profile.bagBgOpacity or 100
                    end,
                    setValue = function(val)
                        saved.profile.bagBgOpacity = val
                        ApplyBackgrounds()
                    end,
                }
                layoutSlots[#layoutSlots + 1] = {
                    type = "colorpicker",
                    text = "Slot Background",
                    hasAlpha = true,
                    tooltip = "The color and opacity of empty item slots in the bags and bank.",
                    disabled = NoSlotGrid,
                    disabledTooltip = NO_SLOT_GRID,
                    getValue = function()
                        local c = saved.profile.bagSlotBgColor
                        if c then
                            return c.r, c.g, c.b, c.a or 1
                        end
                        return 1, 1, 1, 1
                    end,
                    setValue = function(r, g, b, a)
                        saved.profile.bagSlotBgColor = { r = r, g = g, b = b, a = a }
                        -- the picker fires every frame while dragging: retint, don't re-lay out
                        BagsNS.RetintSlotBackgrounds()
                    end,
                }
                for i = 1, #layoutSlots, 2 do
                    _, hgt = W:DualRow(
                        hostFrame,
                        posY,
                        layoutSlots[i],
                        layoutSlots[i + 1] or CludesUI.BlankRowCfg()
                    )
                    posY = posY - hgt
                end

                ---------------------------------------------------------------------------
                --  CATEGORIES
                ---------------------------------------------------------------------------
                _, hgt = W:SectionHeader(hostFrame, "CATEGORIES", posY)
                posY = posY - hgt

                -- Show Pinned Items | Show Recent Items (each with inline cog for OneBag)
                local pinRecRow
                pinRecRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Show Pinned Items",
                    tooltip = "Show the Pinned Items category in the sidebar and content grid.",
                    getValue = function()
                        return saved.profile.bagShowPinnedItems ~= false
                    end,
                    setValue = function(val)
                        saved.profile.bagShowPinnedItems = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                        CludesUI:RefreshPage()
                    end,
                }, {
                    type = "toggle",
                    text = "Show Recent Items",
                    tooltip = "Show the Recent Items category in the sidebar and content grid for newly acquired items.",
                    getValue = function()
                        return saved.profile.bagShowRecentItems ~= false
                    end,
                    setValue = function(val)
                        saved.profile.bagShowRecentItems = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                        CludesUI:RefreshPage()
                    end,
                })
                posY = posY - hgt

                -- Inline cog for Show Pinned Items
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(pinRecRow._leftRegion, {
                        chain = false,
                        disabled = function()
                            return saved.profile.bagShowPinnedItems == false
                        end,
                        disabledTooltip = "Show Pinned Items",
                        title = "Pinned Items Options",
                        rows = {
                            {
                                type = "toggle",
                                label = "Show in OneBag/MultiBag",
                                get = function()
                                    return saved.profile.bagPinnedInOneBag ~= false
                                end,
                                set = function(val)
                                    saved.profile.bagPinnedInOneBag = val
                                    if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                        _G.CUI_Bags:RefreshInventory()
                                    end
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Hide Items in Their Categories",
                                tooltip = "Pinned items show only in Pinned Items, not in their categories or Recent Items.",
                                get = function()
                                    return saved.profile.bagHidePinnedInCategories == true
                                end,
                                set = function(val)
                                    saved.profile.bagHidePinnedInCategories = val
                                    if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                        _G.CUI_Bags:RefreshInventory()
                                    end
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Dim Items in OneBag/MultiBag",
                                tooltip = "Dims pinned items in their bag slots, since they also show in Pinned Items.",
                                disabled = function()
                                    return saved.profile.bagPinnedInOneBag == false
                                end,
                                disabledTooltip = "Show in OneBag/MultiBag",
                                get = function()
                                    return saved.profile.bagDimPinnedInOneBag == true
                                end,
                                set = function(val)
                                    saved.profile.bagDimPinnedInOneBag = val
                                    if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                        _G.CUI_Bags:RefreshInventory()
                                    end
                                end,
                            },
                            -- Account-wide, on unless turned off: only the off state is stored.
                            {
                                type = "toggle",
                                label = "Pins per Character",
                                tooltip = "Each character keeps its own pinned items, starting from the shared ones.",
                                get = function()
                                    return not (CludesUIDB and CludesUIDB.bagPinsPerCharacter == false)
                                end,
                                set = function(val)
                                    if not CludesUIDB then
                                        return
                                    end
                                    if val then
                                        CludesUIDB.bagPinsPerCharacter = nil
                                    else
                                        CludesUIDB.bagPinsPerCharacter = false
                                    end
                                    if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                        _G.CUI_Bags:RefreshInventory()
                                    end
                                end,
                            },
                        },
                    })
                end

                -- Inline cog for Show Recent Items: "Show in OneBag"
                if not CludesUI._prebuilding then
                    CludesUI.BuildInlineCog(pinRecRow._rightRegion, {
                        chain = false,
                        disabled = function()
                            return saved.profile.bagShowRecentItems == false
                        end,
                        disabledTooltip = "Show Recent Items",
                        title = "Recent Items Options",
                        rows = {
                            {
                                type = "toggle",
                                label = "Show in OneBag/MultiBag",
                                get = function()
                                    return saved.profile.bagRecentInOneBag == true
                                end,
                                set = function(val)
                                    saved.profile.bagRecentInOneBag = val
                                    if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                        _G.CUI_Bags:RefreshInventory()
                                    end
                                end,
                            },
                            {
                                type = "toggle",
                                label = "Show Clear Button",
                                get = function()
                                    return saved.profile.bagShowRecentClear == true
                                end,
                                set = function(val)
                                    saved.profile.bagShowRecentClear = val
                                    if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                        _G.CUI_Bags:RefreshInventory()
                                    end
                                end,
                            },
                        },
                    })
                end

                -- Enabled Categories | Hide Categories with 0 Items
                local catRow
                catRow, hgt = W:DualRow(hostFrame, posY, { type = "label", text = "Enabled Categories" }, {
                    type = "toggle",
                    text = "Hide Categories with 0 Items",
                    tooltip = "Hide sidebar categories that have no items in them.",
                    getValue = function()
                        return saved.profile.bagHideEmptyCategories ~= false
                    end,
                    setValue = function(val)
                        saved.profile.bagHideEmptyCategories = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                })
                posY = posY - hgt

                -- Enabled Categories dropdown (left side)
                if not CludesUI._prebuilding then
                    -- Function, not a static table: re-evaluated on every menu open, so the
                    -- list follows split-mode toggles and set changes without a page rebuild.
                    local function BuildCatItems()
                        local catItems = {}
                        if _G.CUI_CategoryManager then
                            local cats = _G.CUI_CategoryManager:GetCategories()
                            for ci, category in ipairs(cats) do
                                -- isEquipSet excluded: per-character keys, governed by the split toggle instead
                                -- isVirtual excluded: runtime-only, its addon owns it (a saved key would outlive it)
                                if
                                    not category.isCatchAll
                                    and not category.isPinned
                                    and not category.isRecent
                                    and not category.isReagentBag
                                    and not category.isSpecialBag
                                    and not category.isEquipSet
                                    and not category.isVirtual
                                then
                                    catItems[#catItems + 1] =
                                        { key = category._defaultName, label = category.name }
                                end
                            end
                        end
                        return catItems
                    end

                    if #BuildCatItems() > 0 then
                        local leftRgn = catRow._leftRegion
                        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                            leftRgn,
                            210,
                            leftRgn:GetFrameLevel() + 2,
                            BuildCatItems,
                            function(defName)
                                local dc = saved.profile.bagDisabledCategories
                                return not (dc and dc[defName])
                            end,
                            function(defName, val)
                                if not saved.profile.bagDisabledCategories then
                                    saved.profile.bagDisabledCategories = {}
                                end
                                if val then
                                    saved.profile.bagDisabledCategories[defName] = nil
                                else
                                    saved.profile.bagDisabledCategories[defName] = true
                                end
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    C_Timer.After(0.1, function()
                                        if _G.CUI_Bags:IsVisible() then
                                            _G.CUI_Bags:RefreshInventory()
                                        end
                                    end)
                                end
                                CludesUI:RefreshPage()
                            end,
                            nil,
                            10,
                            true
                        )
                        Pix.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                        leftRgn._control = cbDD
                        leftRgn._lastInline = nil
                        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                    end
                end

                -- Hide 'Add Category' Tab | Split Set Gear by Set
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Hide 'Add Category' Tab",
                    tooltip = "Hides the Add Category button at the bottom of the bag sidebar.",
                    getValue = function()
                        return saved.profile.bagHideAddCategory or false
                    end,
                    setValue = function(val)
                        saved.profile.bagHideAddCategory = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                }, {
                    type = "toggle",
                    text = "Split Set Gear by Set",
                    tooltip = "Show one sub-category per equipment set (named after the set) nested under Item Set Gear. Gear in several sets goes to the first one.",
                    getValue = function()
                        return saved.profile.bagSplitSetGearBySet == true
                    end,
                    setValue = function(val)
                        saved.profile.bagSplitSetGearBySet = val
                        -- Re-resolves the selected view by stable key (indices shift)
                        if _G.CUI_Bags and _G.CUI_Bags.InvalidateSetCategories then
                            _G.CUI_Bags.InvalidateSetCategories()
                        elseif _G.CUI_CategoryManager then
                            _G.CUI_CategoryManager:OnEquipmentSetsChanged()
                        end
                        if _G.CUI_Bags and _G.CUI_Bags.UpdateSetEventRegistration then
                            _G.CUI_Bags.UpdateSetEventRegistration()
                        end
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                })
                posY = posY - hgt

                -- Category Title Size (also on the Fonts page) | Hide Sidebar Icons When Collapsed
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "slider",
                    text = "Category Title Size",
                    min = 8,
                    max = 16,
                    step = 1,
                    tooltip = "Font size for the category titles above your items.",
                    getValue = function()
                        return saved.profile.bagCatTitleSize or 11
                    end,
                    setValue = function(val)
                        saved.profile.bagCatTitleSize = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                }, {
                    type = "toggle",
                    text = "Hide Sidebar Icons When Collapsed",
                    tooltip = "Hides a collapsed sidebar; its expand arrow sits by the Inventory title.",
                    getValue = function()
                        return saved.profile.bagHideSidebarIconsCollapsed == true
                    end,
                    setValue = function(val)
                        saved.profile.bagHideSidebarIconsCollapsed = val and true or false
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                })
                posY = posY - hgt

                if anyGrid then
                    ---------------------------------------------------------------------------
                    --  DISPLAY (GRID / COMPACT)
                    ---------------------------------------------------------------------------
                    _, hgt = W:SectionHeader(hostFrame, "DISPLAY (GRID / COMPACT)", posY)
                    posY = posY - hgt

                    -- Show Item Level: Never / Default Colors / Custom Colored (+ the Gear
                    -- Track Rank cog and an inline swatch left of it, live only under
                    -- Custom Colored) | Item Level Text Size. A view over the saved keys:
                    -- showItemlevelInBags (false = Never) and itemlevelUseCustomColor
                    -- (Custom Colored); viewing the page writes nothing.
                    local function IlvlMode()
                        if saved.profile.showItemlevelInBags == false then
                            return "never"
                        end
                        return saved.profile.itemlevelUseCustomColor and "custom" or "default"
                    end
                    local ilvlRow
                    ilvlRow, hgt = W:DualRow(hostFrame, posY, {
                        type = "dropdown",
                        text = "Show Item Level",
                        tooltip = "Display item levels on equipment items in the inventory, in their usual colors or in one color of your choice.",
                        values = { never = "Never", default = "Default Colors", custom = "Custom Colored" },
                        order = { "never", "default", "custom" },
                        getValue = IlvlMode,
                        setValue = function(val)
                            local p = saved.profile
                            p.showItemlevelInBags = val ~= "never"
                            if val ~= "never" then
                                p.itemlevelUseCustomColor = val == "custom"
                            end
                            -- The first Custom Colored pick starts from white.
                            if val == "custom" and not p.itemlevelCustomColor then
                                p.itemlevelCustomColor = { r = 1, g = 1, b = 1 }
                            end
                            if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                _G.CUI_Bags:RefreshInventory()
                            end
                            CludesUI:RefreshPage() -- the swatch's and the cog's disabled states
                        end,
                    }, {
                        type = "slider",
                        text = "Item Level Text Size",
                        min = 8,
                        max = 16,
                        step = 1,
                        tooltip = "Font size for item level numbers on equipment items.",
                        getValue = function()
                            return saved.profile.itemlevelFontSize or 12
                        end,
                        setValue = function(val)
                            saved.profile.itemlevelFontSize = val
                            if _G.CUI_Bags and _G.CUI_Bags.RefreshTextSizes then
                                _G.CUI_Bags:RefreshTextSizes()
                            end
                            local bank = _G.CUI_BankFrame
                            if bank and bank.RefreshTextSizes then
                                bank:RefreshTextSizes()
                            end
                        end,
                    })
                    posY = posY - hgt

                    -- Show Item Level's inlines: the cog nearest the control (Show Gear
                    -- Track Rank, live while item levels show: the rank only renders
                    -- beside them), then the Custom Colored swatch left of it.
                    if not CludesUI._prebuilding then
                        local region = ilvlRow._leftRegion
                        CludesUI.BuildInlineCog(region, {
                            disabled = function()
                                return saved.profile.showItemlevelInBags == false
                            end,
                            disabledTooltip = "Show Item Level",
                            title = "Item Level Options",
                            rows = {
                                {
                                    type = "toggle",
                                    label = "Show Gear Track Rank",
                                    get = function()
                                        return saved.profile.bagShowTrackRank or false
                                    end,
                                    set = function(val)
                                        saved.profile.bagShowTrackRank = val
                                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                            _G.CUI_Bags:RefreshInventory()
                                        end
                                    end,
                                },
                            },
                        })

                        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                            region,
                            region:GetFrameLevel() + 5,
                            function()
                                local c = saved.profile.itemlevelCustomColor
                                if c then
                                    return c.r, c.g, c.b, 1
                                end
                                return 1, 1, 1, 1
                            end,
                            function(r, g, b)
                                saved.profile.itemlevelCustomColor = { r = r, g = g, b = b }
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                            end,
                            false,
                            20
                        )
                        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
                        region._lastInline = colorSwatch
                        local swatchBlock = CreateFrame("Frame", nil, colorSwatch)
                        swatchBlock:SetAllPoints()
                        swatchBlock:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
                        swatchBlock:EnableMouse(true)
                        swatchBlock:SetScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(
                                colorSwatch,
                                CludesUI.DisabledTooltip(
                                    "This option requires Show Item Level to be set to Custom Colored"
                                )
                            )
                        end)
                        swatchBlock:SetScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                        local function UpdateIlvlSwatch()
                            local off = IlvlMode() ~= "custom"
                            colorSwatch:SetAlpha(off and 0.3 or 1)
                            swatchBlock:SetShown(off)
                        end
                        UpdateIlvlSwatch()
                        CludesUI.RegisterWidgetRefresh(UpdateIlvlSwatch)
                        CludesUI.RegisterWidgetRefresh(updateSwatch)
                    end

                    -- Show BoE / Warbound Text (+ inline cog: Text Size) | Item Count Text Size
                    local bindRow
                    bindRow, hgt = W:DualRow(hostFrame, posY, {
                        type = "toggle",
                        text = "Show BoE / Warbound Text",
                        tooltip = "Display Binds on Equipped / Warbound until Equipped on equipment items in your bags and bank.",
                        getValue = function()
                            return saved.profile.bagDisplayBindType
                        end,
                        setValue = function(val)
                            saved.profile.bagDisplayBindType = val
                            if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                _G.CUI_Bags:RefreshInventory()
                            end
                            local bank = _G.CUI_BankFrame
                            if bank and bank.RefreshBank then
                                bank:RefreshBank()
                            end
                            CludesUI:RefreshPage() -- refresh the cog's disabled state
                        end,
                    }, {
                        type = "slider",
                        text = "Item Count Text Size",
                        min = 8,
                        max = 16,
                        step = 1,
                        tooltip = "Font size for stack counts, keystone levels, and dungeon abbreviations.",
                        getValue = function()
                            return saved.profile.bagCountFontSize or 11
                        end,
                        setValue = function(val)
                            saved.profile.bagCountFontSize = val
                            if _G.CUI_Bags and _G.CUI_Bags.RefreshTextSizes then
                                _G.CUI_Bags:RefreshTextSizes()
                            end
                            local bank = _G.CUI_BankFrame
                            if bank and bank.RefreshTextSizes then
                                bank:RefreshTextSizes()
                            end
                        end,
                    })
                    posY = posY - hgt

                    -- Inline cog (RESIZE) on Show BoE / Warbound Text: text size
                    -- Skipped during the hidden search pre-build: that pass swaps the
                    -- widget factory for the frameless absorber, so DualRow returns a
                    -- plain table and CreateFrame/SetPoint against its regions throw.
                    -- Nothing is lost from the index -- cog popup rows are not search
                    -- entries, and the host rows were already registered by DualRow.
                    -- Same for every region-chrome block below.
                    if not CludesUI._prebuilding then
                        CludesUI.BuildInlineCog(bindRow._leftRegion, {
                            chain = false,
                            disabled = function()
                                return not saved.profile.bagDisplayBindType
                            end,
                            disabledTooltip = "Show BoE / Warbound Text",
                            title = "BoE / Warbound Text Options",
                            rows = {
                                {
                                    type = "slider",
                                    label = "Text Size",
                                    min = 8,
                                    max = 16,
                                    step = 1,
                                    get = function()
                                        return saved.profile.bagBindTypeFontSize or 11
                                    end,
                                    set = function(val)
                                        saved.profile.bagBindTypeFontSize = val
                                        if _G.CUI_Bags and _G.CUI_Bags.RefreshTextSizes then
                                            _G.CUI_Bags:RefreshTextSizes()
                                        end
                                        local bank = _G.CUI_BankFrame
                                        if bank and bank.RefreshTextSizes then
                                            bank:RefreshTextSizes()
                                        end
                                    end,
                                },
                            },
                        })
                    end

                    -- Show Set Name on Gear (+ inline cog: Text Size) | Nest by Expansion:
                    -- bags only, so not built while only the bank uses this display
                    if not bagList then
                        local setNameRow
                        setNameRow, hgt = W:DualRow(hostFrame, posY, {
                            type = "toggle",
                            text = "Show Set Name on Gear",
                            tooltip = "Display the equipment set's name at the bottom of bag items that belong to one of your equipment sets.",
                            getValue = function()
                                return saved.profile.bagShowSetGearName == true
                            end,
                            setValue = function(val)
                                saved.profile.bagShowSetGearName = val
                                if _G.CUI_Bags and _G.CUI_Bags.UpdateSetEventRegistration then
                                    _G.CUI_Bags.UpdateSetEventRegistration()
                                end
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                                CludesUI:RefreshPage() -- refresh the cog's disabled state
                            end,
                        }, {
                            type = "toggle",
                            text = "Nest by Expansion",
                            tooltip = "In the All Items bag view, show each category's items under indented expansion sub-headers (newest expansions first), even when everything in that category is from one expansion.",
                            getValue = function()
                                return saved.profile.bagNestByExpansion == true
                            end,
                            setValue = function(val)
                                saved.profile.bagNestByExpansion = val and true or false
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                            end,
                        })
                        posY = posY - hgt

                        -- Inline cog (RESIZE) on Show Set Name on Gear: text size
                        if not CludesUI._prebuilding then
                            CludesUI.BuildInlineCog(setNameRow._leftRegion, {
                                chain = false,
                                disabled = function()
                                    return saved.profile.bagShowSetGearName ~= true
                                end,
                                disabledTooltip = "Show Set Name on Gear",
                                title = "Set Name Text Options",
                                rows = {
                                    {
                                        type = "slider",
                                        label = "Text Size",
                                        min = 7,
                                        max = 14,
                                        step = 1,
                                        get = function()
                                            return saved.profile.bagSetNameFontSize or 9
                                        end,
                                        set = function(val)
                                            saved.profile.bagSetNameFontSize = val
                                            if _G.CUI_Bags and _G.CUI_Bags.RefreshTextSizes then
                                                _G.CUI_Bags:RefreshTextSizes()
                                            end
                                        end,
                                    },
                                },
                            })
                        end
                    end
                end

                if anyList then
                    ---------------------------------------------------------------------------
                    --  DISPLAY (LIST)
                    ---------------------------------------------------------------------------
                    _, hgt = W:SectionHeader(hostFrame, "DISPLAY (LIST)", posY)
                    posY = posY - hgt

                    -- Left Gap | Right Gap | Row Height | Text Size | Round Icons |
                    -- Section Gold Value | Split by Type | Hide Row Stripes, two per row.
                    -- Section Gold Value and Split by Type are bags only, so they drop
                    -- out while only the bank uses the List display.
                    local listSlots = {
                        {
                            type = "slider",
                            text = "Left Gap",
                            min = 0,
                            max = 50,
                            step = 1,
                            tooltip = "Empty space between this side of the bag and bank lists and their rows.",
                            getValue = function()
                                return saved.profile.bagListGapL or 15
                            end,
                            setValue = function(val)
                                saved.profile.bagListGapL = val
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                                local bank = _G.CUI_BankFrame
                                if bank and bank.RefreshBank then
                                    bank:RefreshBank()
                                end
                            end,
                        },
                        {
                            type = "slider",
                            text = "Right Gap",
                            min = 0,
                            max = 50,
                            step = 1,
                            tooltip = "Empty space between this side of the bag and bank lists and their rows.",
                            getValue = function()
                                return saved.profile.bagListGapR or 23
                            end,
                            setValue = function(val)
                                saved.profile.bagListGapR = val
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                                local bank = _G.CUI_BankFrame
                                if bank and bank.RefreshBank then
                                    bank:RefreshBank()
                                end
                            end,
                        },
                        {
                            type = "slider",
                            text = "Row Height",
                            min = 16,
                            max = 32,
                            step = 1,
                            tooltip = "Height of each row in the bag and bank lists. Icons shrink to fit short rows.",
                            getValue = function()
                                return saved.profile.bagListRowHeight or 24
                            end,
                            setValue = function(val)
                                saved.profile.bagListRowHeight = val
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                                local bank = _G.CUI_BankFrame
                                if bank and bank.RefreshBank then
                                    bank:RefreshBank()
                                end
                            end,
                        },
                        -- Also on the Fonts page (List Text Size)
                        {
                            type = "slider",
                            text = "Text Size",
                            min = 8,
                            max = 16,
                            step = 1,
                            tooltip = "Text size of the bag and bank lists.",
                            getValue = function()
                                return saved.profile.bagListFontSize or 11
                            end,
                            setValue = function(val)
                                saved.profile.bagListFontSize = val
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                                local bank = _G.CUI_BankFrame
                                if bank and bank.RefreshBank then
                                    bank:RefreshBank()
                                end
                            end,
                        },
                        {
                            type = "toggle",
                            text = "Round Icons",
                            tooltip = "Show the item icons in the bag and bank lists as circles instead of squares.",
                            getValue = function()
                                return saved.profile.bagListRoundIcons == true
                            end,
                            setValue = function(val)
                                saved.profile.bagListRoundIcons = val and true or false
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                                local bank = _G.CUI_BankFrame
                                if bank and bank.RefreshBank then
                                    bank:RefreshBank()
                                end
                            end,
                        },
                    }
                    local splitSlot
                    if bagList then
                        listSlots[#listSlots + 1] = {
                            type = "toggle",
                            text = "Section Gold Value",
                            tooltip = "Show the total vendor sell price of each section's items next to its count in the bag list.",
                            getValue = function()
                                return saved.profile.bagListSectionValue == true
                            end,
                            setValue = function(val)
                                saved.profile.bagListSectionValue = val and true or false
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                            end,
                        }
                        splitSlot = #listSlots + 1
                        listSlots[splitSlot] = {
                            type = "label",
                            text = "Split by Type",
                            tooltip = "In the list, group the checked kinds of items under sub-headers by armor type, weapon type, or profession and material. Group Gear by Slot sorts the gear in its categories by slot instead.",
                        }
                    end
                    listSlots[#listSlots + 1] = {
                        type = "toggle",
                        text = "Hide Row Stripes",
                        tooltip = "Remove the shading on every other row in the bag and bank lists.",
                        getValue = function()
                            return saved.profile.bagListHideStripes == true
                        end,
                        setValue = function(val)
                            saved.profile.bagListHideStripes = val and true or false
                            if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                _G.CUI_Bags:RefreshInventory()
                            end
                            local bank = _G.CUI_BankFrame
                            if bank and bank.RefreshBank then
                                bank:RefreshBank()
                            end
                        end,
                    }
                    local splitRow, splitLeft
                    for i = 1, #listSlots, 2 do
                        local row
                        row, hgt = W:DualRow(
                            hostFrame,
                            posY,
                            listSlots[i],
                            listSlots[i + 1] or CludesUI.BlankRowCfg()
                        )
                        posY = posY - hgt
                        if splitSlot == i or splitSlot == i + 1 then
                            splitRow, splitLeft = row, splitSlot == i
                        end
                    end

                    -- Split by Type checkbox dropdown: a view over the three split toggles
                    if splitRow and not CludesUI._prebuilding then
                        local splitRgn = splitLeft and splitRow._leftRegion or splitRow._rightRegion
                        local SPLIT_TYPES = {
                            { key = "bagListSplitArmor", label = "Armor" },
                            { key = "bagListSplitWeapons", label = "Weapons" },
                            { key = "bagListSplitProfessions", label = "Professions" },
                        }
                        local splitDD, splitDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                            splitRgn,
                            210,
                            splitRgn:GetFrameLevel() + 2,
                            SPLIT_TYPES,
                            function(key)
                                return saved.profile[key] == true
                            end,
                            function(key, val)
                                saved.profile[key] = val and true or false
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    _G.CUI_Bags:RefreshInventory()
                                end
                            end,
                            nil,
                            10
                        )
                        Pix.Point(splitDD, "RIGHT", splitRgn, "RIGHT", -20, 0)
                        splitRgn._control = splitDD
                        splitRgn._lastInline = nil
                        CludesUI.RegisterWidgetRefresh(splitDDRefresh)
                    end
                end

                ---------------------------------------------------------------------------
                --  EXTRAS (every display)
                ---------------------------------------------------------------------------
                _, hgt = W:SectionHeader(hostFrame, "EXTRAS", posY)
                posY = posY - hgt

                -- Merge Duplicate Items | Group Gear by Slot (+ inline cog: Compact Slot Groups)
                local gearRow
                gearRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Merge Duplicate Items",
                    tooltip = "Show copies of the same item in separate bag slots as one icon or row, with their counts added together. Gear is never merged, and OneBag and MultiBag always show every slot. Merging pauses while the mail, trade, auction house, vendor, bank or guild bank window is open.",
                    getValue = function()
                        return saved.profile.bagMergeDuplicates ~= false
                    end,
                    setValue = function(val)
                        saved.profile.bagMergeDuplicates = val and true or false
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                }, {
                    type = "toggle",
                    text = "Group Gear by Slot",
                    tooltip = "In The Armory and the Weapons / Trinkets, Armor, and Item Set Gear category views, group items under equip-slot sub-headers (Head, Shoulders, Chest, Cosmetic, ...). Does not add sidebar views.",
                    disabled = function()
                        local dc = saved.profile.bagDisabledCategories
                        return dc and dc["Armor"] == true
                    end,
                    disabledTooltip = "Armor",
                    getValue = function()
                        return saved.profile.bagArmoryGroupBySlot == true
                    end,
                    setValue = function(val)
                        saved.profile.bagArmoryGroupBySlot = val and true or false
                        ResetAndRefreshBagLayout()
                        CludesUI:RefreshPage()
                    end,
                })
                posY = posY - hgt

                -- Inline cog for Group Gear by Slot: Compact Slot Groups. Grid display
                -- only, so not built for any other Bag Style.
                if not CludesUI._prebuilding and BagDisplayValue() == "grid" then
                    local function SlotCogState()
                        local dc = saved.profile.bagDisabledCategories
                        if dc and dc["Armor"] == true then
                            return true, "Armor"
                        end
                        if saved.profile.bagArmoryGroupBySlot ~= true then
                            return true, "Group Gear by Slot"
                        end
                        return false
                    end
                    local gearRgn = gearRow._rightRegion
                    CludesUI.BuildInlineCog(gearRgn, {
                        anchorTo = gearRgn._control,
                        disabled = function()
                            return (SlotCogState())
                        end,
                        disabledTooltip = function()
                            local _, why = SlotCogState()
                            return why
                        end,
                        title = "Armory Slot Group Options",
                        rows = {
                            {
                                type = "toggle",
                                label = "Compact Slot Groups",
                                tooltip = "Place smaller Armory slot groups beside each other and fill the unused end of each row with empty-slot blocks. Large groups still use full rows.",
                                get = function()
                                    return saved.profile.bagCompactArmorySlotGroups == true
                                end,
                                set = function(val)
                                    saved.profile.bagCompactArmorySlotGroups = val and true or false
                                    ResetAndRefreshBagLayout()
                                end,
                            },
                        },
                    })
                end

                -- Junk Item Visuals | Quality Item Border
                local junkRow
                junkRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "label",
                    text = "Junk Item Visuals",
                    tooltip = "Choose how junk items look in the bags and bank.",
                }, {
                    type = "toggle",
                    text = "Quality Item Border",
                    tooltip = "Draw a border in the item's quality color around item icons in the bags and bank. Round list icons have no border.",
                    getValue = function()
                        return saved.profile.bagQualityBorder ~= false
                    end,
                    setValue = function(val)
                        saved.profile.bagQualityBorder = val and true or false
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                        if _G.CUI_BagsReagent and _G.CUI_BagsReagent.RefreshInventory then
                            _G.CUI_BagsReagent:RefreshInventory()
                        end
                        if _G.CUI_BagsWindow and _G.CUI_BagsWindow.RefreshBags then
                            _G.CUI_BagsWindow:RefreshBags()
                        end
                        local bank = _G.CUI_BankFrame
                        if bank and bank.RefreshBank then
                            bank:RefreshBank()
                        end
                    end,
                })
                posY = posY - hgt

                -- Junk Item Visuals dropdown (left side). The coin badge is drawn
                -- only by the bag window's Grid and Compact displays, so the List
                -- display lists Desaturate alone.
                if not CludesUI._prebuilding then
                    local JUNK_VISUALS = {
                        {
                            key = "bagDesaturateJunkItems",
                            label = "Desaturate",
                            tooltip = "Display junk items in a greyed-out style.",
                        },
                    }
                    if not bagList then
                        JUNK_VISUALS[2] = {
                            key = "bagShowJunkCoin",
                            label = "Show Coin Icon",
                            tooltip = "Show a coin on the corner of each junk item's icon.",
                        }
                    end
                    local junkRgn = junkRow._leftRegion
                    local junkDD, junkDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                        junkRgn,
                        210,
                        junkRgn:GetFrameLevel() + 2,
                        JUNK_VISUALS,
                        function(key)
                            return saved.profile[key] == true
                        end,
                        function(key, val)
                            saved.profile[key] = val and true or false
                            if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                _G.CUI_Bags:RefreshInventory()
                            end
                            local bank = _G.CUI_BankFrame
                            if bank and bank.RefreshBank then
                                bank:RefreshBank()
                            end
                        end,
                        nil,
                        10
                    )
                    Pix.Point(junkDD, "RIGHT", junkRgn, "RIGHT", -20, 0)
                    junkRgn._control = junkDD
                    junkRgn._lastInline = nil
                    CludesUI.RegisterWidgetRefresh(junkDDRefresh)
                end

                -- Bag Top Bar Icons (+ inline cog: Sort to Bottom) | Gold Tracking and History
                local iconsRow
                iconsRow, hgt = W:DualRow(hostFrame, posY, {
                    type = "label",
                    text = "Bag Top Bar Icons",
                    tooltip = "Choose which icons show in the bag window's top bar; the Junk Icon is the Junk Marker.",
                }, {
                    type = "toggle",
                    text = "Gold Tracking and History",
                    tooltip = "Track and display gold amounts from all your characters on hover.",
                    getValue = function()
                        return CludesUI.GetGoldLedger().IsTracking()
                    end,
                    setValue = function(val)
                        CludesUI.GetGoldLedger().SetTracking(val)
                    end,
                })
                posY = posY - hgt

                -- Bag Top Bar Icons dropdown (left side), its Sort Options cog to the left
                if not CludesUI._prebuilding then
                    local TOP_BAR_ICONS = {
                        { key = "bagShowBagsIcon", label = "Bags Icon" },
                        { key = "bagShowJunkIcon", label = "Junk Icon" },
                        { key = "bagShowQuickIcon", label = "Quick Actions Icon" },
                        { key = "bagShowSortIcon", label = "Sort Icon" },
                    }
                    local leftRgn = iconsRow._leftRegion
                    local iconsDD, iconsDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                        leftRgn,
                        210,
                        leftRgn:GetFrameLevel() + 2,
                        TOP_BAR_ICONS,
                        function(key)
                            return saved.profile[key] ~= false
                        end,
                        function(key, val)
                            saved.profile[key] = val and true or false
                            local bags = _G.CUI_Bags
                            if bags and bags.SyncHeaderIcons then
                                if key == "bagShowJunkIcon" then
                                    -- The Junk category exists only while the Junk Marker is
                                    -- on: rebuild the categories and re-resolve the selected
                                    -- view by stable key
                                    bags.InvalidateSetCategories()
                                    bags:SyncHeaderIcons()
                                    bags:RefreshInventory()
                                    -- An open bank greys (or stops greying) its junk too
                                    local bank = _G.CUI_BankFrame
                                    if bank then
                                        bank:RefreshBank()
                                    end
                                    -- WoW Forever's Junk Items window lists marked items only while the marker is on
                                    _G.CUI_CategoryManager:OnJunkChanged()
                                else
                                    bags:SyncHeaderIcons()
                                end
                            end
                            CludesUI:RefreshPage() -- the Sort Options cog follows Sort Icon
                        end,
                        nil,
                        10
                    )
                    Pix.Point(iconsDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                    leftRgn._control = iconsDD
                    leftRgn._lastInline = nil
                    CludesUI.RegisterWidgetRefresh(iconsDDRefresh)

                    CludesUI.BuildInlineCog(leftRgn, {
                        disabled = function()
                            return saved.profile.bagShowSortIcon == false
                        end,
                        disabledTooltip = "Sort Icon",
                        title = "Sort Options",
                        rows = {
                            {
                                type = "toggle",
                                label = "Sort to Bottom",
                                tooltip = "Sorting normally packs your items into the first free slots, at the top of the grid. Turn this on to pack them into the last slots instead, so the empty slots end up at the top. The item order itself does not change. This affects the OneBag, MultiBag and bank views -- category views fill their own grid with no gaps, so there is nothing to move. MultiBag and the bank use Blizzard's own sorting, so while this is on it also flips Blizzard's cleanup direction; turning it back off restores the direction you had.",
                                get = function()
                                    return saved.profile.bagSortToBottom == true
                                end,
                                set = function(val)
                                    val = val and true or false
                                    local p = saved.profile
                                    if val == (p.bagSortToBottom == true) then
                                        return
                                    end
                                    -- MultiBag and the bank sort through Blizzard, whose
                                    -- fill direction is a real game setting shared with
                                    -- their Clean Up button. Stash the player's own value
                                    -- on the way in so switching back off restores it
                                    -- instead of leaving ours behind.
                                    if
                                        C_Container.SetSortBagsRightToLeft
                                        and C_Container.GetSortBagsRightToLeft
                                    then
                                        if val then
                                            p.bagSortBlizzRTLWas = C_Container.GetSortBagsRightToLeft()
                                                    and true
                                                or false
                                            C_Container.SetSortBagsRightToLeft(false)
                                        elseif p.bagSortBlizzRTLWas ~= nil then
                                            C_Container.SetSortBagsRightToLeft(p.bagSortBlizzRTLWas)
                                            p.bagSortBlizzRTLWas = nil
                                        end
                                    end
                                    p.bagSortToBottom = val
                                end,
                            },
                        },
                    })
                end

                -- Enabled Currencies | Icon Zoom
                local currRow
                currRow, hgt = W:DualRow(hostFrame, posY, { type = "label", text = "Enabled Currencies" }, {
                    type = "slider",
                    text = "Icon Zoom",
                    min = 0,
                    max = 0.20,
                    step = 0.01,
                    tooltip = "Crops the border of every item icon in bags and bank. 0 shows the full icon.",
                    getValue = function()
                        return saved.profile.bagItemIconZoom or 0.08
                    end,
                    setValue = function(val)
                        saved.profile.bagItemIconZoom = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshIconZoom then
                            _G.CUI_Bags:RefreshIconZoom()
                        end
                        local bank = _G.CUI_BankFrame
                        if bank and bank.RefreshIconZoom then
                            bank:RefreshIconZoom()
                        end
                    end,
                })
                posY = posY - hgt

                -- Enabled Currencies dropdown (left side)
                if not CludesUI._prebuilding then
                    local currencyItems = {}
                    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize then
                        -- Expand all collapsed headers so we can see every currency,
                        -- then restore them after scanning.
                        local collapsedHeaders = {}
                        local position = 1
                        while position <= C_CurrencyInfo.GetCurrencyListSize() do
                            local details = C_CurrencyInfo.GetCurrencyListInfo(position)
                            if details and details.isHeader and not details.isHeaderExpanded then
                                collapsedHeaders[#collapsedHeaders + 1] = position
                                C_CurrencyInfo.ExpandCurrencyList(position, true)
                            end
                            position = position + 1
                        end

                        local listSize = C_CurrencyInfo.GetCurrencyListSize()
                        for i = 1, listSize do
                            local details = C_CurrencyInfo.GetCurrencyListInfo(i)
                            if details then
                                if details.isHeader then
                                    currencyItems[#currencyItems + 1] =
                                        { isHeader = true, label = details.name }
                                else
                                    local itemLink = C_CurrencyInfo.GetCurrencyListLink(i)
                                    if itemLink then
                                        local cID = C_CurrencyInfo.GetCurrencyIDFromLink(itemLink)
                                        if cID then
                                            local cInfo = C_CurrencyInfo.GetCurrencyInfo(cID)
                                            local cName = cInfo and cInfo.name or details.name
                                            currencyItems[#currencyItems + 1] = {
                                                key = cID,
                                                label = cName,
                                                icon = (cInfo and cInfo.iconFileID) or details.iconFileID,
                                            }
                                        end
                                    end
                                end
                            end
                        end

                        -- Restore collapsed headers (iterate in reverse so indices stay valid)
                        for i = #collapsedHeaders, 1, -1 do
                            C_CurrencyInfo.ExpandCurrencyList(collapsedHeaders[i], false)
                        end
                    end

                    -- Retired lane: tracked ids that are no longer in Blizzard's
                    -- currency list (seasonal currencies get delisted at rollover)
                    -- would otherwise have NO checkbox anywhere -- stuck tracked
                    -- forever, with no way off the bag footer. Built from the
                    -- tracked set itself so unchecking always works; names resolve
                    -- via GetCurrencyInfo, which still answers for delisted ids.
                    -- Never auto-pruned: what renders stays the user's choice.
                    do
                        local co = CludesUI._BagsCurrencyOrder and CludesUI._BagsCurrencyOrder()
                        if co then
                            local listed = {}
                            for _, item in ipairs(currencyItems) do
                                if item.key then
                                    listed[item.key] = true
                                end
                            end
                            local retired = {}
                            for cID in pairs(co) do
                                if type(cID) == "number" and not listed[cID] then
                                    retired[#retired + 1] = cID
                                end
                            end
                            table.sort(retired)
                            if #retired > 0 then
                                -- Top of the menu: a leftover seasonal currency is
                                -- exactly what this dropdown gets opened to remove,
                                -- so it never hides under the live headers.
                                local block = {
                                    { isHeader = true, label = CludesUI.L("Retired") },
                                }
                                for _, cID in ipairs(retired) do
                                    local cInfo = C_CurrencyInfo.GetCurrencyInfo
                                        and C_CurrencyInfo.GetCurrencyInfo(cID)
                                    block[#block + 1] = {
                                        key = cID,
                                        label = (cInfo and cInfo.name) or ("Currency " .. cID),
                                        icon = cInfo and cInfo.iconFileID,
                                    }
                                end
                                for i = #block, 1, -1 do
                                    table.insert(currencyItems, 1, block[i])
                                end
                            end
                        end
                    end

                    if #currencyItems > 0 then
                        local leftRgn = currRow._leftRegion
                        local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                            leftRgn,
                            210,
                            leftRgn:GetFrameLevel() + 2,
                            currencyItems,
                            -- Tracked currencies are per character (the module owns
                            -- the accessor and its first-use seeding; see
                            -- CurrencyOrder in CludesUIBags.lua). Reading
                            -- db.profile.currencyOrder here would edit the legacy
                            -- shared table that nothing renders any more.
                            function(cID)
                                local co = CludesUI._BagsCurrencyOrder and CludesUI._BagsCurrencyOrder()
                                return co and co[cID] and true or false
                            end,
                            function(cID, val)
                                local co = CludesUI._BagsCurrencyOrder and CludesUI._BagsCurrencyOrder()
                                if not co then
                                    return
                                end
                                if val then
                                    local maxOrder = 0
                                    for _, ord in pairs(co) do
                                        if type(ord) == "number" and ord > maxOrder then
                                            maxOrder = ord
                                        end
                                    end
                                    co[cID] = maxOrder + 1
                                else
                                    co[cID] = nil
                                end
                                if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                                    C_Timer.After(0.1, function()
                                        if _G.CUI_Bags:IsVisible() then
                                            _G.CUI_Bags:RefreshInventory()
                                        end
                                    end)
                                end
                            end,
                            nil,
                            10,
                            true
                        )
                        Pix.Point(cbDD, "RIGHT", leftRgn, "RIGHT", -20, 0)
                        leftRgn._control = cbDD
                        leftRgn._lastInline = nil
                        CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                    end
                end

                -- Stack Splitter
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "toggle",
                    text = "Stack Splitter",
                    tooltip = "Also use the split dialog with Auto Split in OneBag, MultiBag, the reagent bag, the bank and the guild bank, replacing Blizzard's split popup there. All Items and category views always use it.",
                    getValue = function()
                        return saved.profile.bagStackSplitter == true
                    end,
                    setValue = function(val)
                        saved.profile.bagStackSplitter = val and true or false
                    end,
                }, {
                    type = "toggle",
                    text = "Open Bags with Character Window",
                    tooltip = "The bags automatically open when the character window is opened and close again when the character window is closed.",
                    getValue = function()
                        return saved.profile.bagOpenWithCharacter == true
                    end,
                    setValue = function(val)
                        saved.profile.bagOpenWithCharacter = val and true or false
                        BagsNS.ToggleBagsWithCharacterFrame()
                    end,
                })
                posY = posY - hgt

                -- Auto Open Bags | Auto Close Bags: absent or true = selected
                local autoRow
                autoRow, hgt = W:DualRow(
                    hostFrame,
                    posY,
                    { type = "label", text = "Auto Open Bags" },
                    { type = "label", text = "Auto Close Bags" }
                )
                posY = posY - hgt
                local function AutoWindowsDropdown(region, setting)
                    local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                        region,
                        210,
                        region:GetFrameLevel() + 2,
                        BagsNS.BAG_AUTO_WINDOWS,
                        function(key)
                            return BagsNS.BagAutoWindowOn(setting, key)
                        end,
                        function(key, val)
                            local t = saved.profile[setting]
                            if not t then
                                t = {}
                                saved.profile[setting] = t
                            end
                            if val then
                                t[key] = nil
                            else
                                t[key] = false
                            end
                        end
                    )
                    Pix.Point(cbDD, "RIGHT", region, "RIGHT", -20, 0)
                    region._control = cbDD
                    region._lastInline = nil
                    CludesUI.RegisterWidgetRefresh(cbDDRefresh)
                end
                AutoWindowsDropdown(autoRow._leftRegion, "bagAutoOpenWindows")
                AutoWindowsDropdown(autoRow._rightRegion, "bagAutoCloseWindows")

                -- Slot Count Format | Separate Reagent Slots
                _, hgt = W:DualRow(hostFrame, posY, {
                    type = "dropdown",
                    text = "Slot Count Format",
                    tooltip = "Show used or free inventory slots.",
                    values = { used_total = "Used / Total", free_total = "Free / Total", free = "Free" },
                    order = { "used_total", "free_total", "free" },
                    getValue = function()
                        local val = saved.profile.bagSlotCountFormat
                        return (val == "free_total" or val == "free") and val or "used_total"
                    end,
                    setValue = function(val)
                        saved.profile.bagSlotCountFormat = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                }, CludesUI.IS_FOREVER and CludesUI.BlankRowCfg() or {
                    type = "toggle",
                    text = "Separate Reagent Slots",
                    tooltip = "Show reagent bag slots on a separate line.",
                    getValue = function()
                        return saved.profile.bagSeparateReagentSlots == true
                    end,
                    setValue = function(val)
                        saved.profile.bagSeparateReagentSlots = val
                        if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then
                            _G.CUI_Bags:RefreshInventory()
                        end
                    end,
                })
                posY = posY - hgt

                _, hgt = W:Spacer(hostFrame, posY, 20)
                posY = posY - hgt
                return math.abs(posY)
            end) -- end pcall
            if not success then
                print("|cffff0000[Bags Options ERROR]|r " .. tostring(result))
            end
            return success and result or 0
        end,
        onReset = function()
            -- Wipe per-profile data and re-apply defaults
            local bdb = CludesUI._bagsDB
            local p = bdb and bdb.profile
            if p then
                for k in pairs(p) do
                    p[k] = nil
                end
                if bdb._profileDefaults then
                    CludesUI.Lite.DeepMergeDefaults(p, bdb._profileDefaults)
                end
            end
            if _G.CUI_Bags and _G.CUI_Bags.ApplyWindowLayering then
                _G.CUI_Bags:ApplyWindowLayering()
            end
            -- Wipe per-character data from root DB
            if CludesUIDB then
                CludesUIDB.bagPinnedItems = nil
                CludesUIDB.bagPinnedByChar = nil
                CludesUIDB.bagPinsPerCharacter = nil
                CludesUIDB.bagItemAssignments = nil
                CludesUIDB.bagJunkPrev = nil
                -- Legacy gold stores: they stay on disk until a gold module loads and absorbs them.
                CludesUIDB.characterGold = nil
                CludesUIDB.dataBarsGold = nil
                CludesUIDB.warbandGold = nil
                CludesUIDB.bagCurrencyByChar = nil
                -- offline bank: its switches and every saved inventory
                CludesUIDB.bagOfflineBank = nil
                CludesUIDB.bagTooltipCounts = nil
                -- auto deposit/withdraw
                CludesUIDB.bagAutoGold = nil
                CludesUIDB.bagAutoGoldAmount = nil
                CludesUIDB.bagAutoGoldChat = nil
            end
            local bagsNS = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIBags"]
            local Offline = bagsNS and bagsNS.Offline
            if Offline then
                Offline.Wipe()
                Offline.Sync()
                Offline.SyncButton()
            end
            if bagsNS and bagsNS.AutoGold then
                bagsNS.AutoGold.Sync()
            end
            CludesUI:InvalidatePageCache()
        end,
    })
end)
