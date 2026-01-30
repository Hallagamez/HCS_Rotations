--[[
    M+ Season 3 (TWW) Tank Buster / "Press a cooldown" List
    Dungeon pool: Ara-Kara, Eco-Dome Al'dani, Halls of Atonement, Operation: Floodgate,
    Priory of the Sacred Flame, Tazavesh (Gambit + Streets), The Dawnbreaker.

    Usage:
      local tb = require("libraries/mplus_s3_tank_buster_list")
      if tb.is_casting_tank_buster(target) then
          -- use defensive
      end
]]

local M = {}

local TANK_BUSTER_IDS = {
    [438471] = true, [433002] = true, [1241785] = true, [1241779] = true, [1219482] = true,
    [1235368] = true, [1222341] = true, [1215850] = true, [1237071] = true, [1235766] = true,
    [13737] = true, [322936] = true, [328791] = true, [426883] = true, [466188] = true,
    [424414] = true, [435165] = true, [448485] = true, [346116] = true, [355048] = true,
    [355429] = true, [352796] = true, [354474] = true, [355477] = true, [349934] = true,
    [347716] = true, [1240912] = true, [427001] = true, [431491] = true, [453212] = true,
    [428086] = true,
}

local PHYSICAL_BUSTER_IDS = {
    [426883] = true, [466188] = true, [424414] = true, [438471] = true, [13737] = true,
    [1219482] = true,
}

local MAGIC_BUSTER_IDS = {
    [428086] = true, [453212] = true, [1235368] = true, [1222341] = true, [435165] = true,
    [1241785] = true,
}

M.TANK_BUSTER_SPELL_IDS = TANK_BUSTER_IDS
M.PHYSICAL_BUSTER_IDS = PHYSICAL_BUSTER_IDS
M.MAGIC_BUSTER_IDS = MAGIC_BUSTER_IDS

function M.is_tank_buster_cast(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return TANK_BUSTER_IDS[spell_id] == true
end

function M.is_casting_tank_buster(unit)
    if not unit or not unit.get_active_cast_or_channel_id then return false end
    local cast_id = unit:get_active_cast_or_channel_id()
    return M.is_tank_buster_cast(cast_id)
end

function M.is_physical_tank_buster(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return PHYSICAL_BUSTER_IDS[spell_id] == true
end

function M.is_magic_tank_buster(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return MAGIC_BUSTER_IDS[spell_id] == true
end

function M.get_tank_buster_cast_id(unit)
    if not unit or not unit.get_active_cast_or_channel_id then return nil end
    local cast_id = unit:get_active_cast_or_channel_id()
    if M.is_tank_buster_cast(cast_id) then return cast_id end
    return nil
end

return M
