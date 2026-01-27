--[[
    HCS Fire Mage (IZI SDK)
    Author: HCS
    Updated: M+ Cooldowns, Spellsteal, defensives, Living Bomb, Interrupt (in-combat only)
]]

-- Import libraries
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")
local ok_mplus, mplus_s3 = pcall(require, "shared/mplus_s3_interrupt_stun_list")
local ok_cc, class_colors = pcall(require, "shared/hcs_class_colors")
local function hcs_header(cls, title) return (ok_cc and class_colors and class_colors.hcs_header and class_colors.hcs_header(cls, title)) or title end
local ok_tp, hcs_target_priority = pcall(require, "shared/hcs_target_priority")

local buffs = enums.buff_db
local AOE_RADIUS = 8
local AOE_MIN_TARGETS = 2     -- Treat as AoE at this many or more enemies in splash range
local AOE_FLAMESTRIKE_MIN = 3 -- Only cast Flamestrike at this many or more targets (2t = Pyro/filler)
local EXECUTE_PCT = 30    -- Scorch below this target health %
local KICK_RANGE = 40     -- Counterspell range
local DISPEL_RANGE = 40   -- Remove Curse range (party/self)
local ICE_BLOCK_HP = 25   -- Use Ice Block below this HP %
local ALTER_TIME_HP = 45  -- Use Alter Time below this HP %
local POTION_HP = 35      -- Use health potion below this HP %
local TRINKET_SLOT_1 = 13 -- First trinket slot
local TRINKET_SLOT_2 = 14 -- Second trinket slot
local TAG = "hcs_fire_mage_"

-- Define Spells
local SPELLS = {
    FIREBALL       = izi.spell(133),
    FROSTFIRE_BOLT = izi.spell(443328), -- Hero Talent
    FLAMESTRIKE    = izi.spell(2120),
    PYROBLAST      = izi.spell(11366),
    FIRE_BLAST     = izi.spell(108853), -- Heating Up → Hot Streak
    PHOENIX_FLAMES = izi.spell(257541), -- Heating Up fallback when Fire Blast has no charges
    SCORCH         = izi.spell(2948),
    COUNTERSPELL   = izi.spell(2139),   -- Interrupt (M+)
    SPELLSTEAL     = izi.spell(30449),  -- Steal magic buffs (M+)
    COMBUSTION     = izi.spell(190319), -- Major CD
    RUNE_OF_POWER  = izi.spell(116011), -- Buff before Combustion
    ICE_BLOCK      = izi.spell(45438),  -- Defensive
    ALTER_TIME     = izi.spell(108978), -- Defensive
    LIVING_BOMB    = izi.spell(44457),  -- AoE DoT (when talented)
    REMOVE_CURSE   = izi.spell(475),    -- Dispel curses (party/self)
}

-- Menu System
local menu = {
    root             = core.menu.tree_node(),
    enabled          = core.menu.checkbox(false, TAG .. "enabled"),
    toggle_key       = core.menu.keybind(999, false, TAG .. "toggle"),
    fs_only_instant  = core.menu.checkbox(false, TAG .. "fs_only_instant"),
    interrupt        = core.menu.checkbox(true, TAG .. "interrupt"),
    mplus_s3_list    = core.menu.checkbox(false, TAG .. "mplus_s3_list"),
    use_cooldowns    = core.menu.checkbox(true, TAG .. "use_cds"),   -- Combustion + Rune of Power
    use_defensives   = core.menu.checkbox(true, TAG .. "use_def"),   -- Ice Block, Alter Time, health potion
    use_spellsteal   = core.menu.checkbox(true, TAG .. "spellsteal"),
    use_living_bomb  = core.menu.checkbox(true, TAG .. "living_bomb"),
    targeting_mode   = core.menu.combobox(1, TAG .. "targeting_mode"),  -- 1=Manual, 2=Casters first, 3=Skull first
    use_dispel_curse = core.menu.checkbox(true, TAG .. "dispel_curse"),
    -- Cooldowns category
    cooldowns_node   = core.menu.tree_node(),
    trinket1_boss    = core.menu.checkbox(false, TAG .. "trinket1_boss"),
    trinket1_cd      = core.menu.checkbox(true, TAG .. "trinket1_cd"),
    trinket2_boss    = core.menu.checkbox(false, TAG .. "trinket2_boss"),
    trinket2_cd      = core.menu.checkbox(true, TAG .. "trinket2_cd"),
}

