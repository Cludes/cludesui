if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
--------------------------------------------------------------------------------
--  CludesUI_TextTags.lua
--  Custom text templates ("[hp:abr] | [hp:pct]%"): shared tag schema, parser,
--  preview and help text. Pure string logic (no frames, events or units), plus
--  the options glue a Custom text field shares (PopupOpts and below it).
--  A module binds the schema keys it draws to its own pieces (Bind) and paints
--  the parse through its own path: fmt has one %s per tag, keys names each one.
--  Secret values, DEAD/OFFLINE and abbreviation stay in the module's pieces.
--------------------------------------------------------------------------------
CludesUI = CludesUI or {}
local CludesUI = CludesUI

local type, pairs, error, tostring = type, pairs, error, tostring
local sfind, ssub, slower, sgsub, sformat = string.find, string.sub, string.lower, string.gsub, string.format
local tconcat, unpack = table.concat, unpack

local TextTags = {}
CludesUI.TextTags = TextTags

-------------------------------------------------------------------------------
--  Unit schema
--  reads: the value a key shows -- "hp", "pp", "abs", "habs", "id" (name or
--  level, changes on identity events only), "tgt" (the unit's target),
--  "roster" (group membership). width: estimated pixels. sample: preview value.
-------------------------------------------------------------------------------
TextTags.UNIT = {
    mods = { "max", "abr", "pct", "first", "last", "abbr" }, -- order of the modifiers inside a key
    modAliases = { percent = "pct" },
    tags = { -- order of the help text
        { tag = "hp", aliases = { "health" }, keys = { "hp", "hp:abr", "hp:max", "hp:max:abr", "hp:pct" } },
        { tag = "pp", aliases = { "power" }, keys = { "pp", "pp:abr", "pp:max", "pp:max:abr", "pp:pct" } },
        { tag = "absorb", keys = { "absorb", "absorb:abr" } },
        { tag = "healabsorb", keys = { "healabsorb", "healabsorb:abr" } },
        { tag = "name", keys = { "name", "name:first", "name:last", "name:abbr" } },
        { tag = "target", keys = { "target", "target:first", "target:last", "target:abbr" } },
        { tag = "level", keys = { "level" } },
        { tag = "group", keys = { "group" } },
    },
    keys = {
        ["hp"] = { reads = "hp", width = 45, sample = "132456" },
        ["hp:abr"] = { reads = "hp", width = 38, sample = "132 K" },
        ["hp:max"] = { reads = "hp", width = 45, sample = "150000" },
        ["hp:max:abr"] = { reads = "hp", width = 38, sample = "150 K" },
        ["hp:pct"] = { reads = "hp", width = 30, sample = "88" },
        ["pp"] = { reads = "pp", width = 45, sample = "31250" },
        ["pp:abr"] = { reads = "pp", width = 38, sample = "31 K" },
        ["pp:max"] = { reads = "pp", width = 45, sample = "50000" },
        ["pp:max:abr"] = { reads = "pp", width = 38, sample = "50 K" },
        ["pp:pct"] = { reads = "pp", width = 30, sample = "62" },
        ["absorb"] = { reads = "abs", width = 45, sample = "12345" },
        ["absorb:abr"] = { reads = "abs", width = 38, sample = "12 K" },
        ["healabsorb"] = { reads = "habs", width = 45, sample = "4200" },
        ["healabsorb:abr"] = { reads = "habs", width = 38, sample = "4 K" },
        ["name"] = { reads = "id", width = 80, sample = "Thrall" },
        ["name:first"] = { reads = "id", width = 48, sample = "Thrall" },
        ["name:last"] = { reads = "id", width = 64, sample = "Stormrage" },
        ["name:abbr"] = { reads = "id", width = 72, sample = "I. Stormrage" },
        ["target"] = { reads = "tgt", width = 80, sample = "Jaina" },
        ["target:first"] = { reads = "tgt", width = 48, sample = "Jaina" },
        ["target:last"] = { reads = "tgt", width = 72, sample = "Proudmoore" },
        ["target:abbr"] = { reads = "tgt", width = 72, sample = "J. Proudmoore" },
        ["level"] = { reads = "id", width = 24, sample = "80" },
        ["group"] = { reads = "roster", width = 10, sample = "3" },
    },
    -- Built on demand: the active locale is resolved only at ADDON_LOADED.
    descs = function()
        return {
            tags = {
                hp = CludesUI.L("Health"),
                pp = CludesUI.L("Power"),
                absorb = CludesUI.L("Absorb shield"),
                healabsorb = CludesUI.L("Heal absorb"),
                name = CludesUI.L("Unit name"),
                target = CludesUI.L("Name of the unit's target"),
                level = CludesUI.L("Unit level"),
                group = CludesUI.L("Raid group number"),
            },
            mods = {
                abr = CludesUI.L("Abbreviated (132 K)"),
                max = CludesUI.L("Maximum instead of current"),
                pct = CludesUI.L("Percent, number only"),
                first = CludesUI.L("First word"),
                last = CludesUI.L("Last word"),
                abbr = CludesUI.L("Initials, last word whole (I. Stormrage)"),
            },
            -- Short, for the suggestion list.
            keys = {
                ["hp"] = CludesUI.L("Current health"),
                ["hp:abr"] = CludesUI.L("Current, abbreviated"),
                ["hp:max"] = CludesUI.L("Maximum health"),
                ["hp:max:abr"] = CludesUI.L("Maximum, abbreviated"),
                ["hp:pct"] = CludesUI.L("Health percent"),
                ["pp"] = CludesUI.L("Current power"),
                ["pp:abr"] = CludesUI.L("Current, abbreviated"),
                ["pp:max"] = CludesUI.L("Maximum power"),
                ["pp:max:abr"] = CludesUI.L("Maximum, abbreviated"),
                ["pp:pct"] = CludesUI.L("Power percent"),
                ["absorb"] = CludesUI.L("Absorb shield"),
                ["absorb:abr"] = CludesUI.L("Absorb, abbreviated"),
                ["healabsorb"] = CludesUI.L("Heal absorb"),
                ["healabsorb:abr"] = CludesUI.L("Heal absorb, abbreviated"),
                ["name"] = CludesUI.L("Unit name"),
                ["name:first"] = CludesUI.L("First name"),
                ["name:last"] = CludesUI.L("Last name"),
                ["name:abbr"] = CludesUI.L("Abbreviated"),
                ["target"] = CludesUI.L("Target's name"),
                ["target:first"] = CludesUI.L("Target, first name"),
                ["target:last"] = CludesUI.L("Target, last name"),
                ["target:abbr"] = CludesUI.L("Target, abbreviated"),
                ["level"] = CludesUI.L("Unit level"),
                ["group"] = CludesUI.L("Raid group"),
            },
        }
    end,
    examples = { "[hp:max:abr]", "[name:abbr] [hp:pct]%", "[hp:abr] | [pp]/[pp:max]" },
}

-------------------------------------------------------------------------------
--  Bind: a catalog is the schema narrowed to the keys a module draws. map is
--  { schema key = the module's own piece }; the core never looks at the values.
--  A key the module leaves out is unknown to that catalog.
-------------------------------------------------------------------------------
function TextTags.Bind(schema, map)
    local category =
        { schema = schema, map = {}, keys = {}, tags = {}, names = {}, mods = {}, cache = {}, count = 0 }
    for key, val in pairs(map) do
        if not schema.keys[key] then
            error("TextTags.Bind: unknown key " .. tostring(key), 2)
        end
        category.map[key] = val
    end
    for idx = 1, #schema.tags do
        local def, bound = schema.tags[idx], {}
        for k = 1, #def.keys do
            local key = def.keys[k]
            if category.map[key] ~= nil then
                bound[#bound + 1] = key
                category.keys[#category.keys + 1] = key
            end
        end
        if #bound > 0 then
            category.tags[#category.tags + 1] = { tag = def.tag, aliases = def.aliases, keys = bound }
            category.names[def.tag] = def.tag
            if def.aliases then
                for a = 1, #def.aliases do
                    category.names[def.aliases[a]] = def.tag
                end
            end
        end
    end
    for idx = 1, #schema.mods do
        category.mods[schema.mods[idx]] = schema.mods[idx]
    end
    if schema.modAliases then
        for alias, mod in pairs(schema.modAliases) do
            category.mods[alias] = mod
        end
    end
    return category
end

-------------------------------------------------------------------------------
--  Parse
-------------------------------------------------------------------------------
local function Escape(s)
    return (sgsub(sgsub(s, "%%", "%%%%"), "|", "||"))
end

-- "hp:ABR:max" -> "hp:max:abr" when the catalog binds it, else nil. Modifier
-- order is free; an empty part, an unknown or a repeated modifier is no key.
local modSeen = {}
local function ResolveKey(category, inner)
    inner = slower(inner)
    local s, e = sfind(inner, ":", 1, true)
    local tag = category.names[s and ssub(inner, 1, s - 1) or inner]
    if not tag then
        return nil
    end
    if not s then
        return category.map[tag] ~= nil and tag or nil
    end
    for key in pairs(modSeen) do
        modSeen[key] = nil
    end
    local place = e + 1
    while true do
        local ns = sfind(inner, ":", place, true)
        local mod = category.mods[ssub(inner, place, (ns or 0) - 1)]
        if not mod or modSeen[mod] then
            return nil
        end
        modSeen[mod] = true
        if not ns then
            break
        end
        place = ns + 1
    end
    local sequence, key = category.schema.mods, tag
    for idx = 1, #sequence do
        if modSeen[sequence[idx]] then
            key = key .. ":" .. sequence[idx]
        end
    end
    return category.map[key] ~= nil and key or nil
end

local strlen = strlenutf8 or string.len

--- Parses a template against a catalog: nil for an empty or non-string one,
--- else { fmt, keys, has, reads, literalChars, unknown }. fmt is escaped with
--- one %s per tag, keys the schema key of each, has / reads sets of the keys
--- and value classes used, literalChars the UTF-8 length outside the tags,
--- unknown the bracketed text that is no bound key (left as typed, no repeats).
--- "%" is escaped and "|" doubled: no colour or texture escape can be typed.
--- Cached and shared by every reader (read-only); transient (the popup's
--- per-keystroke preview) reads the cache but never fills it.
function TextTags.Parse(category, template, transient)
    if type(template) ~= "string" or template == "" then
        return nil
    end
    local hit = category.cache[template]
    if hit then
        return hit
    end
    local fmt, literal, keyList, has, reads, unknown, seen = {}, {}, {}, {}, {}, {}, {}
    local place = 1
    while true do
        -- Any bracketed text: what is no bound key stays as typed and is named.
        local s, e, inner = sfind(template, "%[([^%[%]]+)%]", place)
        local lit = ssub(template, place, (s or 0) - 1)
        local key = s and ResolveKey(category, inner)
        if s and not key then
            local raw = ssub(template, s, e)
            lit = lit .. raw
            if not seen[raw] then
                seen[raw] = true
                unknown[#unknown + 1] = raw
            end
        end
        fmt[#fmt + 1] = Escape(lit)
        literal[#literal + 1] = lit
        if key then
            fmt[#fmt + 1] = "%s"
            keyList[#keyList + 1] = key
            has[key] = true
            reads[category.schema.keys[key].reads] = true
        end
        if not s then
            break
        end
        place = e + 1
    end
    hit = {
        fmt = tconcat(fmt),
        keys = keyList,
        has = has,
        reads = reads,
        literalChars = strlen(tconcat(literal)),
        unknown = unknown,
    }
    if transient then
        return hit
    end
    if category.count >= 64 then
        category.cache, category.count = {}, 0
    end
    category.cache[template] = hit
    category.count = category.count + 1
    return hit
end

-------------------------------------------------------------------------------
--  Preview, width, help
-------------------------------------------------------------------------------
local scratch = {}
-- The schema's descriptions, translated once per catalog on first use (help
-- and completion run only after ADDON_LOADED, when the locale is active).
local function Descs(category)
    local d = category.descs
    if not d then
        d = category.schema.descs and category.schema.descs() or {}
        category.descs = d
    end
    return d
end
local DIM, MOD, UNKNOWN = CludesUI.COLOR_CODES.DIM, "|cffffd27a", "|cffffa633"

--- The parse filled with the schema's samples. mark (a colour escape such as
--- "|cffffa633"), when given, colours the unknown tags left as text.
function TextTags.Preview(category, parsed, mark)
    local keyList, defs = parsed.keys, category.schema.keys
    for idx = 1, #keyList do
        scratch[idx] = defs[keyList[idx]].sample
    end
    local result = sformat(parsed.fmt, unpack(scratch, 1, #keyList))
    if mark then
        local unknown = parsed.unknown
        for idx = 1, #unknown do
            -- As it stands in fmt: "|" doubled; "%" escaped for the replacement.
            local isShown = sgsub(unknown[idx], "|", "||")
            result = sgsub(result, sgsub(isShown, "%p", "%%%0"), mark .. sgsub(isShown, "%%", "%%%%") .. "|r")
        end
    end
    return result
end

--- Estimated pixel width: each key's schema width, 5 per literal character.
--- override(key), when given, may return a number to replace a key's width.
function TextTags.EstimateWidth(category, parsed, override)
    local keyList, defs = parsed.keys, category.schema.keys
    local wid = parsed.literalChars * 5
    for idx = 1, #keyList do
        local key = keyList[idx]
        wid = wid + (override and override(key) or defs[key].width)
    end
    return wid
end

--- The info text for the popup: syntax, one line per bound tag with its
--- aliases and modifiers, the modifier legend, and examples with their result.
--- opts (optional): examples replaces the schema's (any using an unbound key
--- is skipped); tagNotes { tag = localized text } adds "(text)" to a tag.
function TextTags.HelpText(category, options)
    local descs = Descs(category)
    local tagDescs, modDescs = descs.tags or {}, descs.mods or {}
    local tagNotes = options and options.tagNotes or {}
    local ACC = CludesUI.CLUDES_GREEN
    local head = CludesUI.HexColor(ACC.r, ACC.g, ACC.b)
    local orWord = " " .. DIM .. CludesUI.L("or") .. "|r "
    local sequence = category.schema.mods
    local lines = {
        head .. CludesUI.L("Syntax") .. "|r",
        DIM .. CludesUI.L("Tags in [brackets], add modifiers with a colon, in any order.") .. "|r",
        "",
        head .. CludesUI.L("Tags") .. "|r",
    }
    local used = {}
    for idx = 1, #category.tags do
        local t, mods = category.tags[idx], {}
        for k = 1, #t.keys do
            for m = 1, #sequence do
                if sfind(t.keys[k] .. ":", ":" .. sequence[m] .. ":", 1, true) then
                    mods[sequence[m]] = true
                end
            end
        end
        local nameList, entries = { "[" .. t.tag .. "]" }, {}
        if t.aliases then
            for a = 1, #t.aliases do
                nameList[#nameList + 1] = "[" .. t.aliases[a] .. "]"
            end
        end
        for m = 1, #sequence do
            if mods[sequence[m]] then
                entries[#entries + 1] = sequence[m]
                used[sequence[m]] = true
            end
        end
        local desc = tagDescs[t.tag]
        if desc and tagNotes[t.tag] then
            desc = desc .. " (" .. tagNotes[t.tag] .. ")"
        end
        lines[#lines + 1] = tconcat(nameList, orWord)
            .. (desc and ("  " .. DIM .. desc .. "|r") or "")
            .. (#entries > 0 and ("  " .. MOD .. tconcat(entries, " ") .. "|r") or "")
    end
    local modAliases = category.schema.modAliases or {}
    local first = true
    for m = 1, #sequence do
        local mod = sequence[m]
        if used[mod] then
            if first then
                first = false
                lines[#lines + 1] = ""
                lines[#lines + 1] = head .. CludesUI.L("Modifiers") .. "|r"
            end
            local line = MOD .. mod .. "|r"
            for alias, target in pairs(modAliases) do
                if target == mod then
                    line = line .. orWord .. MOD .. alias .. "|r"
                end
            end
            lines[#lines + 1] = line .. (modDescs[mod] and ("  " .. DIM .. modDescs[mod] .. "|r") or "")
        end
    end
    local examples = options and options.examples or category.schema.examples
    local isShown = 0
    for idx = 1, #(examples or {}) do
        local parsed = TextTags.Parse(category, examples[idx])
        if parsed and #parsed.unknown == 0 then
            if isShown == 0 then
                lines[#lines + 1] = ""
                lines[#lines + 1] = head .. CludesUI.L("Examples") .. "|r"
            end
            isShown = isShown + 1
            -- Modifiers in their legend colour; "|" doubled before any colour escape is added.
            local shownText =
                sgsub(sgsub(examples[idx], "|", "||"), "%[(%w+)(:[%w:]+)%]", "[%1" .. MOD .. "%2|r]")
            lines[#lines + 1] = shownText
                .. "  "
                .. DIM
                .. "=  "
                .. TextTags.Preview(category, parsed)
                .. "|r"
        end
    end
    return tconcat(lines, "\n")
end

--- Completion for the tag being typed: text up to cursor (in bytes, as
--- EditBox:GetCursorPosition counts) ending in "[" plus an unclosed partial
--- tag. Returns nil, or (items, from, to): items { text = "hp:abr]", label (modifiers coloured),
--- desc, detail = sample } in schema order, and the text[from..to] range an
--- item replaces (a "]" right after the caret included). A bare tag name lists
--- its variants, a partial name one entry per matching tag. An item with longer
--- variants inserts without "]" (its variants are listed next), unless it is
--- already typed in full.
function TextTags.Complete(category, textValue, cursor)
    if type(textValue) ~= "string" then
        return nil
    end
    local before = ssub(textValue, 1, cursor)
    local open = before:match(".*()%[")
    if not open then
        return nil
    end
    local partial = slower(ssub(before, open + 1))
    if not partial:match("^[%w:]*$") then
        return nil
    end
    local colon = sfind(partial, ":", 1, true)
    -- The partial as a key (aliases resolved, any modifier order), to tell
    -- "already typed in full".
    local typed = ResolveKey(category, partial) or partial
    -- After a colon: the complete modifiers typed (done, by canonical name)
    -- and the partial last one; a modifier that is unknown or repeated ends
    -- the suggestions, as it does the parse.
    local done, last = {}, nil
    if colon then
        local place = colon + 1
        while true do
            local nx = sfind(partial, ":", place, true)
            if not nx then
                last = ssub(partial, place)
                break
            end
            local m = category.mods[ssub(partial, place, nx - 1)]
            if not m or done[m] then
                return nil
            end
            done[m] = true
            place = nx + 1
        end
    end
    -- A key fits when it holds every done modifier plus one more whose name
    -- or alias starts with last.
    local function Fits(key)
        local mods = {}
        for m in key:gmatch(":(%w+)") do
            mods[m] = true
        end
        for m in pairs(done) do
            if not mods[m] then
                return false
            end
        end
        for m in pairs(mods) do
            if not done[m] then
                for name, canon in pairs(category.mods) do
                    if canon == m and ssub(name, 1, #last) == last then
                        return true
                    end
                end
            end
        end
        return false
    end
    local descs = Descs(category).keys or {}
    local itemList, seen, defs = {}, {}, category.schema.keys
    local function Add(key)
        if seen[key] then
            return
        end
        seen[key] = true
        local open = false
        if key ~= typed then
            for k = 1, #category.keys do
                if ssub(category.keys[k], 1, #key + 1) == key .. ":" then
                    open = true
                    break
                end
            end
        end
        local labelText = sgsub(key, "^(%w+)(:.+)$", "%1" .. MOD .. "%2|r")
        itemList[#itemList + 1] = {
            text = open and key or (key .. "]"),
            label = labelText,
            desc = descs[key],
            detail = defs[key].sample,
        }
    end
    for idx = 1, #category.tags do
        local t = category.tags[idx]
        local nameList = { t.tag }
        if t.aliases then
            for a = 1, #t.aliases do
                nameList[#nameList + 1] = t.aliases[a]
            end
        end
        for num = 1, #nameList do
            local name = nameList[num]
            if colon then
                if ssub(partial, 1, colon - 1) == name then
                    for k = 1, #t.keys do
                        if Fits(t.keys[k]) then
                            Add(t.keys[k])
                        end
                    end
                end
            elseif partial == name then
                for k = 1, #t.keys do
                    Add(t.keys[k])
                end
            elseif ssub(name, 1, #partial) == partial then
                Add(t.keys[1])
            end
        end
    end
    if #itemList == 0 then
        return nil
    end
    local to = cursor
    if ssub(textValue, cursor + 1, cursor + 1) == "]" then
        to = cursor + 1
    end
    return itemList, open + 1, to
end

--- Fills the options of CludesUI:ShowInputPopup for a template field and
--- returns them: preview (the sample line and a hint naming unknown tags),
--- previewLabel, complete (tag suggestions), infoTooltip (the help text, built
--- on hover) and infoTooltipOpts. helpOpts goes to TextTags.HelpText.
function TextTags.PopupOpts(category, options, helpOpts)
    options = options or {}
    options.preview = function(textValue)
        -- The edit box doubles a typed "|"; templates are stored with single ones.
        local parsed = TextTags.Parse(
            category,
            type(textValue) == "string" and sgsub(textValue, "||", "|") or textValue,
            true
        )
        if not parsed then
            return nil, nil
        end
        local hint
        if #parsed.unknown > 0 then
            hint = CludesUI.Lf(
                "Unknown tags, shown as typed: %s",
                (sgsub(tconcat(parsed.unknown, ", "), "|", "||"))
            )
        end
        return TextTags.Preview(category, parsed, UNKNOWN), hint
    end
    options.previewLabel = CludesUI.L("Preview")
    options.complete = function(textValue, cursor)
        return TextTags.Complete(category, textValue, cursor)
    end
    options.infoTooltip = function()
        return TextTags.HelpText(category, helpOpts)
    end
    options.infoTooltipOpts =
        { width = 360, justify = "LEFT", anchorPoint = "TOPRIGHT", anchorTo = "TOPLEFT", anchorX = -8 }
    return options
end

-------------------------------------------------------------------------------
--  A Custom text field's options: the template popup, the dropdown entry that
--  opens it and the Spec Overrides accessor, shared by every module offering
--  Custom text. Called only from options pages.
-------------------------------------------------------------------------------
local EDIT_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-edit.png"
local CLOSE_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"
TextTags.EDIT_ICON = EDIT_ICON

--- The template popup. o: cat (the module's catalog), get() / set(text) (the stored
--- template, single pipes), color (the preview's text colour; nil = white), tagNotes
--- (as TextTags.HelpText's), onSave (after the template is stored). Spaces only opens
--- the popup again with a hint instead of closing unsaved.
function TextTags.EditPopup(o, warning)
    local current = o.get()
    -- The edit box holds a typed "|" doubled.
    if type(current) == "string" then
        current = sgsub(current, "|", "||")
    else
        current = nil
    end
    -- 120 letters for new input; a longer stored template (import) keeps its length.
    local maxLen = math.max(120, current and strlenutf8(current) or 0)
    local popupOpts = {
        title = CludesUI.L("Custom Text"),
        message = CludesUI.L("Tags in [brackets] show live values, other text stays as typed.")
            .. "\n"
            .. CludesUI.L("Type [ for suggestions, the (i) lists every tag."),
        messageSize = 10,
        previewColor = o.color,
        placeholder = "[name] - [hp:pct]%",
        initialText = (not warning and current) or "",
        maxLetters = maxLen,
        showCount = true,
        warning = warning,
        onConfirm = function(txt)
            txt = sgsub(sgsub(sgsub(tostring(txt or ""), "||", "|"), "^%s+", ""), "%s+$", "")
            if txt == "" then
                TextTags.EditPopup(o, CludesUI.L("Enter at least one tag or character."))
                return
            end
            o.set(txt)
            if o.onSave then
                o.onSave()
            end
        end,
    }
    TextTags.PopupOpts(o.cat, popupOpts, o.tagNotes and { tagNotes = o.tagNotes } or nil)
    CludesUI:ShowInputPopup(popupOpts)
end

--- A copy of a text dropdown's values whose "custom" entry is an action opening the
--- popup (edit; nil adds none), marked with the edit pencil. o.text: that entry's
--- label (nil: "Custom"); o.selected(): the pencil at full alpha while true (nil:
--- always); o.removeKey: that entry in the house red with the close X. The values'
--- own _menuOpts still dress their other entries; the menu reads all of it when it
--- is built.
function TextTags.MenuValues(values, edit, o)
    local val = CopyTable(values)
    if edit then
        val.custom = { text = (o and o.text) or "Custom", action = edit }
    end
    local mo = val._menuOpts or {}
    val._menuOpts = mo
    local icon, iconColor, labelColor = mo.icon, mo.iconColor, mo.labelColor
    local selected, removeKey = o and o.selected, o and o.removeKey
    mo.icon = function(key)
        if key == "custom" then
            return EDIT_ICON
        end
        if key == removeKey then
            return CLOSE_ICON
        end
        if icon then
            return icon(key)
        end
    end
    mo.iconSize = mo.iconSize or function()
        return 12
    end
    mo.iconClearScroll = true
    mo.iconColor = function(key)
        if key == "custom" then
            return 1, 1, 1, (not selected or selected()) and 1 or 0.75
        end
        if key == removeKey then
            return 1, 0.35, 0.35, 0.75
        end
        if iconColor then
            return iconColor(key)
        end
    end
    mo.labelColor = function(key)
        if key == removeKey then
            return 1, 0.35, 0.35, 0.8
        end
        if labelColor then
            return labelColor(key)
        end
    end
    return val
end

--- Spec Overrides' accessor for a template the popup writes directly: the capture
--- reads and restores it as label .. " Custom Format" (get() / set(v); nil clears).
function TextTags.AddFormatAccessor(region, labelText, get, set)
    CludesUI.AddCaptureAccessor(region, {
        type = "input",
        text = labelText .. " Custom Format",
        getValue = function()
            return get() or ""
        end,
        setValue = function(val)
            set((val ~= "" and val) or nil)
        end,
    })
end
