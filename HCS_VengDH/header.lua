-- Setup our plugin info
local plugin = {}

plugin.name = "HCS Vengeance Demon Hunter"
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

-- 2. Class Check: Are we a Demon Hunter?
local player_class = local_player:get_class()
if player_class ~= enums.class_id.DEMONHUNTER then
    plugin.load = false
    return plugin
end

-- 3. Spec Check: Are we Vengeance?
local spec_id = enums.class_spec_id
local player_spec_id = local_player:get_specialization_id()
local veng_spec_id = spec_id.get_spec_id_from_enum(spec_id.spec_enum.VENGEANCE_DEMON_HUNTER)

if player_spec_id ~= veng_spec_id then
    plugin.load = false
    return plugin
end

return plugin
