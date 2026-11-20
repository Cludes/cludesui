if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  expressions.lua - type a filter like "hasBL and hasBR and healer > 0"
--  our own little language, parsed into closures: nothing typed ever runs
--  as lua. saved as extraExpr
-------------------------------------------------------------------------------
local FOLDER, mod = ...
if CludesUI.HELD_BACK_ADDONS[FOLDER] then
    return
end -- held back (CludesUIGroupFinder.lua)
local GFNS = mod
local CM = mod.CUI

local EXPR_TEX = "Interface\\AddOns\\" .. FOLDER .. "\\media\\icons\\cui-expression.png"
local Secret = CludesUI.IsSecret
local function Readable(t)
    return type(t) == "table" and not Secret(t) and not (canaccesstable and not canaccesstable(t))
end

-------------------------------------------------------------------------------
--  words you can use (any case)
-------------------------------------------------------------------------------
local CLASS_WORDS = {
    warrior = "WARRIOR",
    paladin = "PALADIN",
    hunter = "HUNTER",
    rogue = "ROGUE",
    priest = "PRIEST",
    deathknight = "DEATHKNIGHT",
    dk = "DEATHKNIGHT",
    shaman = "SHAMAN",
    mage = "MAGE",
    warlock = "WARLOCK",
    monk = "MONK",
    druid = "DRUID",
    demonhunter = "DEMONHUNTER",
    dh = "DEMONHUNTER",
    evoker = "EVOKER",
}
local WORDS = {
    tank = "tanks",
    healer = "healers",
    dps = "dps",
    members = "members",
    tankopen = "tanksLeft",
    healeropen = "healersLeft",
    dpsopen = "dpsLeft",
    hasbl = "hasBL",
    hasbr = "hasBR",
    myclass = "myClass",
    score = "score",
    ilvl = "ilvl",
    age = "age",
    friends = "friends",
    voice = "voice",
}
for wid, cls in pairs(CLASS_WORDS) do
    WORDS[wid] = cls
end
local LUST = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
local BREZ = { DRUID = true, DEATHKNIGHT = true, WARLOCK = true, PALADIN = true }

-------------------------------------------------------------------------------
--  tokens
-------------------------------------------------------------------------------
local TWO = {
    ["<="] = "<=",
    [">="] = ">=",
    ["=="] = "==",
    ["~="] = "!=",
    ["!="] = "!=",
    ["&&"] = "and",
    ["||"] = "or",
}
local ONE = {
    ["+"] = "+",
    ["-"] = "-",
    ["*"] = "*",
    ["/"] = "/",
    ["("] = "(",
    [")"] = ")",
    ["<"] = "<",
    [">"] = ">",
    ["="] = "==",
    ["!"] = "not",
}
local KEYWORDS = { ["and"] = "and", ["or"] = "or", ["not"] = "not" }

