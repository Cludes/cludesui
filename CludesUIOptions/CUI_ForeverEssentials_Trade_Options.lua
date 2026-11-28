if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_ForeverEssentials_Trade_Options.lua
--  Forever Tools > Trade: trade and bags: professions, the market, mail and alts, junk items, bag space, restock and reminders, fishing and Glimmer. Each section reads and writes its own feature's
--  keys (the same ones it had on the General page).
-------------------------------------------------------------------------------
if not CUI._ModuleNS["CludesUIForeverEssentials"] then return end

function _G._CUI_BuildForeverTradePage(_, hostFrame, yOffset)
    local W = CUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    CUI:ClearContentHeader()

    ---------------------------------------------------------------------------
    --  PROFESSIONS
    ---------------------------------------------------------------------------
    local PF = CUI._Professions
    if PF then
        local function pOff() return not PF.Get("enabled") end
        local function Set(key, val)
            PF.Cfg()[key] = val
            PF.Apply()
        end
        _, height = W:SectionHeader(hostFrame, "PROFESSIONS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Professions",
            tooltip = "A window (/cprof) for each of your professions: the next rank and where to get it, the recipes you know that still give skill, and every recipe you have not learned with where it comes from. Open your profession window once so it knows what you have learned.",
            getValue = function() return not pOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "labeledButton",
            text = "Professions Window",
            buttonText = "Open",
            width = 90,
            disabled = pOff,
            tooltip = "Opens the Professions window. Also /cprof.",
            onClick = function() PF.Open() end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Next Rank Alert",
            disabled = pOff,
            tooltip = "A chat line once when a profession is ready for its next rank, with where to train it. /cprof rank checks now.",
            getValue = function() return PF.Get("rankAlert") end,
            setValue = function(val) Set("rankAlert", val and true or false) end,
        }, {
            type = "toggle",
            text = "List Recipes for Later",
            disabled = pOff,
            tooltip = "The Recipe Finder also lists the recipes your skill is not high enough for yet.",
            getValue = function() return PF.Get("showLater") end,
            setValue = function(val) Set("showLater", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Recipe Window",
            disabled = pOff,
            tooltip = "Opening a profession shows CludesUI's recipe window in place of the game's: your recipes by category with how many you can make, favourites, a filter, reagents with what is in your bags and bank, and the recipes you have not learned yet with where to learn them.",
            getValue = function() return PF.Get("craftWindow") end,
            setValue = function(val) Set("craftWindow", val and true or false) end,
        }, {
            type = "toggle",
            text = "Skill-up Chances",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "The recipe window shows each recipe's chance to raise your skill, where it is not certain either way.",
            getValue = function() return PF.Get("skillUpChances") end,
            setValue = function(val) Set("skillUpChances", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Skill-up Levels",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "The picked recipe shows the skill where it turns yellow, green and gray, and your chance now.",
            getValue = function() return PF.Get("skillThresholds") end,
            setValue = function(val) Set("skillThresholds", val and true or false) end,
        }, {
            type = "toggle",
            text = "Alts' Professions",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "An Alts button on the recipe window opens your other characters' professions on this realm. Each one shows once that character has opened it.",
            getValue = function() return PF.Get("altProfessions") end,
            setValue = function(val) Set("altProfessions", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Craft Orders",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "On someone else's profession (from a trade link), an order column: pick recipes, how many, the materials you bring and a tip, then ask them in party chat or by whisper.",
            getValue = function() return PF.Get("craftOrders") end,
            setValue = function(val) Set("craftOrders", val and true or false) end,
        }, {
            type = "toggle",
            text = "Skill-up Plan",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "A Skill-up Plan button on the recipe window: the fewest crafts from your skill to your cap, with the trainer recipes to learn on the way.",
            getValue = function() return PF.Get("skillUpPlan") end,
            setValue = function(val) Set("skillUpPlan", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Craft Profit",
            disabled = function() return pOff() or not PF.Get("craftWindow") end,
            tooltip = "Under a recipe's reagents: what one craft sells for after the auction cut, its materials and the profit. Needs auction prices (The Market's Auction Prices, or Auctionator).",
            getValue = function() return PF.Get("craftProfit") end,
            setValue = function(val) Set("craftProfit", val and true or false) end,
        }, {
            type = "toggle",
            text = "Disenchant Window",
            disabled = pOff,
            tooltip = "/cde, or the Disenchant button on the recipe window while Enchanting is open: everything in your bags Disenchant can take. Right-click keeps one, Shift-right-click every copy; Disenchant All does one per click.",
            getValue = function() return PF.Get("disenchant") end,
            setValue = function(val) Set("disenchant", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Disenchant on Tooltips",
            disabled = function() return pOff() or not PF.Get("disenchant") end,
            tooltip = "Green, blue and purple gear says about what it disenchants into is worth at your auction prices, and the Enchanting skill it needs (red when yours is lower).",
            getValue = function() return PF.Get("disenchantTooltip") end,
            setValue = function(val) Set("disenchantTooltip", val and true or false) end,
        }, {
            type = "toggle",
            text = "Trade Enchants",
            disabled = pOff,
            tooltip = "While you trade with Enchanting open: beside the trade window, your enchants that go on the item in the \"Will not be traded\" slot, the ones they linked to you first. Enchant casts it in one click.",
            getValue = function() return PF.Get("tradeEnchants") end,
            setValue = function(val) Set("tradeEnchants", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  THE MARKET
    ---------------------------------------------------------------------------
    local MK = CUI._Market
    if MK then
        local function mOff() return not MK.Get("enabled") end
        local function Set(key, val)
            MK.Cfg()[key] = val
            MK.Apply()
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "THE MARKET", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Auction Prices",
            tooltip = function()
                return "A Scan Prices button on the auction house: it reads every listing and keeps each item's lowest buyout for this realm and faction (the game allows one full scan every 15 minutes). Your own searches keep prices fresh too. Loot Feed, Junk Items and the recipe window use these prices when Auctionator is not installed.\n\n"
                    .. MK.Market.Summary()
            end,
            getValue = function() return not mOff() end,
            setValue = function(val) Set("enabled", val and true or false) end,
        }, {
            type = "toggle",
            text = "Prices on Tooltips",
            disabled = mOff,
            tooltip = "Item tooltips show the lowest buyout and how old it is. Off while Auctionator is installed, which shows its own.",
            getValue = function() return MK.Get("tooltip") end,
            setValue = function(val) Set("tooltip", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Scan on Opening",
            disabled = mOff,
            tooltip = "Scans by itself when you open the auction house and your last scan is over 30 minutes old.",
            getValue = function() return MK.Get("autoScan") end,
            setValue = function(val) Set("autoScan", val and true or false) end,
        }, {
            type = "toggle",
            text = "Keep Other Addons' Scans",
            disabled = mOff,
            tooltip = "Also keeps the prices from full scans that other addons start.",
            getValue = function() return MK.Get("capture") end,
            setValue = function(val) Set("capture", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Market Panel",
            disabled = mOff,
            tooltip = "A panel beside the auction house. Sell: your bags most valuable first, each priced one step under the cheapest listing that is not yours, with quantity, duration and Post. My Auctions: your auctions checked against the listings, undercut ones first, with Cancel.",
            getValue = function() return MK.Get("panel") end,
            setValue = function(val) Set("panel", val and true or false) end,
        }, {
            type = "toggle",
            text = "Undercut Alert",
            disabled = function() return mOff() or not MK.Get("panel") end,
            tooltip = "A chat line at the auction house when someone lists for less than your auctions.",
            getValue = function() return MK.Get("undercutAlert") end,
            setValue = function(val) Set("undercutAlert", val and true or false) end,
        })
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Shopping Tab",
            disabled = function() return mOff() or not MK.Get("panel") end,
            tooltip = "A Shopping tab on the Market panel: the items your current RestedXP steps tell you to buy and the items your quests still need, with how many you have. Click one to search for it.",
            getValue = function() return MK.Get("shopping") end,
            setValue = function(val) Set("shopping", val and true or false) end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  MAIL AND ALTS
    ---------------------------------------------------------------------------
    local MA = CUI._MailAlts
    if MA then
        local function Tog(key, textValue, tipText)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                getValue = function() return MA.Get(key) end,
                setValue = function(val)
                    MA.Cfg()[key] = val and true or false
                    MA.Apply()
                end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "MAIL AND ALTS", cursorY)
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "altCounts",
                "Alt Item Counts",
                "Item tooltips show how many your characters on this realm and faction hold in their bags, bank and mailbox. Each is counted once you log in on it, its bank once you open it."
            ),
            Tog(
                "mailAlts",
                "Alts Button on Mail",
                "An Alts button beside the mailbox's Send tab lists your characters with level and gold; pick one to fill the To box."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "quickAttach",
                "Quick Attach",
                "An Attach button beside the Send tab: attach every trade good, one type of trade good, or your unbound gear in one click."
            ),
            Tog(
                "expiry",
                "Mail Expiry Warning",
                "At login, names any of your characters with mail expiring within three days."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "labeledButton",
            text = "Forget a Character",
            buttonText = "Forget",
            width = 90,
            tooltip = "Removes a deleted or moved character from the counts and the Alts list.",
            onClick = function(self) MA.Forget(self) end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  JUNK ITEMS (the rows after the toggle are built while the window is
    --  on; the toggle rebuilds the page)
    ---------------------------------------------------------------------------
    local JI = CUI._JunkItems
    local function junkOff() return not JI.Get("enabled") end
    -- Every write re-applies the window.
    local function JunkSet(key, val)
        JI.Cfg()[key] = val
        JI.Apply()
    end
    local function ClearJunkExclusions()
        CUI:ShowConfirmPopup({
            title = CUI.L("Clear Excluded Items"),
            message = CUI.L(
                "Every item you middle-clicked away can show in the Junk Items window again."
            ),
            confirmText = CUI.L("Clear"),
            cancelText = CANCEL,
            onConfirm = JI.ClearExclusions,
        })
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    heading, height = W:SectionHeader(hostFrame, "JUNK ITEMS", cursorY)
    cursorY = cursorY - height
    CUI.BuildSectionUnlockJump(
        heading,
        { key = "CUI_JunkList", disabled = junkOff, disabledTooltip = "Junk Items Window" }
    )

    _, height = CUI.BuildVisibilityRow(W, hostFrame, cursorY, {
        leftCfg = {
            type = "toggle",
            text = "Enable Junk Items Window",
            tooltip = "Shows your cheapest junk in a small window.",
            getValue = function() return not junkOff() end,
            setValue = CUI.SectionToggleSetValue(function(val) JunkSet("enabled", val) end),
        },
        -- The window's table exists once it was turned on, and the row is
        -- greyed out while it is off, so viewing the page saves nothing.
        getStore = function() return junkOff() and JI.Read() or JI.Cfg() end,
        legacyKey = "visibility",
        caps = { partyIncludesRaid = false, luaDragonriding = true, noMouseover = true },
        disabledFn = junkOff,
        disabledTooltip = "Junk Items Window",
        onChanged = CUI.RequestVisibilityUpdate,
        onOptionChanged = CUI.RequestVisibilityUpdate,
    })
    cursorY = cursorY - height

    if not junkOff() then
        -- Rare and better are never junk by quality (and need DELETE typed), so
        -- both lists stop at Uncommon.
        local qualityValues, qualityOrder = _G._CUI_ItemQualityValues(Enum.ItemQuality.Uncommon)

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Items Shown",
            min = 1,
            max = 6,
            step = 1,
            isPercent = false,
            tooltip = "How many junk stacks the window lists.",
            getValue = function() return JI.Get("itemCount") end,
            setValue = function(val) JunkSet("itemCount", val) end,
        }, {
            type = "dropdown",
            text = "Maximum Quality",
            values = qualityValues,
            order = qualityOrder,
            tooltip = "Items above this quality are not shown, unless marked as junk in Bags.",
            getValue = function() return tostring(JI.Get("maxQuality")) end,
            setValue = function(val) JunkSet("maxQuality", tonumber(val)) end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Delete Without Confirming",
            values = qualityValues,
            order = qualityOrder,
            tooltip = "Items of this quality and below delete on the first Ctrl + Left Click. Higher-quality items need a second click, and Rare and above also need DELETE typed.",
            getValue = function() return tostring(JI.Get("oneClickQuality")) end,
            setValue = function(val) JunkSet("oneClickQuality", tonumber(val)) end,
        }, {
            type = "labeledButton",
            text = "Excluded Items",
            buttonText = "Clear",
            width = 90,
            tooltip = "Brings back items you middle-clicked away.",
            onClick = ClearJunkExclusions,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Size",
            min = 16,
            max = 64,
            step = 1,
            isPercent = false,
            getValue = function() return JI.Get("iconSize") end,
            setValue = function(val) JunkSet("iconSize", val) end,
        }, {
            type = "slider",
            text = "Icon Spacing",
            tooltip = "Prices that don't fit show only their largest coin.",
            min = 0,
            max = 30,
            step = 1,
            isPercent = false,
            getValue = function() return JI.Get("iconSpacing") end,
            setValue = function(val) JunkSet("iconSpacing", val) end,
        })
        cursorY = cursorY - height

        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Price Position",
            values = { bottom = "Below Icon", top = "Above Icon" },
            order = { "bottom", "top" },
            getValue = function() return JI.Get("priceSide") end,
            setValue = function(val) JunkSet("priceSide", val) end,
        }, {
            type = "toggle",
            text = "Show Empty Bag Slots",
            tooltip = "Shows free and total bag slots as the title.",
            getValue = function() return JI.Get("showFreeSlots") == true end,
            setValue = function(val) JunkSet("showFreeSlots", val) end,
        })
        cursorY = cursorY - height

        -- Only Show When Bag Space Is Low (its threshold in the cog) | Use Auctionator Prices
        local lowRow
        lowRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Only Show When Bag Space Is Low",
            tooltip = "Shows the window only while few bag slots are free. Use the cog to set how few.",
            getValue = function() return JI.Get("onlyLowBagSpace") == true end,
            setValue = function(val)
                JunkSet("onlyLowBagSpace", val)
                CUI:RefreshPage() -- the cog's disabled state
            end,
        }, {
            type = "toggle",
            text = "Use Auctionator Prices",
            tooltip = "Prices items from Auctionator scans.",
            disabled = function() return CUI._ModuleNS["CludesUIForeverEssentials"].AuctionAPI() == nil end,
            disabledTooltip = "This option requires Auctionator to be loaded.",
            getValue = function() return JI.Get("auctionPrices") == true end,
            setValue = function(val) JunkSet("auctionPrices", val) end,
        })
        cursorY = cursorY - height
        if not CUI._prebuilding then
            CUI.BuildInlineCog(lowRow._leftRegion, {
                title = "Only Show When Bag Space Is Low",
                disabled = function() return JI.Get("onlyLowBagSpace") ~= true end,
                disabledTooltip = "Only Show When Bag Space Is Low",
                rows = {
                    {
                        type = "slider",
                        label = "Free-Slot Threshold",
                        min = 1,
                        max = 100,
                        step = 1,
                        tooltip = "Shows the window while fewer regular bag slots than this are free.",
                        get = function() return JI.Get("freeSlotThreshold") end,
                        set = function(val) JunkSet("freeSlotThreshold", val) end,
                    },
                },
            })
        end
    end

    ---------------------------------------------------------------------------
    --  BAG SPACE
    ---------------------------------------------------------------------------
    local BS = CUI._BagSpace
    if BS then
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "BAG SPACE", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_BagSpace",
            disabled = function() return not BS.Get("enabled") end,
            disabledTooltip = "Bag Space",
        })
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Bag Space",
            tooltip = "Free bag slots on screen, amber when nearly full and red when full. Hover it for the cheapest items you carry; click it to open your bags.",
            getValue = function() return BS.Get("enabled") end,
            setValue = function(val)
                BS.Cfg().enabled = val and true or false
                BS.Apply()
            end,
        }, {
            type = "toggle",
            text = "Warn When Nearly Full",
            disabled = function() return not BS.Get("enabled") end,
            getValue = function() return BS.Get("warn") end,
            setValue = function(val)
                BS.Cfg().warn = val and true or false
                BS.Apply()
            end,
        })
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  RESTOCK AND REMINDERS
    ---------------------------------------------------------------------------
    local RM = CUI._Reminders
    if RM then
        local rs, lk, gr, tp = RM.restock, RM.lock, RM.gear, RM.talents
        local function Set(f, key, val)
            f.Cfg()[key] = val
            if f.Apply then f.Apply() end
        end
        local function Tog(f, key, textValue, tipText, off)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, val and true or false) end,
            }
        end
        local function Num(f, key, textValue, min, max, step, off)
            return {
                type = "slider",
                text = textValue,
                min = min,
                max = max,
                step = step,
                isPercent = false,
                disabled = off,
                getValue = function() return f.Get(key) end,
                setValue = function(val) Set(f, key, math.floor(val + 0.5)) end,
            }
        end
        local function rsOff() return not rs.Get("enabled") end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "RESTOCK REMINDER", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(
            heading,
            { key = "CUI_Restock", disabled = rsOff, disabledTooltip = "Restock Reminder" }
        )
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                rs,
                "enabled",
                "Restock Reminder",
                "When you reach a city or inn, a flashing list of what you are short on. It stays up until you have what you need or leave."
            ),
            Tog(
                rs,
                "buy",
                "Buy at Vendors",
                "At a vendor who sells them, tops your class reagents and ammo up to what you carry, and prints what it spent. Off by default: it spends gold for you.",
                rsOff
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(rs, "reagents", "Class Reagents", nil, rsOff),
            Tog(rs, "ammo", "Ammo (thrown, arrows, shot)", nil, rsOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "ammoTarget", "Ammo to Carry", 50, 4000, 50, rsOff),
            Tog(rs, "food", "Food & Drink", "Warriors and rogues do not need drink.", rsOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "foodBelow", "Food & Drink Below", 1, 40, 1, rsOff),
            Tog(rs, "vendor", "Junk & Full Bags", nil, rsOff)
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "foodMinLevel", "Food Minimum Level", 0, 60, 1, rsOff),
            Num(rs, "foodMaxLevel", "Food Maximum Level", 0, 60, 1, rsOff)
        )
        cursorY = cursorY - height
        if rs.Class == "HUNTER" then
            _, height = W:DualRow(
                hostFrame,
                cursorY,
                Tog(
                    rs,
                    "hunterAmmo",
                    "Hunter Ammo Reminder",
                    "Reminds about your equipped ammo at its own amount.",
                    rsOff
                ),
                Num(rs, "hunterAmmoBelow", "Remind When Ammo Falls To", 50, 4000, 50, rsOff)
            )
            cursorY = cursorY - height
        end
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Num(rs, "bagsBelow", "Free Slots Below", 1, 20, 1, rsOff),
            Num(rs, "size", "Text Size", 10, 32, 1, rsOff)
        )
        cursorY = cursorY - height
        local reagents = rs.Reagents()
        for idx = 1, #reagents, 2 do
            local function Carry(r)
                if not r then return { type = "label", text = "" } end
                return {
                    type = "slider",
                    text = r.name .. " to Carry",
                    min = 0,
                    max = 200,
                    step = 1,
                    isPercent = false,
                    disabled = rsOff,
                    tooltip = "How many to carry. 0 stops reminding you about it.",
                    getValue = function() return rs.Target(r.item) end,
                    setValue = function(val)
                        local c = rs.Cfg()
                        c.targets = c.targets or {}
                        c.targets[r.item] = math.floor(val + 0.5)
                        rs.Apply()
                    end,
                }
            end
            _, height = W:DualRow(hostFrame, cursorY, Carry(reagents[idx]), Carry(reagents[idx + 1]))
            cursorY = cursorY - height
        end

        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        heading, height = W:SectionHeader(hostFrame, "OTHER REMINDERS", cursorY)
        cursorY = cursorY - height
        CUI.BuildSectionUnlockJump(heading, {
            key = "CUI_GearReminders",
            disabled = function() return not (gr.Get("worn") or gr.Get("pole")) end,
            disabledTooltip = "Gear Reminders",
        })
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                lk,
                "enabled",
                "Lockpicking Skill",
                "Lockbox tooltips show the Lockpicking needed to open them, colored by yours."
            ),
            Tog(
                tp,
                "enabled",
                "Unspent Talent Points",
                "Text on screen while you have talent points to spend. Hidden in combat."
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                gr,
                "worn",
                "Worn Gear Reminder",
                "An icon while you wear Cloak of Hermitic Bliss in Wailing Caverns, so you remember to swap it."
            ),
            Tog(gr, "pole", "Fishing Pole Reminder", "An icon while you have a fishing pole equipped.")
        )
        cursorY = cursorY - height
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Fishing Pole Shows In",
            values = { always = "Everywhere", instance = "Dungeons & Raids" },
            order = { "always", "instance" },
            disabled = function() return not gr.Get("pole") end,
            getValue = function() return gr.Get("poleWhere") end,
            setValue = function(val) Set(gr, "poleWhere", val) end,
        }, Num(gr, "size", "Gear Icon Size", 20, 96, 1))
        cursorY = cursorY - height
    end

    ---------------------------------------------------------------------------
    --  FISHING (CludesUIForeverEssentials_Fishing.lua)
    ---------------------------------------------------------------------------
    local FI = CUI._Fishing
    local function SetFish(key, val)
        FI.Cfg()[key] = val
        FI.Apply()
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height
    heading, height = W:SectionHeader(hostFrame, "FISHING", cursorY)
    cursorY = cursorY - height
    -- The Bobber Indicator's mover exists only while the indicator can show:
    -- the Fishing Key bound with Reel In and Bobber Indicator on (the cog's
    -- rows), so the button names whichever of the three is missing.
    CUI.BuildSectionUnlockJump(heading, {
        key = "CUI_FishingBobber",
        disabled = function() return FI.Get("key") == nil or not FI.Get("reel") or not FI.Get("indicator") end,
        disabledTooltip = function()
            if FI.Get("key") == nil then return "Fishing Key" end
            if not FI.Get("reel") then return "Reel In With the Key" end
            return "Bobber Indicator"
        end,
    })

    -- Fishing Key (keybind, its options in the cog) | Double-Click to Cast
    local fishKeyRow
    fishKeyRow, height = W:DualRow(hostFrame, cursorY, {
        type = "label",
        text = "Fishing Key",
        tooltip = "One key casts your line, equipping your best fishing pole first. Use the cog for reeling in, the bobber indicator and lures.",
    }, {
        type = "toggle",
        text = "Double-Click to Cast",
        tooltip = "With a fishing pole in hand, double right-click the world to cast.",
        disabled = function() return CUI.PadGamepadUI() end,
        disabledTooltip = "This option does not work with the Gamepad interface style.",
        getValue = function() return FI.Get("doubleClick") end,
        setValue = function(val)
            SetFish("doubleClick", val)
            CUI:RefreshPage() -- the cog's disabled state
        end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local region = fishKeyRow._leftRegion
        local kbBtn, refresh = CUI.BuildKeybindButton(region, {
            w = 140,
            h = 30,
            font = 13,
            get = function() return FI.Get("key") end,
            set = function(val)
                SetFish("key", val)
                CUI:RefreshPage() -- the cog's disabled state
            end,
            tooltip = "Left-click to set a keybind.\nRight-click to unbind.",
        })
        CUI.PanelPP.Point(kbBtn, "RIGHT", region, "RIGHT", -20, 0)
        CUI.RegisterWidgetRefresh(refresh)

        local function fishRow(labelText, tooltip, key)
            return {
                type = "toggle",
                label = labelText,
                tooltip = tooltip,
                get = function() return FI.Get(key) end,
                set = function(val) SetFish(key, val) end,
            }
        end
        -- A label half has no control: the cog sits left of the keybind
        -- button, which also bounds the label.
        CUI.BuildInlineCog(region, {
            title = "Fishing Key",
            rows = {
                fishRow(
                    "Reel In With the Key",
                    "Once the bobber bites and is on screen, the Fishing Key reels it in.",
                    "reel"
                ),
                fishRow(
                    "Bobber Indicator",
                    "Shows whether the key will reel in. Place it in Edit Layout.",
                    "indicator"
                ),
                fishRow(
                    "Apply Lure",
                    "With no lure on your pole, the key applies your best lure first.",
                    "lure"
                ),
            },
            anchorTo = kbBtn,
            disabled = function() return FI.Get("key") == nil end,
            disabledTooltip = "Fishing Key",
        })
        CUI.BuildInlineCog(fishKeyRow._rightRegion, {
            title = "Double-Click to Cast",
            rows = {
                fishRow(
                    "Apply Lure",
                    "With no lure on your pole, a double-click applies your best lure first.",
                    "clickLure"
                ),
            },
            disabled = function() return CUI.PadGamepadUI() or not FI.Get("doubleClick") end,
            disabledTooltip = function()
                if CUI.PadGamepadUI() then
                    return "This option does not work with the Gamepad interface style."
                end
                return "Double-Click to Cast"
            end,
        })
    end

    _, height = W:DualRow(hostFrame, cursorY, {
        type = "toggle",
        text = "Fishing Sounds",
        tooltip = "While you fish: music and ambience down, effects up, sound on in the background.",
        getValue = function() return FI.Get("sound") end,
        setValue = function(val) SetFish("sound", val) end,
    }, {
        type = "toggle",
        text = "Auto Loot While Fishing",
        tooltip = "While you fish, the catch loots itself; your own auto loot setting comes back when you stop.",
        getValue = function() return FI.Get("autoLoot") end,
        setValue = function(val) SetFish("autoLoot", val) end,
    })
    cursorY = cursorY - height

    -- GLIMMER (CludesUIForeverEssentials_Glimmer.lua).
    local GL = CUI._Glimmer
    if GL then
        local function glOff() return not GL.Get("enabled") end
        local function GLSet(key, val, refresh)
            GL.Cfg()[key] = val
            GL.Apply()
            if refresh then CUI:RefreshPage() end
        end
        local function Tog(key, textValue, tipText, off, refresh)
            return {
                type = "toggle",
                text = textValue,
                tooltip = tipText,
                disabled = off,
                getValue = function() return GL.Get(key) == true end,
                setValue = function(val) GLSet(key, val and true or false, refresh) end,
            }
        end
        _, height = W:Spacer(hostFrame, cursorY, 20)
        cursorY = cursorY - height
        _, height = W:SectionHeader(hostFrame, "GLIMMER", cursorY)
        cursorY = cursorY - height
        local lookRow
        lookRow, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "enabled",
                "Object Highlights",
                "Herbs, ore, chests, quest objects and quest givers light up as you walk up to them, herbs and ore in the color of your chance to raise your skill, with a line under them. It turns the game's soft interact targeting on while it is on, and puts your settings back when you turn it off. Rests in combat.",
                nil,
                true
            ),
            {
                type = "dropdown",
                text = "Effect",
                disabled = glOff,
                values = { glow = "Glow", sparkles = "Sparkles", ring = "Ring", beam = "Beam", brackets = "Brackets" },
                order = { "glow", "sparkles", "ring", "beam", "brackets" },
                getValue = function() return GL.Get("style") end,
                setValue = function(val) GLSet("style", val) end,
            }
        )
        cursorY = cursorY - height
        if not CUI._prebuilding then
            CUI.BuildInlineCog(lookRow._rightRegion, {
                disabled = glOff,
                disabledTooltip = "Object Highlights",
                title = "Glimmer Look",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 60,
                        max = 160,
                        step = 5,
                        get = function() return math.floor(GL.Get("size") * 100 + 0.5) end,
                        set = function(val) GLSet("size", val / 100) end,
                    },
                    {
                        type = "slider",
                        label = "Brightness",
                        min = 30,
                        max = 150,
                        step = 5,
                        get = function() return math.floor(GL.Get("brightness") * 100 + 0.5) end,
                        set = function(val) GLSet("brightness", val / 100) end,
                    },
                    {
                        type = "slider",
                        label = "Reach (yards)",
                        min = 5,
                        max = 15,
                        step = 1,
                        get = function() return GL.Get("range") end,
                        set = function(val) GLSet("range", math.floor(val + 0.5)) end,
                    },
                    {
                        type = "toggle",
                        label = "Skill-up Colors",
                        get = function() return GL.Get("skillColors") == true end,
                        set = function(val) GLSet("skillColors", val) end,
                    },
                    {
                        type = "toggle",
                        label = "Line Under It",
                        tooltip = "Skill-up chance, the skill needed, or the quest objective.",
                        get = function() return GL.Get("showLine") == true end,
                        set = function(val) GLSet("showLine", val) end,
                    },
                    {
                        type = "toggle",
                        label = "Hide in Dungeons",
                        get = function() return GL.Get("hideInstance") == true end,
                        set = function(val) GLSet("hideInstance", val) end,
                    },
                    {
                        type = "toggle",
                        label = "Hide What You Cannot Gather",
                        get = function() return GL.Get("hideLocked") == true end,
                        set = function(val) GLSet("hideLocked", val) end,
                    },
                },
            })
        end
        local NAMES = {
            ore = "Ore",
            herb = "Herbs",
            quest = "Quest Objects",
            giver = "Quest Givers",
            chest = "Chests",
            bobber = "Fishing Bobber",
            corpse = "Lootable Corpses",
        }
        local cats = GL.Categories
        for idx = 1, #cats, 2 do
            local function Cat(key)
                if not key then return { type = "label", text = "" } end
                return Tog(key, NAMES[key], nil, glOff)
            end
            local catRow
            catRow, height = W:DualRow(hostFrame, cursorY, Cat(cats[idx]), Cat(cats[idx + 1]))
            cursorY = cursorY - height
            if not CUI._prebuilding then
                for side, key in pairs({ _leftRegion = cats[idx], _rightRegion = cats[idx + 1] }) do
                    CUI.BuildInlineSwatches(catRow[side], {
                        {
                            tooltip = NAMES[key] .. " Color",
                            getValue = function() return GL.Get(key .. "R"), GL.Get(key .. "G"), GL.Get(key .. "B"), 1 end,
                            setValue = function(red, green, blue)
                                local c = GL.Cfg()
                                c[key .. "R"], c[key .. "G"], c[key .. "B"] = red, green, blue
                                GL.Apply()
                            end,
                        },
                    }, { disabled = glOff, disabledTooltip = "Object Highlights" })
                end
            end
        end
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog(
                "minimapIcons",
                "Herb and Ore Spots on the Minimap",
                "Every spot herbs and ore grow near you, on the minimap, ringed in your skill-up color. With Find Herbs or Find Minerals on, the game's own dot shows inside the ring when the node is up.",
                glOff
            ),
            Tog(
                "gatheredPins",
                "Gathered on the World Map",
                "Each herb and vein you gather goes on the world map, with how many times you have gathered it.",
                glOff
            )
        )
        cursorY = cursorY - height
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            Tog("myProfessions", "Only My Gathering Skills", "Minimap spots only for Herbalism or Mining you have.", glOff),
            {
                type = "slider",
                text = "Minimap Spot Size",
                min = 10,
                max = 24,
                step = 1,
                isPercent = false,
                disabled = glOff,
                getValue = function() return GL.Get("minimapSize") end,
                setValue = function(val) GLSet("minimapSize", math.floor(val + 0.5)) end,
            }
        )
        cursorY = cursorY - height
    end

    return math.abs(cursorY)
end
