--[[
    M+ Season 3 (TWW) Tank Buster / "Press a cooldown" List
    Dungeon pool: Ara-Kara, Eco-Dome Al'dani, Halls of Atonement, Operation: Floodgate,
    Priory of the Sacred Flame, Tazavesh (Gambit + Streets), The Dawnbreaker.

    When an enemy is casting one of these spells at the tank, use a defensive (e.g. Fortifying,
    Celestial, Ironskin, or class equivalent).

    Usage:
      local tb = require("shared/mplus_s3_tank_buster_list")
      if tb.is_casting_tank_buster(target) then
          -- use defensive
      end
]]

local M = {}

-- Spell IDs: huge hits that need a defensive. Wowhead tooltip IDs from S3 M+ pool.
local TANK_BUSTER_IDS = {
    -- Ara-Kara, City of Echoes
    [438471] = true,   -- Voracious Bite (major tank bite) → Dampen + Celestial
    [433002] = true,   -- Extraction Strike (tank hit + heals mob)
    [1241785] = true,  -- Tainted Blood (stacking tank DoT pressure)
    [1241779] = true,  -- Black Blood Drenched Claws (tank pressure source hit)
    [1219482] = true,  -- Rift Claws (tank rip) → Celestial (+ Fortifying if low/overlap)
    -- Eco-Dome Al'dani
    [1235368] = true,  -- Arcane Slash (tank frontal, magic)
    [1222341] = true,  -- Gloom Bite (tank buster + healing absorb)
    [1215850] = true,  -- Earthcrusher (avoid circles — scary overlap after Sandstorm)
    -- Halls of Atonement
    [1237071] = true,  -- Stone Fist (tank hit + knockback)
    [1235766] = true,  -- Mortal Strike (tank hit + healing reduction)
    [13737] = true,    -- Mortal Strike (HoA variant) → Celestial / Dampen Harm
    [322936] = true,   -- Crumbling Slam (boss tank hit + splash / puddle)
    [328791] = true,   -- Ritual of Woe (tank often soaks 2 beams — major CD)
    -- Operation: Floodgate
    [426883] = true,   -- Wallop (big tank bonk from trash) → Celestial (+ Fortifying if overlap)
    [466188] = true,   -- Thunder Punch → Dampen Harm (physical) or Celestial
    -- Priory of the Sacred Flame
    [424414] = true,   -- Pierce Armor (tank shred / danger hit) → Dampen / Fortifying if pressured
    [435165] = true,   -- Blazing Strike (tank hit + DoT)
    [448485] = true,   -- Shield Slam (knockback risk)
    -- Tazavesh: So'leah's Gambit
    [346116] = true,   -- Shearing Swings (boss tank channel)
    [355048] = true,   -- Shellcracker (tank hit / knockback danger)
    [355429] = true,   -- Tidal Stomp (health check)
    -- Tazavesh: Streets of Wonder
    [352796] = true,   -- Proxy Strike (tank hit)
    [354474] = true,   -- Lockdown (tank root + danger window)
    [355477] = true,   -- Power Kick (tank knockback)
    [349934] = true,   -- Flagellation Protocol (tank channel — always defensive)
    [347716] = true,   -- Letter Opener (tank bleed stacks)
    [1240912] = true,  -- Pierce (tank hit + damage amp debuff)
    -- The Dawnbreaker
    [427001] = true,   -- Terrifying Slam (tank buster — defensive every cast)
    [431491] = true,   -- Tainted Slash (tank bleed pressure)
    [453212] = true,   -- Obsidian Beam (huge hit on tank + party, magic)
    [428086] = true,   -- Shadow Bolt (spam tank damage, magic)
}

-- Physical busters: prefer Dampen Harm (Brewmaster) or equivalent.
local PHYSICAL_BUSTER_IDS = {
    [426883] = true,   -- Wallop
    [466188] = true,   -- Thunder Punch
    [424414] = true,   -- Pierce Armor
    [438471] = true,   -- Voracious Bite
    [13737] = true,    -- Mortal Strike (HoA)
    [1219482] = true,  -- Rift Claws
}

-- Magic busters: prefer Diffuse Magic (Brewmaster) or equivalent.
local MAGIC_BUSTER_IDS = {
    [428086] = true,   -- Shadow Bolt
    [453212] = true,   -- Obsidian Beam
    [1235368] = true,  -- Arcane Slash
    [1222341] = true,  -- Gloom Bite
    [435165] = true,   -- Blazing Strike (fire)
    [1241785] = true,  -- Tainted Blood
}

M.TANK_BUSTER_SPELL_IDS = TANK_BUSTER_IDS
M.PHYSICAL_BUSTER_IDS = PHYSICAL_BUSTER_IDS
M.MAGIC_BUSTER_IDS = MAGIC_BUSTER_IDS

--- Returns true if spell_id is in the tank buster list.
function M.is_tank_buster_cast(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return TANK_BUSTER_IDS[spell_id] == true
end

--- Returns true if the unit is currently casting or channeling a tank buster.
function M.is_casting_tank_buster(unit)
    if not unit or not unit.get_active_cast_or_channel_id then return false end
    local cast_id = unit:get_active_cast_or_channel_id()
    return M.is_tank_buster_cast(cast_id)
end

--- Returns true if this spell ID is a physical tank buster (Brewmaster: use Dampen Harm).
function M.is_physical_tank_buster(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return PHYSICAL_BUSTER_IDS[spell_id] == true
end

--- Returns true if this spell ID is a magic tank buster (Brewmaster: use Diffuse Magic).
function M.is_magic_tank_buster(spell_id)
    if not spell_id or spell_id == 0 then return false end
    return MAGIC_BUSTER_IDS[spell_id] == true
end

--- Returns the cast ID if unit is casting a tank buster, else nil.
function M.get_tank_buster_cast_id(unit)
    if not unit or not unit.get_active_cast_or_channel_id then return nil end
    local cast_id = unit:get_active_cast_or_channel_id()
    if M.is_tank_buster_cast(cast_id) then return cast_id end
    return nil
end

return M