local function Tokens(source)
    local result, index, n = {}, 1, #source
    while index <= n do
        local c = source:sub(index, index)
        if c:match("%s") then
            index = index + 1
        else
            local num = source:match("^%d+%.?%d*", index) or source:match("^%.%d+", index)
            local word = not num and source:match("^[%a_][%w_]*", index)
            local two = source:sub(index, index + 1)
            if num then
                result[#result + 1] = { t = "num", v = tonumber(num) }
                index = index + #num
            elseif word then
                local lw = word:lower()
                if KEYWORDS[lw] then
                    result[#result + 1] = { t = KEYWORDS[lw] }
                elseif lw == "true" or lw == "false" then
                    result[#result + 1] = { t = "num", v = lw == "true" and 1 or 0 }
                elseif WORDS[lw] then
                    result[#result + 1] = { t = "var", v = WORDS[lw] }
                else
                    return nil, CludesUI.Lf("unknown word: %1$s", word)
                end
                index = index + #word
            elseif TWO[two] then
                result[#result + 1] = { t = TWO[two] }
                index = index + 2
            elseif ONE[c] then
                result[#result + 1] = { t = ONE[c] }
                index = index + 1
            else
                return nil, CludesUI.Lf('can\'t use "%1$s"', c)
            end
        end
    end
    return result
end

-------------------------------------------------------------------------------
--  parser: each rule returns function(env) -> number (true = 1).
--  a word we can't read for a group throws, and the group is kept
-------------------------------------------------------------------------------
local UNREADABLE = {}
local function Truth(val)
    return val ~= 0
end

local function Compile(source)
    local toks, err = Tokens(source)
    if not toks then
        return nil, err
    end
    if #toks == 0 then
        return nil
    end
    local place = 1
    local function peek()
        return toks[place] and toks[place].t
    end
    local function take()
        place = place + 1
        return toks[place - 1]
    end

    local Or
    local function Primary()
        local tk = take()
        if not tk then
            error(CludesUI.L("ends too soon"), 0)
        end
        if tk.t == "num" then
            local val = tk.v
            return function()
                return val
            end
        elseif tk.t == "var" then
            local k = tk.v
            return function(environ)
                local val = environ[k]
                if val == nil then
                    error(UNREADABLE, 0)
                end
                return val
            end
        elseif tk.t == "(" then
            local frame = Or()
            if take() == nil or toks[place - 1].t ~= ")" then
                error(CludesUI.L("missing )"), 0)
            end
            return frame
        end
        error(CludesUI.Lf('unexpected "%1$s"', tk.t), 0)
    end
    local function Unary()
        if peek() == "-" then
            take()
            local frame = Unary()
            return function(environ)
                return -frame(environ)
            end
        end
        return Primary()
    end
    local function Mul()
        local frame = Unary()
        while peek() == "*" or peek() == "/" do
            local op, a, b = take().t, frame, Unary()
            if op == "*" then
                frame = function(environ)
                    return a(environ) * b(environ)
                end
            else
                frame = function(environ)
                    local skinData = b(environ)
                    return skinData == 0 and 0 or a(environ) / skinData
                end
            end
        end
        return frame
    end
    local function Add()
        local frame = Mul()
        while peek() == "+" or peek() == "-" do
            local op, a, b = take().t, frame, Mul()
            if op == "+" then
                frame = function(environ)
                    return a(environ) + b(environ)
                end
            else
                frame = function(environ)
                    return a(environ) - b(environ)
                end
            end
        end
        return frame
    end
    local CMP = {
        ["<"] = function(posX, posY)
            return posX < posY
        end,
        [">"] = function(posX, posY)
            return posX > posY
        end,
        ["<="] = function(posX, posY)
            return posX <= posY
        end,
        [">="] = function(posX, posY)
            return posX >= posY
        end,
        ["=="] = function(posX, posY)
            return posX == posY
        end,
        ["!="] = function(posX, posY)
            return posX ~= posY
        end,
    }
    local function Cmp()
        local frame = Add()
        local test = CMP[peek() or ""]
        if test then
            take()
            local a, b = frame, Add()
            frame = function(environ)
                return test(a(environ), b(environ)) and 1 or 0
            end
        end
        return frame
    end
    local function Not()
        if peek() == "not" then
            take()
            local frame = Not()
            return function(environ)
                return Truth(frame(environ)) and 0 or 1
            end
        end
        return Cmp()
    end
    local function And()
        local frame = Not()
        while peek() == "and" do
            take()
            local a, b = frame, Not()
            frame = function(environ)
                return (Truth(a(environ)) and Truth(b(environ))) and 1 or 0
            end
        end
        return frame
    end
    Or = function()
        local frame = And()
        while peek() == "or" do
            take()
            local a, b = frame, And()
            frame = function(environ)
                return (Truth(a(environ)) or Truth(b(environ))) and 1 or 0
            end
        end
        return frame
    end

    local success, frame = pcall(Or)
    if not success then
        return nil, frame
    end
    if place <= #toks then
        return nil, CludesUI.Lf('unexpected "%1$s"', toks[place].t)
    end
    return frame
end

-------------------------------------------------------------------------------
--  the saved expression, recompiled when it changes
-------------------------------------------------------------------------------
local compiled, compiledFor, compileErr

local function Current()
    local cfg = GFNS.Cfg and GFNS.Cfg()
    local textValue = cfg and cfg.extraExpr
    if textValue ~= compiledFor then
        compiledFor = textValue
        compiled, compileErr = nil, nil
        if type(textValue) == "string" and textValue:find("%S") then
            compiled, compileErr = Compile(textValue)
        end
    end
    return compiled, compileErr
end

GFNS.ExtraExprActive = function()
    return Current() ~= nil
end

-- one group's words, nil when the game hides one
local environ = {}
local function Fill(ident, details)
    wipe(environ)
    local function num(val)
        if type(val) == "number" and not Secret(val) then
            return val
        end
    end
    local counts = C_LFGList.GetSearchResultMemberCounts(ident)
    if Readable(counts) then
        environ.tanks, environ.healers, environ.dps =
            num(counts.TANK), num(counts.HEALER), num(counts.DAMAGER)
        environ.tanksLeft, environ.healersLeft = num(counts.TANK_REMAINING), num(counts.HEALER_REMAINING)
        environ.dpsLeft = num(counts.DAMAGER_REMAINING)
    end
    local n = num(details.numMembers)
    environ.members = n
    if n then
        local _, mine = UnitClass("player")
        local lust, brez, same, all = 0, 0, 0, true
        for _, cls in pairs(CLASS_WORDS) do
            environ[cls] = 0
        end
        for index = 1, n do
            local p = C_LFGList.GetSearchResultPlayerInfo(ident, index)
            local cls = Readable(p) and p.classFilename
            if cls and not Secret(cls) then
                environ[cls] = (environ[cls] or 0) + 1
                if LUST[cls] then
                    lust = 1
                end
                if BREZ[cls] then
                    brez = 1
                end
                if cls == mine then
                    same = same + 1
                end
            else
                all = false
            end
        end
        -- unreadable member: class words can't be trusted
        if all then
            environ.hasBL, environ.hasBR, environ.myClass = lust, brez, same
        else
            for _, cls in pairs(CLASS_WORDS) do
                environ[cls] = nil
            end
        end
    end
    environ.score = num(details.leaderOverallDungeonScore)
    environ.ilvl = num(details.requiredItemLevel)
    local age = num(details.age)
    environ.age = age and math.floor(age / 60)
    local f1, f2, f3 = num(details.numBNetFriends), num(details.numCharFriends), num(details.numGuildMates)
    if f1 and f2 and f3 then
        environ.friends = f1 + f2 + f3
    end
    local vc = details.voiceChat
    if not Secret(vc) then
        environ.voice = (type(vc) == "string" and vc ~= "") and 1 or 0
    end
end

GFNS.ExtraExprKeep = function(ident, details)
    local frame = Current()
    if not frame or not Readable(details) then
        return true
    end
    Fill(ident, details)
    local success, val = pcall(frame, environ)
    if not success then
        return true
    end -- a word this group hides: keep it
    return Truth(val)
end

-------------------------------------------------------------------------------
--  the button and its box
-------------------------------------------------------------------------------
-- the reference under the box: hover a tag for help, click to type it
local SECTIONS = {
    {
        title = CludesUI.L("Words"),
        boxes = {
            {
                title = CludesUI.L("Open Slots"),
                color = { 0.35, 0.65, 1 },
                cols = 1,
                examples = {
                    { "tankOpen >= 1", CludesUI.L("room for a tank") },
                    { "healerOpen > 0 and dpsOpen > 0", CludesUI.L("room for a healer and a dps") },
                    { "dpsOpen == 3", CludesUI.L("still needs all three dps") },
                },
                tags = {
                    { "tankOpen", CludesUI.L("Tank spots still open.") },
                    { "healerOpen", CludesUI.L("Healer spots still open.") },
                    { "dpsOpen", CludesUI.L("DPS spots still open.") },
                },
            },
            {
                title = CludesUI.L("Roles"),
                color = { 0.3, 0.85, 0.5 },
                cols = 2,
                examples = {
                    { "tank == 1 and healer == 1", CludesUI.L("has its tank and healer") },
                    { "members <= 3", CludesUI.L("three players or fewer so far") },
                    { "myClass == 0", CludesUI.L("nobody of your class yet") },
                    { "mage >= 1 or priest >= 1", CludesUI.L("has a mage or a priest") },
                    { "dk + dh == 0", CludesUI.L("no death knight or demon hunter") },
                },
                tags = {
                    { "tank", CludesUI.L("Tanks in the group.") },
                    { "healer", CludesUI.L("Healers in the group.") },
                    { "dps", CludesUI.L("DPS in the group.") },
                    {
                        "mage",
                        CludesUI.L("Any class name counts that class: mage, druid, priest, dk, dh..."),
                    },
                    { "members", CludesUI.L("Players in the group."), span = true },
                    { "myClass", CludesUI.L("Members of your own class."), span = true },
                },
            },
            {
                title = CludesUI.L("Group"),
                color = { 0.72, 0.52, 1 },
                cols = 2,
                examples = {
                    { "hasBL and hasBR", CludesUI.L("has bloodlust and a battle res") },
                    { "score >= 2500", CludesUI.L("leader has 2500 score or more") },
                    { "age <= 5", CludesUI.L("listed in the last five minutes") },
                    { "friends > 0", CludesUI.L("a friend or guildmate is in it") },
                    { "not voice", CludesUI.L("no voice chat listed") },
                },
                tags = {
                    { "hasBL", CludesUI.L("1 when someone can Bloodlust / Heroism.") },
                    { "hasBR", CludesUI.L("1 when someone can battle res.") },
                    { "score", CludesUI.L("The leader's Mythic+ score.") },
                    { "ilvl", CludesUI.L("The group's required item level.") },
                    { "age", CludesUI.L("Minutes since the group was listed.") },
                    { "friends", CludesUI.L("Your friends and guildmates in the group.") },
                    { "voice", CludesUI.L("1 when the group lists voice chat.") },
                },
            },
        },
    },
    {
        title = CludesUI.L("Syntax"),
        boxes = {
            {
                title = CludesUI.L("Math"),
                color = { 1, 0.55, 0.2 },
                examples = {
                    { "tank + healer == 2", CludesUI.L("has both a tank and a healer") },
                    { "5 - members >= 2", CludesUI.L("at least two spots left") },
                    { "mage + priest + druid >= 2", CludesUI.L("two or more of those classes") },
                    { "(tank + healer) == 0", CludesUI.L("no tank or healer yet") },
                },
                tags = {
                    { "+", CludesUI.L("Add.") },
                    { "-", CludesUI.L("Subtract.") },
                    { "*", CludesUI.L("Multiply.") },
                    { "/", CludesUI.L("Divide.") },
                    { "(", CludesUI.L("Group a part together.") },
                    { ")", CludesUI.L("Close the group.") },
                },
            },
            {
                title = CludesUI.L("Comparisons"),
                color = { 1, 0.8, 0.2 },
                examples = {
                    { "score > 2000", CludesUI.L("more than 2000") },
                    { "healer != 0", CludesUI.L("any healer at all") },
                    { "dps >= 1 and dps <= 2", CludesUI.L("one or two dps") },
                    { "hasBL or hasBR", CludesUI.L("either one is enough") },
                    { "not hasBL", CludesUI.L("no bloodlust") },
                },
                tags = {
                    { ">", CludesUI.L("More than.") },
                    { "<", CludesUI.L("Less than.") },
                    { ">=", CludesUI.L("At least.") },
                    { "<=", CludesUI.L("At most.") },
                    { "==", CludesUI.L("Exactly.") },
                    { "!=", CludesUI.L("Anything but.") },
                    { "and", CludesUI.L("Both sides must be true.") },
                    { "or", CludesUI.L("Either side is enough.") },
                    { "not", CludesUI.L("Flips true and false.") },
                },
            },
        },
    },
}
-- color words like their tags, unknown ones red
local HUE = {}
do
    local byKey = {}
    for _, sec in ipairs(SECTIONS) do
        for _, bx in ipairs(sec.boxes) do
            for _, tg in ipairs(bx.tags) do
                local wid = tg[1]:lower()
                HUE[wid] = bx.color
                if WORDS[wid] then
                    byKey[WORDS[wid]] = bx.color
                end
            end
        end
    end
    for wid, key in pairs(WORDS) do
        HUE[wid] = HUE[wid] or byKey[key]
    end
    local cmp = HUE[">"]
    for _, op in ipairs({ "=", "~=", "&&", "||", "!" }) do
        HUE[op] = cmp
    end
end
local function Hex(cfg)
    return string.format("|cff%02x%02x%02x", cfg[1] * 255, cfg[2] * 255, cfg[3] * 255)
end
local BAD_HEX = CludesUI.COLOR_CODES.BAD

local function Colorize(textValue)
    local result, index, n = {}, 1, #textValue
    while index <= n do
        local c = textValue:sub(index, index)
        local word = textValue:match("^[%a_][%w_]*", index)
        local num = not word and (textValue:match("^%d+%.?%d*", index) or textValue:match("^%.%d+", index))
        local two = textValue:sub(index, index + 1)
        local piece, hue
        if word then
            piece = word
            local lw = word:lower()
            hue = HUE[lw]
            if not hue and lw ~= "true" and lw ~= "false" then
                hue = "bad"
            end
        elseif num then
            piece = num
        elseif HUE[two] then
            piece, hue = two, HUE[two]
        elseif c:match("%s") then
            piece = c
        else
            piece, hue = c, HUE[c] or "bad"
        end
        local isShown = piece:gsub("|", "||")
        if hue == "bad" then
            result[#result + 1] = BAD_HEX .. isShown .. "|r"
        elseif hue then
            result[#result + 1] = Hex(hue) .. isShown .. "|r"
        else
            result[#result + 1] = isShown
        end
        index = index + #piece
    end
    return table.concat(result)
end

local TAG_H, TAG_PAD, TAG_GAP, BOX_PAD, BOX_GAP = 16, 6, 4, 6, 6
local VPAD, ROW_GAP = 6, 8 -- group padding, gap between untitled rows

-- a tag: small tinted box
local function Tag(hostFrame, K, specInfo, color, onClick)
    local t = CreateFrame("Button", nil, hostFrame)
    t:SetHeight(TAG_H)
    local red, green, blue = color[1], color[2], color[3]
    t.fill = t:CreateTexture(nil, "BACKGROUND")
    t.fill:SetAllPoints()
    t.fill:SetColorTexture(red, green, blue, 0.14)
    CM.MakeBorder(t, red, green, blue, 0.45, CM.PanelPP)
    t.text = t:CreateFontString(nil, "OVERLAY")
    K.Font(t.text, 9)
    t.text:SetPoint("CENTER", 0, 0)
    t.text:SetText(specInfo[1])
    t.text:SetTextColor(red, green, blue, 1)
    t.minW = math.ceil(t.text:GetStringWidth()) + TAG_PAD * 2
    t:SetWidth(t.minW)
    t:SetScript("OnEnter", function(self)
        self.fill:SetColorTexture(red, green, blue, 0.3)
        K.Tip(self, specInfo[1], specInfo[2])
    end)
    t:SetScript("OnLeave", function(self)
        self.fill:SetColorTexture(red, green, blue, 0.14)
        K.Untip()
    end)
    t:SetScript("OnClick", function()
        onClick(specInfo[1])
    end)
    t.span = specInfo.span
    return t
end

-- builds the sections once, layout(width) places them
local function BuildHelp(panelFrame, K, onClick)
    local help = { sections = {} }
    for _, sec in ipairs(SECTIONS) do
        local S = { boxes = {} }
        if sec.title then
            S.title = panelFrame:CreateFontString(nil, "OVERLAY")
            K.Font(S.title, 9)
            S.title:SetTextColor(0.55, 0.55, 0.55, 1)
            S.title:SetText(sec.title)
        end
        for _, specInfo in ipairs(sec.boxes) do
            local bx = CreateFrame("Frame", nil, panelFrame)
            local shade = bx:CreateTexture(nil, "BACKGROUND")
            shade:SetAllPoints()
            shade:SetColorTexture(0, 0, 0, 0.22)
            if specInfo.title then
                bx.title = bx:CreateFontString(nil, "OVERLAY")
                K.Font(bx.title, 8)
                bx.title:SetPoint("TOPLEFT", bx, "TOPLEFT", BOX_PAD, -VPAD)
                bx.title:SetTextColor(specInfo.color[1], specInfo.color[2], specInfo.color[3], 0.8)
                bx.title:SetText(specInfo.title:upper())
                if specInfo.examples then
                    -- "?" next to the name: hover for examples
                    local q = CreateFrame("Frame", nil, bx)
                    q:SetSize(12, 12)
                    q:SetPoint("LEFT", bx.title, "RIGHT", 3, 0)
                    q:EnableMouse(true)
                    local qt = q:CreateFontString(nil, "OVERLAY")
                    K.Font(qt, 9)
                    qt:SetPoint("CENTER", 0, 0)
                    qt:SetText("?")
                    qt:SetTextColor(0.6, 0.6, 0.6, 1)
                    q:SetScript("OnEnter", function(self)
                        qt:SetTextColor(1, 1, 1, 1)
                        local lines = {}
                        for _, ex in ipairs(specInfo.examples) do
                            -- starts with a color code so the tooltip keeps our colors
                            lines[#lines + 1] = "|cffffffff|r"
                                .. Colorize(ex[1])
                                .. "   "
                                .. CludesUI.COLOR_CODES.DIM
                                .. ex[2]
                                .. "|r"
                        end
                        K.Tip(self, CludesUI.Lf("%1$s Examples", specInfo.title), unpack(lines))
                    end)
                    q:SetScript("OnLeave", function()
                        qt:SetTextColor(0.6, 0.6, 0.6, 1)
                        K.Untip()
                    end)
                end
            end
            bx.cols = specInfo.cols
            bx.tags = {}
            for _, tg in ipairs(specInfo.tags) do
                bx.tags[#bx.tags + 1] = Tag(bx, K, tg, specInfo.color, onClick)
            end
            if specInfo.text then
                bx.plain = bx:CreateFontString(nil, "OVERLAY")
                K.Font(bx.plain, 9)
                bx.plain:SetJustifyH("LEFT")
                bx.plain:SetTextColor(specInfo.color[1], specInfo.color[2], specInfo.color[3], 1)
                bx.plain:SetText(specInfo.text)
            end
            S.boxes[#S.boxes + 1] = bx
        end
        help.sections[#help.sections + 1] = S
    end

    -- tags wrap left to right, returns the height
    local function FlowBox(bx, wid)
        local topY = bx.title and (VPAD + 10 + 4) or VPAD
        if bx.plain then
            bx.plain:ClearAllPoints()
            bx.plain:SetPoint("TOPLEFT", bx, "TOPLEFT", BOX_PAD + 2, -topY - 2)
            bx.plain:SetWidth(wid - BOX_PAD * 2 - 2)
            return topY + 2 + math.max(12, math.ceil(bx.plain:GetStringHeight())) + VPAD
        end
        if bx.cols then
            local cw = math.floor((wid - BOX_PAD * 2 - (bx.cols - 1) * TAG_GAP) / bx.cols)
            local colour, row = 0, 0
            for _, tag in ipairs(bx.tags) do
                local span = tag.span and bx.cols or 1
                if colour > 0 and colour + span > bx.cols then
                    colour, row = 0, row + 1
                end
                tag:SetWidth(cw * span + TAG_GAP * (span - 1))
                tag:ClearAllPoints()
                tag:SetPoint(
                    "TOPLEFT",
                    bx,
                    "TOPLEFT",
                    BOX_PAD + colour * (cw + TAG_GAP),
                    -(topY + row * (TAG_H + TAG_GAP))
                )
                colour = colour + span
                if colour >= bx.cols then
                    colour, row = 0, row + 1
                end
            end
            if colour == 0 then
                row = row - 1
            end
            return topY + (row + 1) * (TAG_H + TAG_GAP) - TAG_GAP + VPAD
        end
        local posX, posY = BOX_PAD, topY
        for _, tag in ipairs(bx.tags) do
            local tw = tag:GetWidth()
            if posX > BOX_PAD and posX + tw > wid - BOX_PAD then
                posX, posY = BOX_PAD, posY + TAG_H + TAG_GAP
            end
            tag:ClearAllPoints()
            tag:SetPoint("TOPLEFT", bx, "TOPLEFT", posX, -posY)
            posX = posX + tw + TAG_GAP
        end
        return posY + TAG_H + VPAD
    end

    -- the last row grows into the leftover height
    function help.Layout(anchor, width, fillTex)
        local posY = 0
        for si, S in ipairs(help.sections) do
            if S.title then
                S.title:ClearAllPoints()
                S.title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -posY - 8)
                posY = posY + 8 + 14
            else
                posY = posY + ROW_GAP
            end
            local n = #S.boxes
            local bw = math.floor((width - (n - 1) * BOX_GAP) / n)
            local rowH = 0
            for index, bx in ipairs(S.boxes) do
                bx:SetWidth(bw)
                rowH = math.max(rowH, FlowBox(bx, bw))
                bx:ClearAllPoints()
                bx:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", (index - 1) * (bw + BOX_GAP), -posY)
            end
            if si == #help.sections and fillTex and fillTex > posY + rowH then
                rowH = fillTex - posY
            end
            for _, bx in ipairs(S.boxes) do
                bx:SetHeight(rowH)
            end
            posY = posY + rowH
        end
        return posY
    end
    return help
end

local button, panelFrame, box, status, hint, isShown
local function Paint(K)
    if not button then
        return
    end
    local frame, err = Current()
    if frame then
        button.Glyph:SetVertexColor(K.Accent())
    else
        button.Glyph:SetVertexColor(K.GLYPH, K.GLYPH, K.GLYPH)
    end
    button.activeEdge:SetShown(frame ~= nil)
    if isShown and box then
        isShown:SetText(Colorize(box:GetText()))
    end
    if not status then
        return
    end
    local textValue = box and box:GetText() or ""
    if hint then
        hint:SetShown(textValue == "")
    end
    if not textValue:find("%S") then
        status:SetText("")
    elseif frame then
        status:SetText("|cff66dd66" .. CludesUI.L("Filtering with this expression.") .. "|r")
    else
        status:SetText(BAD_HEX .. (err or CludesUI.L("can't read that")) .. "|r")
    end
end

local function Build(SP, K)
    button = K.GlyphButton(SP, K.ROW1_H, EXPR_TEX)
    button.Glyph:SetSize(14, 14)
    -- green edge while an expression is filtering
    button.activeEdge = CreateFrame("Frame", nil, button)
    button.activeEdge:SetAllPoints()
    button.activeEdge:SetFrameLevel(button:GetFrameLevel() + 3)
    button.activeEdge:EnableMouse(false)
    CM.MakeBorder(button.activeEdge, 0.3, 0.85, 0.4, 1, CM.PanelPP)
    button.activeEdge:Hide()
    button:SetFrameLevel(SP:GetFrameLevel() + 5)

    panelFrame = CreateFrame("Frame", nil, SP)
    panelFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    panelFrame:SetFrameLevel(300)
    panelFrame:EnableMouse(true)
    panelFrame:SetClampedToScreen(true)
    local backdrop = panelFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local fr, fg, fb = K.ThemeFill()
    backdrop:SetColorTexture(fr, fg, fb, 0.98)
    CM.MakeBorder(panelFrame, K.ThemeBorder())

    local title = panelFrame:CreateFontString(nil, "OVERLAY")
    K.Font(title, 9)
    title:SetTextColor(0.55, 0.55, 0.55, 1)
    title:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 9, -7)
    title:SetText(CludesUI.L("Expressions"))

    -- clear button, skinned
    local clear = CreateFrame("Button", nil, panelFrame)
    clear:SetSize(46, 16)
    clear:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -8, -4)
    clear:SetNormalFontObject("GameFontHighlight")
    clear:SetText(" ")
    clear.Label = clear:CreateFontString(nil, "OVERLAY")
    K.Font(clear.Label, 9)
    clear.Label:SetPoint("CENTER", 0, 0)
    clear.Label:SetText(CludesUI.L("Clear"))
    local ct = clear.Label
    ct:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    local skin = CM._ModuleNS and CM._ModuleNS.CludesUIBlizzardSkin
    local S = skin and skin.WSkin
    if S and S.Button then
        S.Button(clear, { "Label" })
    else
        local cbg = clear:CreateTexture(nil, "BACKGROUND")
        cbg:SetAllPoints()
        cbg:SetColorTexture(0.06, 0.06, 0.06, 0.95)
        CM.MakeBorder(clear, K.ThemeBorder())
        local chl = clear:CreateTexture(nil, "HIGHLIGHT")
        chl:SetAllPoints()
        chl:SetColorTexture(1, 1, 1, 0.1)
    end
    clear:HookScript("OnEnter", function()
        ct:SetTextColor(1, 1, 1, 1)
    end)
    clear:HookScript("OnLeave", function()
        ct:SetTextColor(CM.TEXT_DIM_R, CM.TEXT_DIM_G, CM.TEXT_DIM_B, CM.TEXT_DIM_A)
    end)

    -- the typing box
    local well = CreateFrame("Frame", nil, panelFrame)
    well:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", 8, -22)
    well:SetPoint("TOPRIGHT", panelFrame, "TOPRIGHT", -8, -22)
    well:SetHeight(58)
    local wbg = well:CreateTexture(nil, "BACKGROUND")
    wbg:SetAllPoints()
    wbg:SetColorTexture(0.02, 0.02, 0.02, 1)
    CM.MakeBorder(well, K.ThemeBorder())
    box = CreateFrame("EditBox", nil, well)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetMaxLetters(500)
    box:SetPoint("TOPLEFT", well, "TOPLEFT", 6, -5)
    box:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -6, 5)
    box:SetFontObject("ChatFontNormal")
    K.Font(box, 10)
    box:SetTextColor(1, 1, 1, 0)
    -- colored copy on a layer above, so the selection sits under it
    local ink = CreateFrame("Frame", nil, box)
    ink:SetAllPoints(box)
    ink:SetFrameLevel(box:GetFrameLevel() + 2)
    ink:EnableMouse(false)
    isShown = ink:CreateFontString(nil, "ARTWORK")
    K.Font(isShown, 10)
    isShown:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    isShown:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    isShown:SetJustifyH("LEFT")
    isShown:SetJustifyV("TOP")
    isShown:SetWordWrap(true)
    -- placeholder example
    hint = well:CreateFontString(nil, "OVERLAY")
    K.Font(hint, 10)
    hint:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    hint:SetTextColor(0.45, 0.45, 0.45, 1)
    hint:SetText(CludesUI.L("e.g. hasBL and hasBR and healer > 0"))
    well:EnableMouse(true)
    well:SetScript("OnMouseDown", function()
        box:SetFocus()
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    -- our own cursor, blinks while you type
    local caret = ink:CreateTexture(nil, "OVERLAY")
    caret:SetColorTexture(1, 1, 1, 0.9)
    caret:SetSize(1, 12)
    caret:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
    caret:Hide()
    local blink = 0
    local function Blink(_, elapsed)
        blink = blink + elapsed
        if blink >= 0.5 then
            blink = 0
            caret:SetShown(not caret:IsShown())
        end
    end
    box:SetScript("OnCursorChanged", function(self, posX, posY, wid, hgt)
        caret:ClearAllPoints()
        caret:SetPoint("TOPLEFT", self, "TOPLEFT", posX, posY)
        caret:SetSize(1, (hgt and hgt > 0) and hgt or 12)
        blink = 0
        caret:SetShown(self:HasFocus())
    end)
    box:SetScript("OnEditFocusGained", function(self)
        blink = 0
        caret:Show()
        self:SetScript("OnUpdate", Blink)
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:SetScript("OnUpdate", nil)
        caret:Hide()
    end)
    box:SetScript("OnTextChanged", function(self, user)
        if not user then
            return
        end
        local c = GFNS.Cfg()
        local textValue = self:GetText()
        c.extraExpr = textValue:find("%S") and textValue or nil
        Paint(K)
        K.Refilter()
    end)
    clear:SetScript("OnClick", function()
        box:SetText("")
        GFNS.Cfg().extraExpr = nil
        Paint(K)
        K.Refilter()
    end)

    status = panelFrame:CreateFontString(nil, "OVERLAY")
    K.Font(status, 9)
    status:SetPoint("LEFT", title, "RIGHT", 10, 0)
    status:SetPoint("RIGHT", clear, "LEFT", -8, 0)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)

    -- click a tag: typed in at the cursor
    local function Insert(word)
        local textValue, place = box:GetText(), box:GetCursorPosition()
        if not box:HasFocus() then
            place = #textValue
        end
        local before, after = textValue:sub(1, place), textValue:sub(place + 1)
        if before ~= "" and not before:find("%s$") then
            word = " " .. word
        end
        if after ~= "" and not after:find("^%s") then
            word = word .. " "
        end
        box:SetText(before .. word .. after)
        box:SetFocus()
        box:SetCursorPosition(place + #word)
        local c = GFNS.Cfg()
        c.extraExpr = box:GetText()
        Paint(K)
        K.Refilter()
    end
    local help = BuildHelp(panelFrame, K, Insert)
    local TOP, BOTTOM = 22 + 58, 10
    local function LayoutPanel()
        local wid = panelFrame:GetWidth()
        if not wid or wid < 50 then
            return
        end
        panelFrame:SetHeight(TOP + help.Layout(well, wid - 16) + BOTTOM)
    end
    panelFrame:SetHeight(TOP + BOTTOM)
    panelFrame:SetScript("OnSizeChanged", function(_, wid)
        if wid and wid > 50 then
            LayoutPanel()
        end
    end)

    K.ClickOff(panelFrame, function(self)
        return self:IsMouseOver() or button:IsMouseOver()
    end)
    panelFrame:HookScript("OnShow", function()
        if K.Dim then
            K.Dim(true)
        end
        LayoutPanel()
        box:SetText(GFNS.Cfg().extraExpr or "")
        Paint(K)
        box:SetFocus()
        box:SetCursorPosition(#box:GetText())
    end)
    panelFrame:HookScript("OnHide", function()
        box:ClearFocus()
        if K.Dim then
            K.Dim(false)
        end
    end)
    panelFrame:Hide()

    button:SetScript("OnClick", function()
        if panelFrame:IsShown() then
            panelFrame:Hide()
            return
        end
        panelFrame:ClearAllPoints()
        local leftX = SP.SearchBox or button
        panelFrame:SetPoint("TOPLEFT", leftX, "BOTTOMLEFT", 0, -K.GAP)
        panelFrame:SetPoint("TOPRIGHT", button.refresh, "BOTTOMRIGHT", 0, -K.GAP)
        panelFrame:Show()
    end)
    button:SetScript("OnEnter", function(self)
        self.Glyph:SetAlpha(1)
        local frame = Current()
        K.Tip(
            self,
            CludesUI.L("Expressions"),
            frame and CludesUI.Lf("Active: %1$s", GFNS.Cfg().extraExpr)
                or CludesUI.L("Filter groups with your own rules")
        )
    end)
    button:SetScript("OnLeave", function(self)
        self.Glyph:SetAlpha(0.8)
        K.Untip()
    end)
    button:SetScript("OnHide", function()
        panelFrame:Hide()
    end)
    GFNS.ExtraExprReset = function()
        local c = GFNS.Cfg()
        c.extraExpr = nil
        if box then
            box:SetText("")
        end
        Paint(K)
    end
end

-------------------------------------------------------------------------------
--  one menu at a time: whatever the open menu blocks dims and eats clicks
-------------------------------------------------------------------------------
local lastK, lastSP
local blockers = {}

local function Block(target, enabled)
    if not target then
        return
    end
    local widget = blockers[target]
    if not widget then
        if not enabled then
            return
        end
        widget = CreateFrame("Button", nil, target:GetParent() or UIParent)
        widget:SetAllPoints(target)
        widget:EnableMouse(true)
        widget:RegisterForClicks("AnyUp")
        blockers[target] = widget
    end
    if enabled then
        widget:SetFrameStrata(target:GetFrameStrata())
        widget:SetFrameLevel(target:GetFrameLevel() + 20)
        widget:Show()
        target:SetAlpha(lastK and lastK.DIM_ALPHA or 0.35)
    else
        widget:Hide()
        target:SetAlpha(1)
    end
end

GFNS.ExtraOnDim = function(enabled)
    local K, SP = lastK, lastSP
    if not (K and SP) then
        return
    end
    local exprOpen = enabled and panelFrame and panelFrame:IsShown()
    local filtersOpen = enabled and not exprOpen and K.FiltersOpen and K.FiltersOpen()
    Block(button and button:IsShown() and button or nil, filtersOpen)
    Block(K.Filters, exprOpen)
    Block(button and button.refresh, exprOpen or filtersOpen)
    Block(SP.SearchBox, exprOpen or filtersOpen)
    local face = GFNS.GFFilterFace and GFNS.GFFilterFace() or SP.FilterButton
    Block(face, filtersOpen)
    if filtersOpen and face then
        face:SetAlpha(K.DIM_ALPHA or 0.35)
    end
end

GFNS.ExtraExprButton = function(SP, refresh, show, K)
    lastK, lastSP = K, SP
    if not button then
        Build(SP, K)
    end
    button.refresh = refresh
    button:ClearAllPoints()
    button:SetPoint("RIGHT", refresh, "LEFT", -K.GAP, 0)
    button:SetShown(show)
    Paint(K)
    return show and button or refresh
end

-- reset with no box built yet
GFNS.ExtraExprReset = function()
    local cfg = GFNS.Cfg and GFNS.Cfg()
    if cfg then
        cfg.extraExpr = nil
    end
end
