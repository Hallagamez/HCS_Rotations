--[[
    M+ Season 3 (TWW) Interrupt & Stun List
    Dungeon pool: Eco-Dome Al'dani, Halls of Atonement, Ara-Kara, The Dawnbreaker,
    Priory of the Sacred Flame, Operation: Floodgate, Tazavesh (Streets), Tazavesh (Gambit).

    Usage:
      local mplus = require("shared/mplus_s3_interrupt_stun_list")
      local cast_id = enemy:get_active_cast_or_channel_id()
      if cast_id and cast_id ~= 0 and mplus.MUST_KICK_SPELL_IDS[cast_id] and enemy:is_active_spell_interruptable() then
          -- interrupt this cast
      end
      if cast_id and cast_id ~= 0 and mplus.MUST_STOP_SPELL_IDS[cast_id] then
          -- allow stun/CC to stop this cast
      end

    To get spell IDs: Wowhead NPC/ability page (spell=ID in URL), or in-game:
    /run local name,_,_,_,_,_,spellId = UnitCastingInfo("target"); print(spellId or UnitChannelInfo("target"))
]]

local M = {}

-- Priority Kick/Stops (S3): interrupt these, or stun/CC when kick is down.
-- All IDs below are in both MUST_KICK and MUST_STOP.
local KICK_LIST = {
    -- Operation: Floodgate (S3)
    1214468, -- Trickshot
    462771,  -- Surveying Beam
    465682,  -- Surprise Inspection
    465128,  -- Wind Up
    468631,  -- Harpoon
    1216039, -- R.P.G.G.
    465595,  -- Lightning Bolt
    1214780, -- Maximum Distortion
    471733,  -- Restorative Algae
    -- Halls of Atonement (S3)
    326450,  -- Loyal Beasts
    338003,  -- Wicked Bolt
    325701,  -- Siphon Life
    -- Priory of the Sacred Flame (S3)
    427356,  -- Greater Heal
    427484,  -- Flamestrike
    424419,  -- Battle Cry
    -- Eco-Dome Al'dani (S3)
    1229474, -- Gorge
    1229510, -- Arcing Zap
    1222815, -- Arcane Bolt
    -- Ara-Kara: City of Echoes (S3)
    434793,  -- Resonant Barrage
    434802,  -- Horrifying Shrill
    448248,  -- Revolting Volley
    432967,  -- Alarm Shrill
    -- Tazavesh: Streets of Wonder (S3)
    355934,  -- Hard Light Barrier
    354297,  -- Hyperlight Bolt
    356324,  -- Empowered Glyph of Restraint
}

-- Extra spell IDs to STOP with stun/CC only (channels / when kick is down). Merge into MUST_STOP.
local STOP_LIST = {
    -- Same as kick for S3: all priority casts are both kick and stop.
    -- Add below any "stop-only" IDs (e.g. channels that aren't interruptable) if you get them later.
}

-- Build sets for O(1) lookup. Merge KICK into STOP so “must stop” includes all kick targets.
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

--- Returns true if the given spell ID is in the "must kick" list.
function M.should_kick_cast(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return MUST_KICK[spell_id] == true
end

--- Returns true if the given spell ID is in the "must stop" (kick or stun) list.
function M.should_stop_cast(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return MUST_STOP[spell_id] == true
end

--- If unit is casting/channeling, returns whether that spell should be kicked (and is in the list).
--- When use_allowlist is true, only kicks when cast is in MUST_KICK; when list has no IDs, treats as "kick any".
--- When use_allowlist is false, returns true for any cast (caller still must check is_active_spell_interruptable).
function M.should_kick_unit(unit, use_allowlist)
    if not unit or not unit.get_active_cast_or_channel_id then return false end
    local cast_id = unit:get_active_cast_or_channel_id()
    if not cast_id or cast_id == 0 then return false end
    if not use_allowlist then return true end
    if next(MUST_KICK) == nil then return true end  -- no IDs yet = allow any
    return M.should_kick_cast(cast_id)
end

--- Same as should_kick_unit but for "should we use stun/CC to stop this cast?"
function M.should_stop_unit(unit, use_allowlist)
    if not unit or not unit.get_active_cast_or_channel_id then return false end
    local cast_id = unit:get_active_cast_or_channel_id()
    if not cast_id or cast_id == 0 then return false end
    if not use_allowlist then return true end
    if next(MUST_STOP) == nil then return true end
    return M.should_stop_cast(cast_id)
end

return M