local function rotation_enabled()
    return menu.enabled:get_state() and menu.toggle_key:get_toggle_state()
end

-- True if the unit has a curse we can dispel (uses engine API when available).
local function unit_has_dispelable_curse(unit)
    if not (unit and unit.is_valid and unit:is_valid()) then return false end
    if unit.dispels_curse and type(unit.dispels_curse) == "function" then
        return unit:dispels_curse()
    end
    return false
end

-- Get the equipped on-use item in a trinket slot (13 or 14). Returns izi_item or nil.
local function get_trinket_item(me, slot)
    if not me or not me.get_item_at_inventory_slot then return nil end
    local info = me:get_item_at_inventory_slot(slot)
    if not info or not info.object then return nil end
    local obj = info.object
    if not obj.get_item_id then return nil end
    local id = obj:get_item_id()
    if not id or id == 0 then return nil end
    return izi.item(id)
end

-- Render Menu
core.register_on_render_menu_callback(function()
    menu.root:render(hcs_header("MAGE", "HCS Fire Mage"), function()
        menu.enabled:render("Enable Plugin")
        
        if not menu.enabled:get_state() then return end
        
        menu.toggle_key:render("Toggle Rotation")
        menu.fs_only_instant:render("Flamestrike: Only when Instant")
        menu.interrupt:render("Interrupt (Counterspell)")
        menu.mplus_s3_list:render("M+ S3 list only (kick/stop listed casts)")
        menu.cooldowns_node:render("Cooldowns", function()
            menu.use_cooldowns:render("Use Combustion + Rune of Power")
            menu.trinket1_boss:render("Trinket 1: Use on boss only")
            menu.trinket1_cd:render("Trinket 1: Use on cooldown")
            menu.trinket2_boss:render("Trinket 2: Use on boss only")
            menu.trinket2_cd:render("Trinket 2: Use on cooldown")
        end)
        menu.use_defensives:render("Use defensives + health potion")
        menu.use_spellsteal:render("Spellsteal stealable buffs")
        menu.use_living_bomb:render("Living Bomb in AoE")
        if menu.targeting_mode and (ok_tp and hcs_target_priority and hcs_target_priority.TARGETING_OPTIONS) then
            menu.targeting_mode:render("Targeting mode", hcs_target_priority.TARGETING_OPTIONS, "Manual = current target only. Auto modes: Casters/Skull = simple priority. Smart = threat (tanking) > low HP (execute) > casters > Skull.")
        end
        menu.use_dispel_curse:render("Dispel curses (party/self)")
    end)
end)

-- Render Control Panel (Overlay)
core.register_on_render_control_panel_callback(function()
    local cp_elements = {}
    if not menu.enabled:get_state() then return cp_elements end

    control_panel_helper:insert_toggle(cp_elements, {
        name = string.format("[HCS Mage] Enabled (%s)", key_helper:get_key_name(menu.toggle_key:get_key_code())),
        keybind = menu.toggle_key
    })
    return cp_elements
end)

