if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- CUI_GroupFinder_Options.lua: Group Finder settings page
-------------------------------------------------------------------------------
local ADDON_NAME = "CludesUIGroupFinder"
local mod = CludesUI._ModuleNS[ADDON_NAME]
if not mod then
    return
end -- module off: no page
local CUI = CludesUI

local PAGE_SEARCH = "Premade Search"
local PAGE_APPS = "Mythic+ Tracker"

CludesUI.AtLogin(function()

    local AddAppsSections, AddListSections

    -----------------------------------------------------------------------
    -- applications settings (greyed while the module's off)
    -----------------------------------------------------------------------
    local function APCfg()
        return mod.AppsCfg()
    end
    local function APGet(key, default)
        local c = APCfg()
        local v = c and c[key]
        if v == nil then
            return default
        end
        return v
    end
    local function APSet(key, val)
        local c = APCfg()
        if c then
            c[key] = val
        end
        mod.ApplyApplications()
    end
    local function ModOff()
        return not mod.Enabled()
    end
    local function APOff()
        return ModOff() or APGet("enabled", false) ~= true
    end
    local function APOffTip()
        return ModOff() and "Group Finder" or "Show Applications in Group Finder"
    end

    local function BuildSearchPage(page, hostFrame, yOffset)
        local W = CUI.Widgets
        local posY = yOffset
        local _, hgt

        -- sample groups up top, drawn as the list draws them
        if mod.OwnListPreviewBuild then
            CUI:SetContentHeader(mod.OwnListPreviewBuild)
        elseif CUI.ClearContentHeader then
            CUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true

        -- the enable toggle reloads; the pgf warning takes the section's last row while it's loaded
        local PGFLoaded = mod.Blocked
        local function BgOpacity()
            return mod.OwnListGet("windowBgOpacity") or 100
        end
        local function QuickOn()
            return CludesUIDB and CludesUIDB.quickSignup and true or false
        end
        _, hgt = W:SectionHeader(hostFrame, "GENERAL", posY)
        posY = posY - hgt
        local bgRow
        bgRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Group Finder",
            disabled = function()
                return PGFLoaded() and not mod.Enabled()
            end,
            disabledTooltip = "Premade Groups Filter",
            requireState = "disabled",
            tooltip = "Premade Groups search filters, group list and the M+ applications bar in the Dungeons & Raids window. Requires a reload.",
            getValue = function()
                return mod.Enabled()
            end,
            setValue = function(v)
                v = v and true or false
                if v == mod.Enabled() then
                    return
                end
                -- only saved once the reload's confirmed
                CUI:ShowConfirmPopup({
                    title = v and "Enable Group Finder" or "Disable Group Finder",
                    message = v and "Your UI will reload to turn on the Group Finder."
                        or "Your UI will reload to turn off the Group Finder.",
                    confirmText = "Reload Now",
                    cancelText = "Cancel",
                    reload = true,
                    onConfirm = function()
                        mod.SetEnabled(v)
                    end,
                    onCancel = function()
                        CUI:RefreshPage()
                    end,
                })
            end,
        }, {
            type = "slider",
            text = "Background",
            min = 0,
            max = 100,
            step = 5,
            tooltip = "How opaque the Dungeons & Raids window background is. The swatch sets its tint.",
            getValue = BgOpacity,
            setValue = function(v)
                local was = BgOpacity() == 0
                mod.SetWindowLook("windowBgOpacity", v)
                -- the swatch greys out at 0
                if was ~= (v == 0) then
                    CUI:RefreshPage()
                end
            end,
        })
        posY = posY - hgt
        if not CUI._prebuilding then
            CUI.BuildInlineSwatches(bgRow._rightRegion, {
                {
                    tooltip = "The tint over the background. Its opacity sets how strong the tint is.",
                    hasAlpha = true,
                    disabled = function()
                        return BgOpacity() == 0
                    end,
                    disabledTooltip = "Background above 0",
                    getValue = function()
                        local c = mod.OwnListGet("windowBgColor")
                        if c then
                            return c.r, c.g, c.b, c.a or 0.62
                        end
                        return 0, 0, 0, 0.62
                    end,
                    setValue = function(r, g, b, a)
                        mod.SetWindowLook("windowBgColor", { r = r, g = g, b = b, a = a })
                    end,
                },
            })
        end
        -- both account-wide
        local noteRow
        noteRow, hgt = W:DualRow(
            hostFrame,
            posY,
            -- one dropdown over the account-wide quickSignup switch and this
            -- profile's click count
            {
                type = "dropdown",
                text = "Quick Signup",
                tooltip = "How many clicks sign you up to a group. Hold Shift to keep the note box open.",
                values = {
                    disabled = "Disabled",
                    single = "Single-click",
                    double = "Double-click",
                    triple = "Triple-click",
                },
                order = { "disabled", "single", "double", "triple" },
                getValue = function()
                    if not QuickOn() then
                        return "disabled"
                    end
                    return mod.OwnListGet("signupClicks")
                end,
                setValue = function(v)
                    if v == "disabled" then
                        CludesUIDB.quickSignup = false
                    else
                        CludesUIDB.quickSignup = true
                        mod.SetOwnListValue("signupClicks", v)
                    end
                    if CUI._applyQuickSignup then
                        CUI._applyQuickSignup()
                    end
                end,
            },
            {
                type = "toggle",
                text = "Persistent Signup Note",
                tooltip = "Keeps a saved signup note you can copy into the Sign Up dialog with the Copy button.",
                getValue = function()
                    return CludesUIDB and CludesUIDB.persistSignupNote or false
                end,
                setValue = function(v)
                    CludesUIDB.persistSignupNote = v
                    if CUI._applyPersistSignupNote then
                        CUI._applyPersistSignupNote()
                    end
                    CUI:RefreshPage()
                end,
            }
        )
        posY = posY - hgt
        if not CUI._prebuilding then
            CUI.BuildInlineCog(noteRow._rightRegion, {
                gap = 9,
                tip = "Edit the saved signup note.",
                disabled = function()
                    return not (CludesUIDB and CludesUIDB.persistSignupNote)
                end,
                disabledTooltip = "Persistent Signup Note",
                show = function()
                    CUI:ShowInputPopup({
                        title = "Signup Note",
                        message = "Saved between reloads and relogs. In Group Finder, choose Copy, press Ctrl+C, then Ctrl+V.",
                        placeholder = "Enter signup note...",
                        initialText = CUI.GetPersistentSignupNote(),
                        maxLetters = 63,
                        inputHeight = 70,
                        multiline = true,
                        showCount = true,
                        allowEmpty = true,
                        confirmText = "Save",
                        onConfirm = function(note)
                            CUI.SetPersistentSignupNote(note or "")
                        end,
                    })
                end,
            })
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Cancel Oldest Application",
            tooltip = "At the application limit, clicking a group cancels your oldest pending application so you can sign up.",
            getValue = function()
                return mod.Cfg().cancelOldest == true
            end,
            setValue = function(v)
                mod.Cfg().cancelOldest = v and true or false
            end,
        }, CUI.BlankRowCfg())
        posY = posY - hgt
        if PGFLoaded() then
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "label",
                text = CUI.COLOR_CODES.ERROR
                    .. CludesUI.L("Premade Groups Filter is loaded. Disable it to use the Group Finder.")
                    .. "|r",
            }, CUI.BlankRowCfg())
            posY = posY - hgt
        end

        posY = AddListSections(hostFrame, posY)

        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        hostFrame:SetHeight(math.abs(posY - yOffset))
        return math.abs(posY - yOffset)
    end

    -- applications page, reset buttons with it
    local function BuildAppsPage(hostFrame, yOffset)
        local W = CUI.Widgets
        local posY = yOffset
        local _, hgt
        if CUI.ClearContentHeader then
            CUI:ClearContentHeader()
        end
        hostFrame._showRowDivider = true
        posY = AddAppsSections(hostFrame, posY)
        _, hgt = W:Spacer(hostFrame, posY, 20)
        posY = posY - hgt
        hostFrame:SetHeight(math.abs(posY - yOffset))
        return math.abs(posY - yOffset)
    end

    -- results list, display, the applicant list
    function AddListSections(hostFrame, posY)
        local W = CUI.Widgets
        local _, hgt
        _, hgt = W:SectionHeader(hostFrame, "RESULTS LIST", posY)
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Title Text Size",
            min = 8,
            max = 20,
            step = 1,
            tooltip = "The group's title, the first line.",
            getValue = function()
                return mod.OwnListSize("titleSize")
            end,
            setValue = function(v)
                mod.SetOwnListSize("titleSize", v)
            end,
        }, {
            type = "slider",
            text = "Label Text Size",
            min = 8,
            max = 20,
            step = 1,
            tooltip = "The playstyle and region tag text size.",
            getValue = function()
                return mod.OwnListSize("lineSize")
            end,
            setValue = function(v)
                mod.SetOwnListSize("lineSize", v)
            end,
        })
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Dungeon / Raid Text Size",
            min = 8,
            max = 20,
            step = 1,
            tooltip = "The dungeon or raid name text size.",
            getValue = function()
                return mod.OwnListSize("nameSize")
            end,
            setValue = function(v)
                mod.SetOwnListSize("nameSize", v)
            end,
        }, {
            type = "toggle",
            text = "Colored Group Names",
            tooltip = "Green name when a group is new, Red name when you were declined or instance locked.",
            getValue = function()
                return mod.Cfg().nameColors == true
            end,
            setValue = function(v)
                mod.Cfg().nameColors = v and true or false
                if mod.Redecorate then
                    mod.Redecorate()
                end
            end,
        })
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Row Height",
            min = 20,
            max = 64,
            step = 1,
            tooltip = "How tall each row is. Lines that no longer fit drop off from the bottom: the playstyle line first, then the dungeon / raid name (its short name then sits ahead of the title) and the leader crown.",
            getValue = function()
                return mod.OwnListRowHeight()
            end,
            setValue = function(v)
                mod.SetOwnListRowHeight(v)
            end,
        }, {
            type = "toggle",
            text = "Applied Groups on Top",
            tooltip = "Groups you apply to move to the top of the list.",
            getValue = function()
                return mod.OwnListGet("appsFirst") ~= false
            end,
            setValue = function(v)
                mod.SetOwnListValue("appsFirst", v and true or false)
            end,
        })
        posY = posY - hgt
        -- status color: a checklist, one color each
        local LINE_ITEMS = {
            { key = "lineDelisted", label = "Delisted", tooltip = "The group was delisted." },
            { key = "lineAccepted", label = "Accepted", tooltip = "Applied and waiting, or invited." },
            { key = "lineCancelled", label = "Canceled", tooltip = "You cancelled the application." },
            {
                key = "lineDeclined",
                label = "Declined",
                tooltip = "Declined, the group filled, or the application timed out.",
            },
        }
        local lineRow
        lineRow, hgt = W:DualRow(
            hostFrame,
            posY,
            -- placeholder, the checklist replaces it
            {
                type = "dropdown",
                text = "Status Effect",
                tooltip = "Marks the groups you applied to in their status color, with a line under the group or a tinted row.",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            },
            {
                type = "segmented",
                text = "Results Visibility",
                tooltip = "Groups your filters leave out: hidden from the list, or shown dimmed.",
                values = { dimmed = "Dimmed", hidden = "Hidden" },
                order = { "dimmed", "hidden" },
                getValue = function()
                    return mod.OwnListGet("visibility")
                end,
                setValue = function(v)
                    if v == mod.OwnListGet("visibility") then
                        return
                    end
                    mod.SetOwnListValue("visibility", v)
                    if mod.DimFiltersChanged then
                        mod.DimFiltersChanged()
                    end
                end,
            }
        )
        posY = posY - hgt
        if not CUI._prebuilding then
            local region = lineRow._leftRegion
            if region._control then
                region._control:Hide()
            end
            local dropdown, ddRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                LINE_ITEMS,
                function(key)
                    return mod.OwnListGet(key) ~= false
                end,
                function(key, v)
                    mod.SetOwnListValue(key, v and true or false)
                end
            )
            CUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(ddRefresh)
            -- the effect's style and each status's color (the list's own
            -- colors and keys: ns.STATUS_LINES, CUI_GroupFinder_ResultsList.lua)
            local function Picker(key, labelText)
                local line = mod.STATUS_LINES[key]
                return {
                    type = "colorpicker",
                    label = labelText,
                    get = function()
                        local c = mod.OwnListGet(line[5])
                        if type(c) == "table" then
                            return c.r, c.g, c.b
                        end
                        return line[2], line[3], line[4]
                    end,
                    set = function(r, g, b)
                        mod.SetOwnListValue(line[5], { r = r, g = g, b = b })
                    end,
                }
            end
            CUI.BuildInlineCog(region, {
                title = "Status Effect",
                rows = {
                    {
                        type = "dropdown",
                        label = "Style",
                        values = { underline = "Underline", row = "Row Highlight" },
                        order = { "underline", "row" },
                        get = function()
                            return mod.OwnListGet("statusStyle") == "row" and "row" or "underline"
                        end,
                        set = function(v)
                            mod.SetOwnListValue("statusStyle", v)
                        end,
                    },
                    Picker("lineDelisted", "Delisted Color"),
                    Picker("lineAccepted", "Accepted Color"),
                    Picker("lineCancelled", "Canceled Color"),
                    Picker("lineDeclined", "Declined Color"),
                },
            })
        end
        local rioRow
        rioRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Raider.IO Rating Colors",
            tooltip = "Color the leader's rating with Raider.IO's score colors. Otherwise, use the game's rating colors.",
            disabled = function()
                return not (RaiderIO and RaiderIO.GetScoreColor)
            end,
            disabledTooltip = "Raider.IO",
            getValue = function()
                return mod.Cfg().rioRatingColors ~= false
            end,
            setValue = function(v)
                mod.Cfg().rioRatingColors = v and true or false
                if mod.Redecorate then
                    mod.Redecorate()
                end
            end,
        }, {
            type = "toggle",
            text = "Members in Tooltip",
            tooltip = "Group tooltips add each member's name (dungeons and arenas, where Blizzard already lists the roles and classes), or a line per member with role, specialization, class and name (other groups).",
            getValue = function()
                return mod.Cfg().classTooltip ~= false
            end,
            setValue = function(v)
                mod.Cfg().classTooltip = v and true or false
            end,
        })
        posY = posY - hgt
        if not CUI._prebuilding then
            -- the rating text shows with the game's colors too, so the cog stays
            -- open without Raider.IO
            CUI.BuildInlineCog(rioRow._leftRegion, {
                title = "Rating Text",
                rows = {
                    {
                        type = "slider",
                        label = "Rating Text Size",
                        min = 8,
                        max = 20,
                        step = 1,
                        tooltip = "The leader's Mythic+ rating beside the role icons.",
                        get = function()
                            return mod.OwnListSize("scoreSize")
                        end,
                        set = function(v)
                            mod.SetOwnListSize("scoreSize", v)
                        end,
                    },
                },
            })
        end

        _, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
        posY = posY - hgt
        local function Circle()
            return mod.OwnListGet("iconShape") ~= "square"
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "segmented",
            text = "Icon Shape",
            tooltip = "The member and specialization icon shape.",
            values = { circle = "Circle", square = "Square" },
            order = { "circle", "square" },
            getValue = function()
                return mod.OwnListGet("iconShape")
            end,
            setValue = function(v)
                mod.SetOwnListValue("iconShape", v)
                CUI:RefreshPage(true)
            end,
        }, {
            type = "slider",
            text = "Role Icon Size",
            min = 100,
            max = 160,
            step = 5,
            tooltip = "Size of the role and specialization icons in the group list.",
            getValue = function()
                return tonumber(mod.Cfg().iconSize) or mod.DEFAULTS.iconSize
            end,
            setValue = function(v)
                mod.Cfg().iconSize = v
                if mod.Redecorate then
                    mod.Redecorate()
                end
            end,
        })
        posY = posY - hgt
        local texValues, texOrder = CUI.GetBorderTextureDropdown()
        local borderRow
        borderRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Border Style",
            tooltip = "The border around square icons.",
            values = texValues,
            order = texOrder,
            disabled = Circle,
            disabledTooltip = "Icon Shape: Square",
            getValue = function()
                return mod.OwnListGet("borderTexture")
            end,
            setValue = function(v)
                -- a new style starts on its own color
                mod.SetOwnListValue("borderColor", nil)
                mod.SetOwnListValue("borderTexture", v)
                CUI:RefreshPage(true)
            end,
        }, {
            type = "slider",
            text = "Border Size",
            min = 0,
            max = 4,
            step = 1,
            tooltip = "In pixels. 0 for no border. Round icons get a ring.",
            getValue = function()
                return tonumber(mod.OwnListGet("borderSize")) or 0
            end,
            setValue = function(v)
                mod.SetOwnListValue("borderSize", v)
            end,
        })
        posY = posY - hgt
        do
            -- border color swatch
            local region = borderRow and borderRow._rightRegion
            if region then
                local colorSwatch, update = CUI.BuildColorSwatch(
                    region,
                    region:GetFrameLevel() + 5,
                    function()
                        local r, g, b = mod.OwnListBorderColor()
                        return r, g, b, 1
                    end,
                    function(r, g, b)
                        mod.SetOwnListValue("borderColor", { r = r, g = g, b = b })
                    end,
                    false,
                    20
                )
                colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -12, 0)
                region._lastInline = colorSwatch
                CUI.RegisterWidgetRefresh(update)
            end
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Missing Role Icons",
            tooltip = "When there is a missing role, add an icon to show you which one.",
            values = { none = "None", blizzard = "Blizzard", cludes = "CludesUI" },
            order = { "none", "blizzard", "cludes" },
            getValue = function()
                return mod.OwnListGet("missingIcons")
            end,
            setValue = function(v)
                mod.SetOwnListValue("missingIcons", v)
                if mod.Redecorate then
                    mod.Redecorate()
                end -- blizzard's list too
            end,
        }, {
            type = "toggle",
            text = "Row Art",
            tooltip = "The instance's art across the left half of each group, fading out to the right.",
            getValue = function()
                return mod.Cfg().extraRowArt == true
            end,
            setValue = function(v)
                mod.Cfg().extraRowArt = v and true or false
                if mod.GFRetagRows then
                    mod.GFRetagRows()
                end
            end,
        })
        posY = posY - hgt
        local function Shown(key, default)
            local v = mod.Cfg()[key]
            if v == nil then
                v = mod.DEFAULTS[key]
            end
            if v == nil then
                v = default
            end
            return v and true or false
        end
        local function SetShown(key, v)
            mod.Cfg()[key] = v and true or false
            if mod.Redecorate then
                mod.Redecorate()
            end
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Specialization",
            tooltip = "Shows each member's specialization icon in place of the game's class and role icons. Off, the game's own icons stay.",
            getValue = function()
                return Shown("specIcons")
            end,
            setValue = function(v)
                SetShown("specIcons", v)
            end,
        }, {
            type = "toggle",
            text = "Show Group Leader",
            tooltip = "Puts a small crown above the group leader's icon.",
            getValue = function()
                return Shown("leaderCrown")
            end,
            setValue = function(v)
                SetShown("leaderCrown", v)
            end,
        })
        posY = posY - hgt
        -- the third line: playstyle and region tag (rows already drawn take them now)
        local function SetLine(key, v)
            mod.Cfg()[key] = v and true or false
            if mod.Redecorate then
                mod.Redecorate()
            end
            if mod.GFRetagRows then
                mod.GFRetagRows()
            end
        end
        local tagsCfg
        if mod.RegionList() then
            tagsCfg = {
                type = "toggle",
                text = "Region Tags",
                tooltip = mod.RegionIsLanguage()
                        and "Shows the leader's realm language (EN, DE, FR, ES, IT, PT, RU) after each group's playstyle."
                    or "Shows OCE, NA, MEX or BRA after each group's playstyle, from the leader's realm.",
                getValue = function()
                    return Shown("extraRegionTags", true)
                end,
                setValue = function(v)
                    SetLine("extraRegionTags", v)
                end,
            }
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Leader Rating",
            tooltip = "Shows the group leader's Mythic+ rating next to the role icons.",
            getValue = function()
                return Shown("leaderRating")
            end,
            setValue = function(v)
                SetShown("leaderRating", v)
            end,
        }, {
            type = "toggle",
            text = "Show Playstyle",
            tooltip = "Each group's playstyle (Learning, Relaxed, Competitive, Carry Offered) on its third line.",
            getValue = function()
                return Shown("extraShowPlaystyle", true)
            end,
            setValue = function(v)
                SetLine("extraShowPlaystyle", v)
            end,
        })
        posY = posY - hgt
        local notesCfg = {
            type = "toggle",
            text = "Show Group Notes",
            tooltip = "Shows each group's note on a line under it; hover the group for the whole note.",
            getValue = function()
                return mod.OwnListGet("groupNotes") == true
            end,
            setValue = function(v)
                mod.SetOwnListValue("groupNotes", v and true or false)
            end,
        }
        if tagsCfg then
            _, hgt = W:DualRow(hostFrame, posY, tagsCfg, notesCfg)
        else
            _, hgt = W:DualRow(hostFrame, posY, notesCfg, CUI.BlankRowCfg())
        end
        posY = posY - hgt

        -- the filter's dungeon / raid squares
        local function SetSquares(key, v)
            mod.Cfg()[key] = v and true or false
            if mod.Search_Layout then
                mod.Search_Layout()
            end
        end
        _, hgt = W:SectionHeader(hostFrame, "DUNGEON / RAID ROW", posY)
        posY = posY - hgt
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Dungeon Names",
            tooltip = "Each dungeon square shows the dungeon's short name (e.g. KR for Kings' Rest).",
            getValue = function()
                return mod.Cfg().dungeonAbbr == true
            end,
            setValue = function(v)
                SetSquares("dungeonAbbr", v)
            end,
        }, {
            type = "toggle",
            text = "Dungeon Keystone Level",
            tooltip = "Each dungeon square shows your best keystone level this season, colored by its score rarity.",
            getValue = function()
                return mod.Cfg().dungeonScore == true
            end,
            setValue = function(v)
                SetSquares("dungeonScore", v)
            end,
        })
        posY = posY - hgt

        -- what Hide Applicant Info hides (the profile's streamer* keys)
        local HIDE_INFO_ITEMS = {
            {
                key = "streamerTitle",
                label = "Title",
                tooltip = "Covers your group's title with a censor bar.",
            },
            {
                key = "streamerDungeon",
                label = "Dungeon",
                tooltip = "Covers the dungeon and description with a censor bar.",
            },
            {
                key = "streamerNames",
                label = "Class Names",
                tooltip = "Shows each applicant's class instead of their name.",
            },
            { key = "streamerRating", label = "Rating", tooltip = "Removes the rating column." },
            { key = "streamerSpec", label = "Specialization", tooltip = "Removes the spec column." },
            { key = "streamerNote", label = "Note", tooltip = "Hides each applicant's note." },
        }
        _, hgt = W:SectionHeader(hostFrame, "APPLICANT LIST", posY)
        posY = posY - hgt
        local applicantRow
        applicantRow, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "slider",
                text = "Applicant Row Height",
                min = 20,
                max = 64,
                step = 1,
                tooltip = "How tall each applicant row is.",
                getValue = function()
                    return mod.OwnListGet("applicantRowHeight") or 36
                end,
                setValue = function(v)
                    mod.SetOwnListValue("applicantRowHeight", v)
                end,
            },
            -- placeholder, the checklist replaces it
            {
                type = "dropdown",
                text = "Hide Applicant Info",
                tooltip = "What to hide on your listed group's page.",
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            }
        )
        posY = posY - hgt
        if not CUI._prebuilding then
            local region = applicantRow._rightRegion
            if region._control then
                region._control:Hide()
            end
            local dropdown, ddRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                HIDE_INFO_ITEMS,
                function(key)
                    return mod.OwnListGet(key) == true
                end,
                function(key, v)
                    mod.SetOwnListValue(key, v and true or false)
                end
            )
            CUI.PanelPP.Point(dropdown, "RIGHT", region, "RIGHT", -20, 0)
            region._control = dropdown
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(ddRefresh)
        end
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Class Colored Role Icons",
            tooltip = "Each applicant's role icons take their class color, in place of the role's blue, green or red.",
            getValue = function()
                return mod.OwnListGet("roleClassColors") == true
            end,
            setValue = function(v)
                mod.SetOwnListValue("roleClassColors", v and true or false)
            end,
        }, CUI.BlankRowCfg())
        posY = posY - hgt
        return posY
    end

    local function ResetMessage(scope)
        if scope == "session" then
            return CludesUI.L("Reset the session application counts to zero?")
        end
        if scope == "account" then
            return CludesUI.L("Reset the account application counts to zero?")
        end
        return CludesUI.L("Reset the character application counts to zero?")
    end

    AddAppsSections = function(hostFrame, posY)
        local W = CUI.Widgets
        local _, hgt

        _, hgt = W:SectionHeader(hostFrame, "M+ APPLICATIONS", posY)
        posY = posY - hgt

        local scopeValues = { session = "Session", character = "Character", account = "Account" }
        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Applications in Group Finder",
            tooltip = "A bar at the top of the Dungeons & Raids sidebar that counts your Mythic+ application results.",
            disabled = ModOff,
            disabledTooltip = "Group Finder",
            getValue = function()
                return APGet("enabled", false) == true
            end,
            setValue = function(v)
                APSet("enabled", v and true or false)
                CUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Counts Shown",
            tooltip = "Which totals the card shows. Hover the card for all three.",
            values = scopeValues,
            order = { "session", "character", "account" },
            disabled = APOff,
            disabledTooltip = APOffTip,
            getValue = function()
                return APGet("scope", "character")
            end,
            setValue = function(v)
                APSet("scope", v)
            end,
        })
        posY = posY - hgt

        -- application visibility: which results show on the bar (all on when unset)
        local VIS_LABEL = "Application Visibility"
        local VIS_ITEMS = {
            { key = "showAccepted", label = "Accepted", tooltip = "Invites you accepted." },
            {
                key = "showDeclined",
                label = "Declined",
                tooltip = "Declined by the leader, the group filled, or the application timed out.",
            },
            {
                key = "showDelisted",
                label = "Delisted",
                tooltip = "The group was delisted before answering.",
            },
            { key = "showCancelled", label = "Cancelled", tooltip = "You cancelled the application." },
        }
        -- search only sees labels + tooltips, so this hidden entry carries the
        -- checklist's names
        if CludesUI._RegisterSearchEntry then
            local words = {}
            for idx = 1, #VIS_ITEMS do
                local labelText = VIS_ITEMS[idx].label
                words[#words + 1] = labelText
                local loc = CludesUI.L(labelText)
                if loc ~= labelText then
                    words[#words + 1] = loc
                end
            end
            local labelLoc = CludesUI.L(VIS_LABEL)
            CludesUI._RegisterSearchEntry(
                VIS_LABEL,
                labelLoc ~= VIS_LABEL and labelLoc or nil,
                table.concat(words, " "),
                CludesUI._buildingModule,
                CludesUI._buildingPage,
                hostFrame._currentSection and hostFrame._currentSection._sectionName
            )
        end

        -- built-in textures, then sharedmedia's
        local texture, nameList, sequence = mod.BarTextureTables()
        local texValues, texOrder = {}, {}
        for _, key in ipairs(sequence) do
            if key ~= "---" then
                texValues[key] = nameList[key] or key
            end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = {
            itemHeight = 28,
            background = function(key)
                return texture[key]
            end,
        }
        local visRow
        visRow, hgt = W:DualRow(
            hostFrame,
            posY,
            -- placeholder, the checklist replaces it
            {
                type = "dropdown",
                text = VIS_LABEL,
                tooltip = "Choose which application results show on the bar.",
                disabled = APOff,
                disabledTooltip = APOffTip,
                values = { __placeholder = "..." },
                order = { "__placeholder" },
                getValue = function()
                    return "__placeholder"
                end,
                setValue = function() end,
            },
            {
                type = "dropdown",
                text = "Bar Texture",
                values = texValues,
                order = texOrder,
                disabled = APOff,
                disabledTooltip = APOffTip,
                getValue = function()
                    return APGet("texture", "none")
                end,
                setValue = function(v)
                    APSet("texture", v)
                end,
            }
        )
        posY = posY - hgt

        if not CUI._prebuilding then
            local region = visRow._leftRegion
            if region._control then
                region._control:Hide()
            end
            local visDD, visDDRefresh = CUI.BuildVisOptsCBDropdown(
                region,
                210,
                region:GetFrameLevel() + 2,
                VIS_ITEMS,
                function(key)
                    return APGet(key, true) == true
                end,
                function(key, v)
                    APSet(key, v and true or false)
                end,
                nil,
                nil,
                nil,
                nil,
                nil,
                { disabled = APOff, disabledTooltip = APOffTip }
            )
            CUI.PanelPP.Point(visDD, "RIGHT", region, "RIGHT", -20, 0)
            region._control = visDD
            region._lastInline = nil
            CUI.RegisterWidgetRefresh(visDDRefresh)
        end

        _, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Show Title",
            tooltip = 'The "M+ Applications" title above the bar.',
            disabled = APOff,
            disabledTooltip = APOffTip,
            getValue = function()
                return APGet("showTitle", true) ~= false
            end,
            setValue = function(v)
                APSet("showTitle", v and true or false)
            end,
        }, CUI.BlankRowCfg())
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "RESET APPLICATION COUNTS", posY)
        posY = posY - hgt
        local function Reset(labelText, scope)
            return function()
                CUI:ShowConfirmPopup({
                    title = labelText,
                    message = ResetMessage(scope),
                    confirmText = "Reset",
                    cancelText = "Cancel",
                    onConfirm = function()
                        mod.ResetApplications(scope)
                    end,
                })
            end
        end
        -- on / off only changes with a reload, so build time is enough
        local offOpts
        if ModOff() then
            local tipText = CUI.DisabledTooltip("Group Finder")
            offOpts = {
                { disabled = true, tooltip = tipText },
                { disabled = true, tooltip = tipText },
                { disabled = true, tooltip = tipText },
            }
        end
        _, hgt = W:WideTripleButton(
            hostFrame,
            "Reset Session",
            "Reset Character",
            "Reset Account",
            posY,
            Reset("Reset Session", "session"),
            Reset("Reset Character", "character"),
            Reset("Reset Account", "account"),
            nil,
            offOpts
        )
        posY = posY - hgt
        return posY
    end

    CUI:RegisterModule(ADDON_NAME, {
        title = "Group Finder",
        description = "Premade Groups search filters, group list, applicant list and application tools in the Dungeons & Raids window.",
        pages = { PAGE_SEARCH, PAGE_APPS },
        buildPage = function(page, hostFrame, yOffset)
            if page == PAGE_APPS then
                return BuildAppsPage(hostFrame, yOffset)
            end
            return BuildSearchPage(page, hostFrame, yOffset)
        end,
        -- a cached page whose header was dropped builds it again
        getHeaderBuilder = function(page)
            if page == PAGE_SEARCH then
                return mod.OwnListPreviewBuild
            end
        end,
        onReset = function()
            mod.ResetSettings()
            -- the account-wide sign up switches live on this page
            if CludesUIDB then
                CludesUIDB.quickSignup = false
                CludesUIDB.persistSignupNote = false
                CludesUIDB.signupNote = nil
            end
            if CUI._applyQuickSignup then
                CUI._applyQuickSignup()
            end
            if CUI._applyPersistSignupNote then
                CUI._applyPersistSignupNote()
            end
            if mod.ResetOwnList then
                mod.ResetOwnList()
            end
            if mod.Enabled() then
                mod.Search_Layout()
                mod.ApplyApplications()
            end
        end,
    })
end)
