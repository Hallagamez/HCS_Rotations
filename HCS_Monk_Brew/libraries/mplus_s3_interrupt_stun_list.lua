--[[
    M+ Season 3 (TWW) Interrupt & Stun List
    Dungeon pool: Eco-Dome Al'dani, Halls of Atonement, Ara-Kara, The Dawnbreaker,
    Priory of the Sacred Flame, Operation: Floodgate, Tazavesh (Streets), Tazavesh (Gambit).

    Usage:
      local mplus = require("libraries/mplus_s3_interrupt_stun_list")
      local cast_id = enemy:get_active_cast_or_channel_id()
      if cast_id and cast_id ~= 0 and mplus.MUST_KICK_SPELL_IDS[cast_id] and enemy:is_active_spell_interruptable() then
          -- interrupt this cast
      end
      if cast_id and cast_id ~= 0 and mplus.MUST_STOP_SPELL_IDS[cast_id] then
          -- allow stun/CC to stop this cast
      end
]]

local M = {}

-- Priority Kick/Stops (S3): interrupt these, or stun/CC when kick is down.
local KICK_LIST = {
    -- Operation: Floodgate (S3)
    1214468, 462771, 465682, 465128, 468631, 1216039, 465595, 1214780, 471733,
    -- Halls of Atonement (S3)
    326450, 338003, 325701,
    -- Priory of the Sacred Flame (S3)
    427356, 427484, 424419,
    -- Eco-Dome Al'dani (S3)
    1229474, 1229510, 1222815,
    -- Ara-Kara: City of Echoes (S3)
    434793, 434802, 448248, 432967,
    -- Tazavesh: Streets of Wonder (S3)
    355934, 354297, 356324,
}

local STOP_LIST = {}

local MUST_KICK = {}
for _, id in ipairs(KICK_LIST) do
    if id and id ~= 0 then MUST_KICK[id] = true end
end

local MUST_STOP = {}
for _, id in ipairs(KICK_LIST) do
    if id and id ~= 0 then MUST_STOP[id] = true end
end
for _, id in ipairs(STOP_LIST) do
    if id and id ~= 0 then MUST_STOP[id] = true end
end

M.MUST_KICK_SPELL_IDS = MUST_KICK
M.MUST_STOP_SPELL_IDS = MUST_STOP
M.KICK_LIST_RAW = KICK_LIST
M.STOP_LIST_RAW = STOP_LIST

function M.should_kick_cast(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return MUST_KICK[spell_id] == true
end

function M.should_stop_cast(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return MUST_STOP[spell_id] == true
end

function M.should_kick_unit(unit, use_allowlist)
    if not unit or not unit.get_active_cast_or_channel_id then return false end
    local cast_id = unit:get_active_cast_or_channel_id()
    if not cast_id or cast_id == 0 then return false end
    if not use_allowlist then return true end
    if next(MUST_KICK) == nil then return true end
    return M.should_kick_cast(cast_id)
end

function M.should_stop_unit(unit, use_allowlist)
    if not unit or not unit.get_active_cast_or_channel_id then return false end
    local cast_id = unit:get_active_cast_or_channel_id()
    if not cast_id or cast_id == 0 then return false end
    if not use_allowlist then return true end
    if next(MUST_STOP) == nil then return true end
    return M.should_stop_cast(cast_id)
end

return M
