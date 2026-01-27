-- Setup our plugin info
local plugin = {}

plugin.name = "HCS Protection Paladin"
plugin.version = "1.0.0"
plugin.author = "HCS"
plugin.load = true

-- 1. Safety Check: Ensure the local player exists
local local_player = core.object_manager:get_local_player()

if not local_player or not local_player:is_valid() then
    plugin.load = false
    return plugin
end

-- Import Enums for ID checks
local enums = require("common/enums")

-- 2. Class Check: Are we a Paladin?
local player_class = local_player:get_class()
if player_class ~= enums.class_id.PALADIN then
    plugin.load = false
    return plugin
end

-- 3. Spec Check: Are we Protection?
local spec_id = enums.class_spec_id
local player_spec_id = local_player:get_specialization_id()
local prot_spec_id = spec_id.get_spec_id_from_enum(spec_id.spec_enum.PROTECTION_PALADIN)

if player_spec_id ~= prot_spec_id then
    plugin.load = false
    return plugin
end

return plugin
