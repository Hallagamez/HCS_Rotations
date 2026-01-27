--[[
    WoW class color escape strings for HCS menu headers.
    Use with tree_node:render():   menu.root:render(M.HCS_HEADER.PALADIN .. "HCS Protection Paladin|r", fn)
    Format is |cAARRGGBB (alpha FF); reset with |r.
    Values from WoW RAID_CLASS_COLORS / ChrClasses.db2.
]]
local M = {}

local function esc(hex_rrggbb)
    return "|cFF" .. (hex_rrggbb or "FFFFFF"):upper():gsub("^#", "")
end

-- WoW class hex (RRGGBB, no #)
M.PALADIN   = esc("F58CBA")
M.MONK      = esc("00FF98")
M.MAGE      = esc("3FC7EB")
M.WARRIOR   = esc("C79C6E")
M.HUNTER    = esc("ABD473")
M.ROGUE     = esc("FFF569")
M.PRIEST    = esc("FFFFFF")
M.DEATH_KNIGHT = esc("C41E3A")
M.SHAMAN    = esc("0070DE")
M.WARLOCK   = esc("8788EE")
M.DRUID     = esc("FF7D0A")
M.DEMON_HUNTER = esc("A330C9")
M.EVOKER    = esc("33937F")

--- Returns a header string with class color applied. Reset with |r at end.
--- @param class_key string One of: PALADIN, MONK, MAGE, WARRIOR, etc.
--- @param title string Plain title, e.g. "HCS Protection Paladin"
--- @return string "|cFFrrggbb" .. title .. "|r"
function M.hcs_header(class_key, title)
    local c = M[class_key]
    if not c or not title then return title or "" end
    return c .. title .. "|r"
end

return M
