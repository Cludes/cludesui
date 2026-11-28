-- encoding_util.lua: a stand-in for the client's C_EncodingUtil (DecodeBase64,
-- DecompressString with raw Deflate, DeserializeCBOR) in plain LuaJIT, so a
-- scenario can run code on the real packed data (Journeys' walking maps,
-- Creature Scout, Glimmer). Slow but exact. Load it with
--   C_EncodingUtil = dofile("tools/headless/encoding_util.lua")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local byte, char, concat = string.byte, string.char, table.concat

local B64 = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for i = 1, 64 do B64[byte(alphabet, i)] = i - 1 end

local function DecodeBase64(s)
    local out, n = {}, 0
    local acc, bits = 0, 0
    for i = 1, #s do
        local v = B64[byte(s, i)]
        if v then
            acc = bor(lshift(acc, 6), v)
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                n = n + 1
                out[n] = char(band(rshift(acc, bits), 255))
                acc = band(acc, lshift(1, bits) - 1)
            end
        end
    end
    return concat(out)
end

-- Raw Deflate (RFC 1951).
local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function Inflate(data)
    local pos, bitbuf, bitcnt = 1, 0, 0
    local out, n = {}, 0
    local function Bits(k)
        while bitcnt < k do
            bitbuf = bitbuf + lshift(byte(data, pos) or 0, bitcnt)
            pos, bitcnt = pos + 1, bitcnt + 8
        end
        local v = band(bitbuf, lshift(1, k) - 1)
        bitbuf, bitcnt = rshift(bitbuf, k), bitcnt - k
        return v
    end
    -- A code table: counts per length and symbols in code order.
    local function Table(lengths, count)
        local counts, offs, symbols = {}, {}, {}
        for l = 0, 15 do counts[l] = 0 end
        for i = 0, count - 1 do counts[lengths[i] or 0] = counts[lengths[i] or 0] + 1 end
        counts[0] = 0
        offs[1] = 0
        for l = 1, 14 do offs[l + 1] = offs[l] + counts[l] end
        for i = 0, count - 1 do
            local l = lengths[i] or 0
            if l ~= 0 then
                symbols[offs[l]] = i
                offs[l] = offs[l] + 1
            end
        end
        return { counts = counts, symbols = symbols }
    end
    local function Decode(t)
        local code, first, index = 0, 0, 0
        for l = 1, 15 do
            code = bor(code, Bits(1))
            local count = t.counts[l]
            if code - count < first then return t.symbols[index + (code - first)] end
            index = index + count
            first = lshift(first + count, 1)
            code = lshift(code, 1)
        end
        error("bad code")
    end
    local fixedLit, fixedDist
    repeat
        local final = Bits(1)
        local kind = Bits(2)
        if kind == 0 then
            bitbuf, bitcnt = 0, 0
            local len = byte(data, pos) + byte(data, pos + 1) * 256
            pos = pos + 4
            for i = 0, len - 1 do
                n = n + 1
                out[n] = byte(data, pos + i)
            end
            pos = pos + len
        else
            local lit, dist
            if kind == 1 then
                if not fixedLit then
                    local l = {}
                    for i = 0, 143 do l[i] = 8 end
                    for i = 144, 255 do l[i] = 9 end
                    for i = 256, 279 do l[i] = 7 end
                    for i = 280, 287 do l[i] = 8 end
                    fixedLit = Table(l, 288)
                    local d = {}
                    for i = 0, 29 do d[i] = 5 end
                    fixedDist = Table(d, 30)
                end
                lit, dist = fixedLit, fixedDist
            else
                local hlit, hdist, hclen = Bits(5) + 257, Bits(5) + 1, Bits(4) + 4
                local cl = {}
                for i = 1, hclen do cl[ORDER[i]] = Bits(3) end
                local clt = Table(cl, 19)
                local lengths, i = {}, 0
                while i < hlit + hdist do
                    local sym = Decode(clt)
                    if sym < 16 then
                        lengths[i], i = sym, i + 1
                    else
                        local rep, val = 0, 0
                        if sym == 16 then
                            rep, val = 3 + Bits(2), lengths[i - 1]
                        elseif sym == 17 then
                            rep = 3 + Bits(3)
                        else
                            rep = 11 + Bits(7)
                        end
                        for _ = 1, rep do
                            lengths[i], i = val, i + 1
                        end
                    end
                end
                local ll, dl = {}, {}
                for k = 0, hlit - 1 do ll[k] = lengths[k] end
                for k = 0, hdist - 1 do dl[k] = lengths[hlit + k] end
                lit, dist = Table(ll, hlit), Table(dl, hdist)
            end
            while true do
                local sym = Decode(lit)
                if sym < 256 then
                    n = n + 1
                    out[n] = sym
                elseif sym == 256 then
                    break
                else
                    sym = sym - 257
                    local len = LEN_BASE[sym + 1] + Bits(LEN_EXTRA[sym + 1])
                    local d = Decode(dist)
                    local back = DIST_BASE[d + 1] + Bits(DIST_EXTRA[d + 1])
                    for _ = 1, len do
                        n = n + 1
                        out[n] = out[n - back]
                    end
                end
            end
        end
    until final == 1
    local parts = {}
    for i = 1, n, 4096 do
        parts[#parts + 1] = char(unpack(out, i, math.min(n, i + 4095)))
    end
    return concat(parts)
end

-- CBOR (RFC 8949): the types the packers write.
local function Cbor(s)
    local pos = 1
    local function Item()
        local ib = byte(s, pos)
        pos = pos + 1
        local major, info = rshift(ib, 5), band(ib, 31)
        local v
        if info < 24 then
            v = info
        elseif info == 24 then
            v = byte(s, pos); pos = pos + 1
        elseif info == 25 then
            v = byte(s, pos) * 256 + byte(s, pos + 1); pos = pos + 2
        elseif info == 26 then
            v = ((byte(s, pos) * 256 + byte(s, pos + 1)) * 256 + byte(s, pos + 2)) * 256 + byte(s, pos + 3); pos = pos + 4
        elseif info == 27 then
            v = 0
            for k = 0, 7 do v = v * 256 + byte(s, pos + k) end
            pos = pos + 8
        end
        if major == 0 then return v end
        if major == 1 then return -1 - v end
        if major == 2 or major == 3 then
            local str = s:sub(pos, pos + v - 1)
            pos = pos + v
            return str
        end
        if major == 4 then
            local t = {}
            for i = 1, v do t[i] = Item() end
            return t
        end
        if major == 5 then
            local t = {}
            for _ = 1, v do
                local k = Item()
                t[k] = Item()
            end
            return t
        end
        if major == 7 then
            if info == 20 then return false end
            if info == 21 then return true end
            if info == 22 or info == 23 then return nil end
            if info == 25 then
                local h = v
                local sign = band(h, 0x8000) ~= 0 and -1 or 1
                local e, m = band(rshift(h, 10), 31), band(h, 1023)
                if e == 0 then return sign * m * 2 ^ -24 end
                if e == 31 then return sign * math.huge end
                return sign * (1 + m / 1024) * 2 ^ (e - 15)
            end
            if info == 26 then
                local sign = v >= 2 ^ 31 and -1 or 1
                local e, m = math.floor(v / 2 ^ 23) % 256, v % 2 ^ 23
                if e == 0 then return sign * m * 2 ^ -149 end
                return sign * (1 + m / 2 ^ 23) * 2 ^ (e - 127)
            end
            if info == 27 then
                local b = { byte(s, pos - 8, pos - 1) }
                local sign = b[1] >= 128 and -1 or 1
                local e = (b[1] % 128) * 16 + math.floor(b[2] / 16)
                local m = b[2] % 16
                for k = 3, 8 do m = m * 256 + b[k] end
                if e == 0 then return sign * m * 2 ^ -1074 end
                return sign * (1 + m / 2 ^ 52) * 2 ^ (e - 1023)
            end
        end
        error("cbor major " .. major)
    end
    return Item()
end

return {
    DecodeBase64 = DecodeBase64,
    DecompressString = function(s) return Inflate(s) end,
    DeserializeCBOR = Cbor,
}