-- MAIN LOOP (Runs every tick)
core.register_on_update_callback(function()
    control_panel_helper:on_update(menu)

    if not rotation_enabled() then return end

    local me = izi.me()
    if not me then return end

    -- Targeting: Manual = current target only; Auto = target list, optionally prefer Casters, Skull, or Smart
    local targets
    local tm = (menu.targeting_mode and menu.targeting_mode.get) and menu.targeting_mode:get() or 1
    if tm == 1 then
        local t = izi.target()
        targets = (t and t.is_valid and t:is_valid()) and { t } or {}
    else
        targets = izi.get_ts_targets()
        if ok_tp and hcs_target_priority and hcs_target_priority.apply_target_priority and #targets > 0 then
            local mode
            if tm == 2 then mode = "casters_first"
            elseif tm == 3 then mode = "skull_first"
            elseif tm == 4 then mode = "smart"
            else mode = "default" end
            targets = hcs_target_priority.apply_target_priority(targets, mode, me)
        end
    end

    local my_hp = me:get_health_percentage()

    -- Defensives (M+): Ice Block / Alter Time / health potion when low
    if menu.use_defensives:get_state() then
        if my_hp < ICE_BLOCK_HP and SPELLS.ICE_BLOCK:is_learned() then
            if SPELLS.ICE_BLOCK:cast_safe(me, "Defensive: Ice Block") then return end
        end
        if my_hp < ALTER_TIME_HP and SPELLS.ALTER_TIME:is_learned() then
            if SPELLS.ALTER_TIME:cast_safe(me, "Defensive: Alter Time") then return end
        end
        if my_hp < POTION_HP and izi.use_best_health_potion_safe then
            if izi.use_best_health_potion_safe() then return end
        end
    end

    -- Dispel curses (party/self): self first, then party in range
    if menu.use_dispel_curse:get_state() and SPELLS.REMOVE_CURSE:is_learned() and SPELLS.REMOVE_CURSE:cooldown_up() then
        if unit_has_dispelable_curse(me) then
            if SPELLS.REMOVE_CURSE:cast_safe(me, "Dispel: Remove Curse (self)") then return end
        end
        local party = me:get_party_members_in_range(DISPEL_RANGE, true)
        for p = 1, #party do
            local ally = party[p]
            if unit_has_dispelable_curse(ally) then
                if SPELLS.REMOVE_CURSE:cast_safe(ally, "Dispel: Remove Curse (party)") then return end
            end
        end
    end

    -- Only run rotation (cooldowns, interrupt, damage) when player is in combat
    if not me:affecting_combat() then return end

    -- Cooldowns (M+): Rune of Power then Combustion when ready and in combat
    if menu.use_cooldowns:get_state() and #targets > 0 and not me:buff_up(buffs.COMBUSTION) then
        if SPELLS.COMBUSTION:is_learned() and SPELLS.COMBUSTION:cooldown_up() then
            if SPELLS.RUNE_OF_POWER:is_learned() and SPELLS.RUNE_OF_POWER:cooldown_up() then
                if SPELLS.RUNE_OF_POWER:cast_safe(me, "CD: Rune of Power") then return end
            end
            if SPELLS.COMBUSTION:cast_safe(me, "CD: Combustion") then return end
        end
    end

    -- On-use trinkets (Cooldowns category): boss-only and/or on-cooldown
    if #targets > 0 then
        local primary = targets[1]
        local is_boss = (primary and primary.is_boss and primary:is_boss()) and true or false
        for _, cfg in ipairs({
            { slot = TRINKET_SLOT_1, boss = menu.trinket1_boss, cd = menu.trinket1_cd, label = "Trinket 1" },
            { slot = TRINKET_SLOT_2, boss = menu.trinket2_boss, cd = menu.trinket2_cd, label = "Trinket 2" },
        }) do
            if cfg.cd:get_state() and (not cfg.boss:get_state() or is_boss) then
                local trinket = get_trinket_item(me, cfg.slot)
                if trinket and trinket:equipped() and trinket:cooldown_up() and trinket:is_usable() then
                    if trinket.use_self_safe and trinket:use_self_safe("CD: " .. cfg.label, {}) then return end
                end
            end
        end
    end

    -- Interrupt phase (M+): only kick enemies already in combat (avoid pulling ahead of tank).
    if menu.interrupt:get_state() and SPELLS.COUNTERSPELL:is_learned() then
        local use_list = ok_mplus and mplus_s3 and menu.mplus_s3_list:get_state()
        local function should_kick(enemy)
            if not (enemy and enemy.is_valid and enemy:is_valid()) then return false end
            if not enemy:is_in_combat() then return false end  -- do not kick out-of-combat mobs
            if not (enemy:is_casting() or enemy:is_channeling_or_casting()) then return false end
            if not enemy:is_active_spell_interruptable() then return false end
            if use_list and mplus_s3 and not mplus_s3.should_kick_unit(enemy, true) then return false end
            return true
        end
        for i = 1, #targets do
            local t = targets[i]
            if should_kick(t) and SPELLS.COUNTERSPELL:cast_safe(t, "Interrupt: Counterspell") then
                return
            end
        end
        local enemies = me:get_enemies_in_range(KICK_RANGE)
        for j = 1, #enemies do
            local e = enemies[j]
            if should_kick(e) and SPELLS.COUNTERSPELL:cast_safe(e, "Interrupt: Counterspell") then
                return
            end
        end
    end

    -- Iterate through valid targets
    for i = 1, #targets do
        local target = targets[i]

        -- Validate target before any use
        if not (target and target.is_valid and target:is_valid()) then goto continue end
        if target:is_damage_immune(target.DMG.MAGICAL) then goto continue end
        if target:is_cc_weak() then goto continue end

        -- Spellsteal (M+): steal magic buffs before damage
        if menu.use_spellsteal:get_state() and SPELLS.SPELLSTEAL:is_learned() then
            local ps = nil
            if target.is_purgable then ps = target:is_purgable() end
            if ps and ps.is_purgeable then
                if SPELLS.SPELLSTEAL:cast_safe(target, "Spellsteal") then return end
            end
        end

        -- 2+ targets: use enemies in splash range around current target
        local enemies_near = (target.get_enemies_in_splash_range_count and target:get_enemies_in_splash_range_count(AOE_RADIUS)) or 1
        if enemies_near >= AOE_MIN_TARGETS then
            -- Living Bomb (M+): apply DoT in AoE when talented
            if menu.use_living_bomb:get_state() and SPELLS.LIVING_BOMB:is_learned() then
                if SPELLS.LIVING_BOMB:cast_safe(target, "AoE: Living Bomb") then return end
            end
            -- At exactly 2 targets, prefer Pyroblast when Hot Streak (no Flamestrike at 2t)
            if enemies_near == 2 and me:buff_up(buffs.HOT_STREAK) then
                if SPELLS.PYROBLAST:cast_safe(target, "AoE 2t: Pyroblast", { skip_moving = true }) then
                    return
                end
            end

            -- Flamestrike only at 3+ targets (avoids spam at 2)
            if enemies_near >= AOE_FLAMESTRIKE_MIN then
                local instant_fs = me:buff_up(buffs.HOT_STREAK) or me:buff_up(buffs.HYPERTHERMIA)
                local should_cast = not menu.fs_only_instant:get_state() or instant_fs
                if should_cast then
                    if SPELLS.FLAMESTRIKE:cast_safe(target, "AoE: Flamestrike", {
                        use_prediction = true,
                        prediction_type = "MOST_HITS",
                        geometry = "CIRCLE",
                        aoe_radius = 8,
                        min_hits = AOE_FLAMESTRIKE_MIN,
                        cast_time = instant_fs and 0 or nil,
                        skip_moving = instant_fs
                    }) then return end
                end
            end
        end

        -- Single Target Logic
        
        -- 1. Pyroblast (Hot Streak)
        if me:buff_up(buffs.HOT_STREAK) then
            if SPELLS.PYROBLAST:cast_safe(target, "Hot Streak: Pyroblast", { skip_moving = true }) then
                return
            end
        end

        -- 2. Fire Blast (Heating Up → Hot Streak)
        if me:buff_up(buffs.HEATING_UP) and SPELLS.FIRE_BLAST:is_learned() then
            if SPELLS.FIRE_BLAST:cast_safe(target, "Heating Up: Fire Blast") then
                return
            end
        end

        -- 2b. Phoenix Flames (Heating Up fallback when Fire Blast has no charges / on CD)
        if me:buff_up(buffs.HEATING_UP) and SPELLS.PHOENIX_FLAMES:is_learned() then
            if SPELLS.PHOENIX_FLAMES:cast_safe(target, "Heating Up: Phoenix Flames") then
                return
            end
        end

        -- 3. Scorch: Execute (< 30% HP) or while moving
        local target_execute = target:get_health_percentage() < EXECUTE_PCT
        local player_moving = me:is_moving()
        if (target_execute or player_moving) and SPELLS.SCORCH:is_learned() then
            if SPELLS.SCORCH:cast_safe(target, "Scorch (Execute/Moving)") then
                return
            end
        end

        -- 4. Frostfire Empowerment: next Frostfire Bolt is instant and +100% damage — use before normal filler
        if me:buff_up(buffs.FROSTFIRE_EMPOWERMENT) and SPELLS.FROSTFIRE_BOLT:is_learned() then
            if SPELLS.FROSTFIRE_BOLT:cast_safe(target, "Frostfire Empowerment: Frostfire Bolt", { skip_moving = true }) then
                return
            end
        end

        -- 5. Filler: Frostfire Bolt or Fireball (skip during Combustion — burn uses only Scorch/Fire Blast/Pyro)
        if not me:buff_up(buffs.COMBUSTION) then
            local filler_spell = SPELLS.FIREBALL
            if SPELLS.FROSTFIRE_BOLT:is_learned() then
                filler_spell = SPELLS.FROSTFIRE_BOLT
            end
            if filler_spell:cast_safe(target, "Filler: Bolt") then
                return
            end
        end

        ::continue::
    end
end)

