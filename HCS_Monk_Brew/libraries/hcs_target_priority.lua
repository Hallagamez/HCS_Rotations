--[[
    HCS target-priority helper for rotations.
    Reorders a list of targets so the preferred type is first:
    - "casters_first": units that are casting or channeling move to the front.
    - "skull_first": unit with raid target marker Skull (index 8) moves to the front.
    - "smart": prioritizes threat (tanking player) > low HP (execute) > casters > Skull > default.
    - "default": returns targets unchanged.
]]

local M = {}

-- Raid target marker: 8 = Skull (per game_object get_target_marker_index).
local SKULL_MARKER_INDEX = 8
-- Execute threshold for "smart" mode: prioritize targets below this HP% for finishing.
local SMART_EXECUTE_HP = 30

--- Returns true if the unit is currently casting or channeling (safe checks).
local function is_casting_or_channeling(unit)
    if not unit or not unit.is_valid or not unit:is_valid() then return false end
    if unit.is_casting and unit:is_casting() then return true end
    if unit.is_channeling_or_casting and unit:is_channeling_or_casting() then return true end
    return false
end

--- Returns true if the unit has the Skull raid target marker.
local function is_skull(unit)
    if not unit or not unit.is_valid or not unit:is_valid() then return false end
    if not unit.get_target_marker_index then return false end
    return unit:get_target_marker_index() == SKULL_MARKER_INDEX
end

--- Returns threat info for unit relative to player (safe checks).
--- @param unit game_object
--- @param player game_object
--- @return boolean is_tanking, number threat_percent (0-100)
local function get_threat_info(unit, player)
    if not unit or not player or not unit.get_threat_situation then return false, 0 end
    local threat = unit:get_threat_situation(player)
    if not threat or not threat.is_tanking then return false, 0 end
    local tp = (threat.threat_percent and type(threat.threat_percent) == "number") and threat.threat_percent or 0
    return threat.is_tanking, tp
end

--- Returns unit HP% (safe checks).
--- @param unit game_object
--- @return number hp_percent (0-100)
local function get_hp_percent(unit)
    if not unit or not unit.get_health_percentage then return 100 end
    local hp = unit:get_health_percentage()
    return (type(hp) == "number" and hp) or 100
end

--- Reorders `targets` so the preferred type is first.
--- @param targets table List of game_object (from get_ts_targets or similar).
--- @param mode string "default" | "casters_first" | "skull_first" | "smart"
--- @param player game_object Optional player object for threat checks (required for "smart" mode).
--- @return table Same list, possibly reordered (does not mutate input).
function M.apply_target_priority(targets, mode, player)
    if not targets or #targets == 0 then return targets end
    if mode == "default" or not mode then return targets end

    if mode == "casters_first" then
        local casting, other = {}, {}
        for i = 1, #targets do
            local u = targets[i]
            if is_casting_or_channeling(u) then
                casting[#casting + 1] = u
            else
                other[#other + 1] = u
            end
        end
        for i = 1, #other do casting[#casting + 1] = other[i] end
        return casting
    end

    if mode == "skull_first" then
        for i = 1, #targets do
            if is_skull(targets[i]) then
                local out = { targets[i] }
                for j = 1, i - 1 do out[#out + 1] = targets[j] end
                for j = i + 1, #targets do out[#out + 1] = targets[j] end
                return out
            end
        end
        return targets
    end

    if mode == "smart" then
        if not player then return targets end  -- Fallback if no player provided
        -- Smart priority: 1) Tanking player (highest threat), 2) Low HP (execute), 3) Casters, 4) Skull, 5) Default
        local tanking = {}
        local low_hp = {}
        local casting = {}
        local skull = {}
        local other = {}
        for i = 1, #targets do
            local u = targets[i]
            local is_tanking, threat_pct = get_threat_info(u, player)
            local hp = get_hp_percent(u)
            if is_tanking then
                tanking[#tanking + 1] = { unit = u, threat = threat_pct, hp = hp }
            elseif hp < SMART_EXECUTE_HP then
                low_hp[#low_hp + 1] = { unit = u, hp = hp }
            elseif is_casting_or_channeling(u) then
                casting[#casting + 1] = u
            elseif is_skull(u) then
                skull[#skull + 1] = u
            else
                other[#other + 1] = u
            end
        end
        -- Sort tanking by threat% (highest first), then by HP (lowest first for execute)
        table.sort(tanking, function(a, b)
            if a.threat ~= b.threat then return a.threat > b.threat end
            return a.hp < b.hp
        end)
        -- Sort low HP by HP% (lowest first)
        table.sort(low_hp, function(a, b) return a.hp < b.hp end)
        -- Build final list: tanking (sorted) -> low HP (sorted) -> casters -> skull -> other
        local out = {}
        for i = 1, #tanking do out[#out + 1] = tanking[i].unit end
        for i = 1, #low_hp do out[#out + 1] = low_hp[i].unit end
        for i = 1, #casting do out[#out + 1] = casting[i] end
        for i = 1, #skull do out[#out + 1] = skull[i] end
        for i = 1, #other do out[#out + 1] = other[i] end
        return out
    end

    return targets
end

--- Targeting mode indices used by HCS scripts (combobox 1-based).
--- Scripts use: 1 = Manual, 2 = Auto: Casters first, 3 = Auto: Skull first, 4 = Auto: Smart.
M.MODE_MANUAL = 1
M.MODE_CASTERS_FIRST = 2
M.MODE_SKULL_FIRST = 3
M.MODE_SMART = 4

M.TARGETING_OPTIONS = { "Manual", "Auto: Casters first", "Auto: Skull first", "Auto: Smart (threat + health + priority)" }

return M
