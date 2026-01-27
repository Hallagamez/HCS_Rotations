-- Setup our plugin info
local plugin = {}

plugin.name = "HCS Fire Mage"
plugin.version = "1.0.0"
plugin.author = "HCS" 
plugin.load = true

-- 1. Safety Check: Ensure the local player exists (prevents loading screen crashes)
local local_player = core.object_manager:get_local_player()

if not local_player or not local_player:is_valid() then
    plugin.load = false
    return plugin
end

-- Import Enums for ID checks
local enums = require("common/enums")

-- 2. Class Check: Are we a Mage?
local player_class = local_player:get_class()
if player_class ~= enums.class_id.MAGE then
    plugin.load = false
    return plugin
end

-- 3. Spec Check: Are we a Fire Mage?
local spec_id = enums.class_spec_id
local player_spec_id = local_player:get_specialization_id()
local fire_spec_id = spec_id.get_spec_id_from_enum(spec_id.spec_enum.FIRE_MAGE)

if player_spec_id ~= fire_spec_id then
    plugin.load = false
    return plugin
end

return plugin