-- Optional: Red-accent settings panel (same layout, red theme). Uses ow_menu_api + core.menu.window.
-- This does NOT change the main Project Sylvanas panel (left-hand tree). That uses core.menu and
-- has no theme API. Red panel only draws when the engine creates window "hcs_fire_mage_red_panel".
-- Same element IDs as the main menu so state is shared.
do
    local ok_theme, red_theme = pcall(require, "common/utility/red_accent_theme")
    local ok_api, menu_api = pcall(require, "common/ow_menu_api")
    if ok_theme and red_theme and ok_api and menu_api and menu_api.bind then
        local RED_PANEL_WINDOW_ID = "hcs_fire_mage_red_panel"
        core.register_on_render_window_callback(function()
            local win = core.menu.window(RED_PANEL_WINDOW_ID)
            if not win then return end
            menu_api.begin_frame()
            local bind = menu_api.bind(win)
            local co = red_theme.checkbox_options()
            local so = red_theme.slider_options()
            local to = red_theme.tree_options()
            -- Same IDs as main menu so options stay in sync
            local en = bind.checkbox(TAG .. "enabled", false, co)
            en:render_to_window(win, "Enable Plugin")
            if not en:get() then return end
            -- (Toggle Rotation is a keybind in the main menu — same-id checkbox would clash, so we skip it here)
            bind.checkbox(TAG .. "fs_only_instant", false, co):render_to_window(win, "Flamestrike: Only when Instant")
            bind.checkbox(TAG .. "interrupt", true, co):render_to_window(win, "Interrupt (Counterspell)")
            local cooldowns = bind.tree(TAG .. "cooldowns_red", to)
            cooldowns:render_to_window(win, "Cooldowns", function()
                bind.checkbox(TAG .. "use_cds", true, co):render_to_window(win, "Use Combustion + Rune of Power")
                bind.checkbox(TAG .. "trinket1_boss", false, co):render_to_window(win, "Trinket 1: Use on boss only")
                bind.checkbox(TAG .. "trinket1_cd", true, co):render_to_window(win, "Trinket 1: Use on cooldown")
                bind.checkbox(TAG .. "trinket2_boss", false, co):render_to_window(win, "Trinket 2: Use on boss only")
                bind.checkbox(TAG .. "trinket2_cd", true, co):render_to_window(win, "Trinket 2: Use on cooldown")
            end)
            bind.checkbox(TAG .. "use_def", true, co):render_to_window(win, "Use defensives + health potion")
            bind.checkbox(TAG .. "spellsteal", true, co):render_to_window(win, "Spellsteal stealable buffs")
            bind.checkbox(TAG .. "living_bomb", true, co):render_to_window(win, "Living Bomb in AoE")
            bind.checkbox(TAG .. "manual_target", false, co):render_to_window(win, "Use manual target (current target only)")
            bind.checkbox(TAG .. "dispel_curse", true, co):render_to_window(win, "Dispel curses (party/self)")
        end)
    end
end
