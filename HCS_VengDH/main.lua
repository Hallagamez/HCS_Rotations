--[[
    HCS Vengeance Demon Hunter (IZI SDK)
    Tank: Fury/souls, defensives, M+ S3 interrupt list and tank buster handling.
    Offensive CDs (guide): Fel Devastation ~40s, Soul Carver 1min, Sigil of Spite 1min — use as available;
      Fel Devastation when 50+ Fury; Soul Carver on CD with <3 souls; sync with Fiery Brand if Fiery Demise.
    Defensive CDs: Meta on CD (don't overwrite if >5s left); Fiery Brand on CD; Demon Spikes when no other
      defensives active; Fel Devastation below 70% when use defensives; Darkness on CD for group damage.
    Priority: Infernal Strike (near 2 charges) → Meta → Fracture (near 2 charges) → Spirit Bomb (4+/6 souls)
      → Fiery Brand → Immolation Aura → Sigil of Flame → Sigil of Spite → Felblade → Fel Devastation (50+ Fury)
      → Soul Cleave → Fracture → Felblade → Throw Glaive.
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")

local ok_ui, rotation_settings_ui = pcall(require, "shared/rotation_settings_ui")
local ok_mplus, mplus_s3 = pcall(require, "shared/mplus_s3_interrupt_stun_list")
local ok_cc, class_colors = pcall(require, "shared/hcs_class_colors")
local function hcs_header(cls, title) return (ok_cc and class_colors and class_colors.hcs_header and class_colors.hcs_header(cls, title)) or title end
local ok_tankbuster, tank_buster_list = pcall(require, "shared/mplus_s3_tank_buster_list")
local ok_tp, hcs_target_priority = pcall(require, "shared/hcs_target_priority")

local MELEE_RANGE = 8
local KICK_RANGE = 10
local THROW_GLAIVE_RANGE = 30
local SIGIL_RANGE = 30
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14
local SOUL_CLEAVE_FURY = 30
local FEL_DEVASTATION_FURY = 50   -- use Fel Devastation when >= this (guide)
local FEL_DEVASTATION_HP = 70    -- use as defensive heal when below this %
local META_BUFF_ID = 187827      -- Metamorphosis buff (don't overwrite if >5s left)
local TAG = "hcs_veng_dh_"

local SPELLS = {
    -- Rotation
    SHEAR           = izi.spell(203782),   -- Fury builder
    FRACTURE        = izi.spell(263642),   -- Fury builder (talent), 2 charges
    SOUL_CLEAVE     = izi.spell(228477),   -- Fury spender, heal
    SPIRIT_BOMB     = izi.spell(247454),   -- Spend souls (talent)
    INFERNAL_STRIKE = izi.spell(189110),   -- Charge (2 charges), damage
    IMMOLATION_AURA = izi.spell(258920),   -- AoE / bleed
    SIGIL_OF_FLAME  = izi.spell(204596),   -- Ground sigil, AoE
    SIGIL_OF_SPITE  = izi.spell(204513),   -- 1 min CD, offense (talent)
    THROW_GLAIVE    = izi.spell(204157),   -- Ranged filler / kite
    TORMENT         = izi.spell(185245),   -- Taunt
    FELBLADE        = izi.spell(232893),   -- Fury builder (talent)
    SOUL_CARVER     = izi.spell(207407),   -- 1 min CD, souls (talent)
    FEL_DEVASTATION = izi.spell(212084),   -- 40s channel, offense + heal
    -- Defensives
    DEMON_SPIKES    = izi.spell(203720),   -- Physical mitigation
    FIERY_BRAND     = izi.spell(204021),   -- Magic DR, 1 min (48s with Down in Flames)
    METAMORPHOSIS   = izi.spell(187827),   -- Vengeance Meta, 2 min
    DARKNESS        = izi.spell(196718),   -- Group DR, 5 min (3 with Pitch Black)
    -- Interrupt / stop
    DISRUPT         = izi.spell(183752),   -- Kick
    CHAOS_NOVA      = izi.spell(179057),   -- Stun
    SIGIL_OF_SILENCE = izi.spell(202137),  -- Silence sigil (talent)
}

-- Menu
local menu = {
    root                = core.menu.tree_node(),
    enabled             = core.menu.checkbox(false, TAG .. "enabled"),
    toggle_key          = core.menu.keybind(999, false, TAG .. "toggle"),
    interrupt           = core.menu.checkbox(true, TAG .. "interrupt"),
    mplus_s3_list       = core.menu.checkbox(false, TAG .. "mplus_s3_list"),
    use_cooldowns       = core.menu.checkbox(true, TAG .. "use_cds"),
    use_defensives      = core.menu.checkbox(true, TAG .. "use_def"),
    mplus_s3_tank_buster = core.menu.checkbox(true, TAG .. "mplus_s3_tank_buster"),
    targeting_mode      = core.menu.combobox(1, TAG .. "targeting_mode"),  -- 1=Manual, 2=Casters first, 3=Skull first, 4=Smart
    right_click_attack  = core.menu.checkbox(false, TAG .. "right_click_attack"),  -- Right-click enemy to taunt/attack from range (optional)
    potion_hp           = core.menu.slider_int(0, 100, 35, TAG .. "potion_hp"),
    cooldowns_node      = core.menu.tree_node(),
    trinket1_boss       = core.menu.checkbox(false, TAG .. "trinket1_boss"),
    trinket1_cd         = core.menu.checkbox(true, TAG .. "trinket1_cd"),
    trinket2_boss       = core.menu.checkbox(false, TAG .. "trinket2_boss"),
    trinket2_cd         = core.menu.checkbox(true, TAG .. "trinket2_cd"),
    -- Defensives: own category, per-ability toggles
    defensives_node     = core.menu.tree_node(),
    def_demon_spikes    = core.menu.checkbox(true, TAG .. "def_demon_spikes"),
    def_fiery_brand     = core.menu.checkbox(true, TAG .. "def_fiery_brand"),
    def_metamorphosis   = core.menu.checkbox(true, TAG .. "def_metamorphosis"),
    def_darkness        = core.menu.checkbox(true, TAG .. "def_darkness"),
    darkness_keybind    = core.menu.keybind(999, false, TAG .. "darkness_keybind"),  -- press to cast Darkness (optional button)
    use_infernal_strike = core.menu.checkbox(true, TAG .. "use_infernal_strike"),   -- disable on bosses to avoid leaping into damage
    -- Offensive CDs (own toggles)
    cd_fel_devastation  = core.menu.checkbox(true, TAG .. "cd_fel_devastation"),
    cd_soul_carver      = core.menu.checkbox(true, TAG .. "cd_soul_carver"),
    cd_sigil_of_spite   = core.menu.checkbox(true, TAG .. "cd_sigil_of_spite"),
}

-- Custom settings window
local ui
if ok_ui and rotation_settings_ui and type(rotation_settings_ui.new) == "function" then
    ui = rotation_settings_ui.new({
        id = "hcs_veng_dh",
        title = hcs_header("DEMON_HUNTER", "HCS Vengeance Demon Hunter"),
        default_x = 700,
        default_y = 200,
        default_w = 520,
        default_h = 650,
        theme = "demonhunter",
    })
end
if ui then
    ui:add_tab({ id = "core", label = "Core" }, function(t)
        if t.keybind_grid then
            t:keybind_grid({ elements = { menu.toggle_key }, labels = { "Enable Rotation" } })
        end
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Rotation",
                columns = 1,
                elements = {
                    { element = menu.use_infernal_strike, label = "Use Infernal Strike (leap) — disable on bosses to avoid jumping into damage" },
                },
            })
        end
    end)
    ui:add_tab({ id = "cooldowns", label = "Cooldowns" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Cooldowns",
                columns = 2,
                elements = {
                    { element = menu.use_cooldowns, label = "Use Metamorphosis + offensive CDs" },
                    { element = menu.cd_fel_devastation, label = "Fel Devastation (50+ Fury / below 70% heal)" },
                    { element = menu.cd_soul_carver, label = "Soul Carver" },
                    { element = menu.cd_sigil_of_spite, label = "Sigil of Spite" },
                    { element = menu.trinket1_boss, label = "Trinket 1: Boss only" },
                    { element = menu.trinket1_cd, label = "Trinket 1: On CD" },
                    { element = menu.trinket2_boss, label = "Trinket 2: Boss only" },
                    { element = menu.trinket2_cd, label = "Trinket 2: On CD" },
                },
            })
        end
    end)
    local function defensives_enabled()
        return menu.use_defensives and menu.use_defensives:get_state() == true
    end
    ui:add_tab({ id = "survival", label = "Survival" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Defensives",
                columns = 1,
                elements = {
                    { element = menu.use_defensives, label = "Use defensives + health potion" },
                    { element = menu.mplus_s3_tank_buster, label = "Use defensives on M+ S3 tank busters" },
                    { element = menu.def_demon_spikes, label = "Demon Spikes" },
                    { element = menu.def_fiery_brand, label = "Fiery Brand" },
                    { element = menu.def_metamorphosis, label = "Metamorphosis" },
                    { element = menu.def_darkness, label = "Darkness (auto on CD)" },
                },
            })
        end
        if t.keybind_grid and menu.darkness_keybind then
            t:keybind_grid({
                elements = { menu.darkness_keybind },
                labels = { "Darkness (press key to cast)" },
            })
        end
        if t.slider_list and menu.potion_hp then
            t:slider_list({
                label = "Thresholds",
                elements = {
                    { element = menu.potion_hp, label = "Potion HP%", suffix = "%", visible_when = defensives_enabled },
                },
            })
        end
    end)
    ui:add_tab({ id = "targeting", label = "Targeting" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Targeting",
                columns = 1,
                elements = {
                    { element = menu.interrupt, label = "Interrupt (Disrupt / Chaos Nova)" },
                    { element = menu.mplus_s3_list, label = "M+ S3 list only (kick/stop listed casts)" },
                    { element = menu.right_click_attack, label = "Right-click attack/taunt (range pull)" },
                },
            })
        end
    end)
end

local function rotation_enabled()
    return menu.enabled:get_state() and menu.toggle_key:get_toggle_state()
end

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

-- Fury current (0–100/120).
local function get_fury(me)
    if not me then return 0 end
    if me.power_current and type(me.power_current) == "function" then
        local v = me:power_current(enums.power_type.FURY)
        return (type(v) == "number" and v) or 0
    end
    if me.get_power and type(me.get_power) == "function" then
        local v = me:get_power(enums.power_type.FURY)
        return (type(v) == "number" and v) or 0
    end
    return 0
end

-- Soul fragments current (0–5 typical). Use when engine exposes it (e.g. soul_fragments_current).
local function get_souls(me)
    if not me then return 0 end
    if me.soul_fragments_current and type(me.soul_fragments_current) == "function" then
        local v = me:soul_fragments_current()
        return (type(v) == "number" and v) or 0
    end
    return 0
end

-- Infernal Strike charges (0–2).
local function infernal_strike_charges()
    if not SPELLS.INFERNAL_STRIKE or not SPELLS.INFERNAL_STRIKE.charges then return 0 end
    local c = SPELLS.INFERNAL_STRIKE:charges()
    return (type(c) == "number" and c) or 0
end

-- Fracture charges (0–2 when talented).
local function fracture_charges()
    if not SPELLS.FRACTURE or not SPELLS.FRACTURE.charges then return 0 end
    local c = SPELLS.FRACTURE:charges()
    return (type(c) == "number" and c) or 0
end

-- Render Menu
core.register_on_render_menu_callback(function()
    if ui then ui:on_menu_render() end
    menu.root:render(hcs_header("DEMON_HUNTER", "HCS Vengeance Demon Hunter"), function()
        menu.enabled:render("Enable Plugin")
        if not menu.enabled:get_state() then return end
        if ui and ui.menu and ui.menu.enable and (not rotation_settings_ui or not rotation_settings_ui.is_stub) then
            ui.menu.enable:render("Show Custom UI Window")
        end
        menu.toggle_key:render("Toggle Rotation")
        menu.use_infernal_strike:render("Use Infernal Strike (leap) — disable on bosses")
        menu.interrupt:render("Interrupt (Disrupt / Chaos Nova)")
        menu.mplus_s3_list:render("M+ S3 list only (kick/stop listed casts)")
        menu.cooldowns_node:render("Cooldowns", function()
            menu.use_cooldowns:render("Use Metamorphosis + offensive CDs")
            menu.cd_fel_devastation:render("Fel Devastation")
            menu.cd_soul_carver:render("Soul Carver")
            menu.cd_sigil_of_spite:render("Sigil of Spite")
            menu.trinket1_boss:render("Trinket 1: Use on boss only")
            menu.trinket1_cd:render("Trinket 1: Use on cooldown")
            menu.trinket2_boss:render("Trinket 2: Use on boss only")
            menu.trinket2_cd:render("Trinket 2: Use on cooldown")
        end)
        menu.use_defensives:render("Use defensives + health potion")
        menu.mplus_s3_tank_buster:render("Use defensives on M+ S3 tank busters")
        menu.right_click_attack:render("Right-click attack/taunt (Torment / Throw Glaive)")
        menu.defensives_node:render("Defensives", function()
            menu.def_demon_spikes:render("Demon Spikes")
            menu.def_fiery_brand:render("Fiery Brand")
            menu.def_metamorphosis:render("Metamorphosis")
            menu.def_darkness:render("Darkness (auto on CD)")
            menu.darkness_keybind:render("Darkness (press to cast)")
        end)
        if menu.potion_hp then menu.potion_hp:render("Potion HP%") end
        if menu.targeting_mode and (ok_tp and hcs_target_priority and hcs_target_priority.TARGETING_OPTIONS) then
            menu.targeting_mode:render("Targeting mode", hcs_target_priority.TARGETING_OPTIONS, "Manual = current target only. Auto modes: Casters/Skull = simple priority. Smart = threat (tanking) > low HP (execute) > casters > Skull.")
        end
    end)
end)

core.register_on_render_callback(function()
    if ui then ui:on_render() end
end)

core.register_on_render_control_panel_callback(function()
    local cp_elements = {}
    if not menu.enabled:get_state() then return cp_elements end
    control_panel_helper:insert_toggle(cp_elements, {
        name = string.format("[HCS Vengeance DH] Enabled (%s)", key_helper:get_key_name(menu.toggle_key:get_key_code())),
        keybind = menu.toggle_key
    })
    return cp_elements
end)

-- Main loop
core.register_on_update_callback(function()
    control_panel_helper:on_update(menu)

    local me = izi.me()
    if not me then return end

    -- Right-click attack/taunt: when right-clicking an enemy, cast taunt or ranged attack (works even when rotation off)
    if menu.right_click_attack:get_state() and menu.enabled:get_state() then
        local right_mouse = core.input.is_key_pressed and core.input.is_key_pressed(2)  -- VK_RBUTTON = 2
        if right_mouse then
            local mouse_over = core.object_manager.get_mouse_over_object and core.object_manager.get_mouse_over_object()
            if mouse_over and mouse_over.is_valid and mouse_over:is_valid() and not (mouse_over.is_dead and mouse_over:is_dead()) then
                if not mouse_over:is_damage_immune() and not mouse_over:is_cc_weak() then
                    local dist = me:distance_to(mouse_over)
                    -- Priority: Torment (taunt) > Throw Glaive (30 yd)
                    if dist <= KICK_RANGE and SPELLS.TORMENT:is_learned() and SPELLS.TORMENT:cooldown_up() then
                        if SPELLS.TORMENT:cast_safe(mouse_over, "Right-click: Torment (taunt)") then return end
                    elseif dist <= THROW_GLAIVE_RANGE and SPELLS.THROW_GLAIVE:is_learned() then
                        if SPELLS.THROW_GLAIVE:cast_safe(mouse_over, "Right-click: Throw Glaive") then return end
                    end
                end
            end
        end
    end

    -- Darkness keybind: press key to cast Darkness (works whenever plugin enabled, no target needed)
    if menu.enabled:get_state() and menu.darkness_keybind and menu.darkness_keybind:get_toggle_state() then
        if SPELLS.DARKNESS:is_learned() and SPELLS.DARKNESS:cooldown_up() then
            if SPELLS.DARKNESS:cast_safe(me, "Darkness (button)") then return end
        end
    end

    if not rotation_enabled() then return end

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

    if #targets == 0 then return end
    local target = targets[1]
    if not (target and target.is_valid and target:is_valid()) then return end
    if target:is_damage_immune() then return end
    if target:is_cc_weak() then return end

    local range = me:distance_to(target)
    local in_melee = range <= MELEE_RANGE
    local my_hp = me:get_health_percentage()

    -- Defensives: M+ S3 tank buster first, then potion, then low-HP fallbacks
    if menu.use_defensives:get_state() then
        if menu.mplus_s3_tank_buster:get_state() and ok_tankbuster and tank_buster_list then
            local cast_id = tank_buster_list.get_tank_buster_cast_id and tank_buster_list.get_tank_buster_cast_id(target) or nil
            if cast_id then
                local low_hp = my_hp < 50
                -- Physical: Demon Spikes then Fiery Brand; magic: Fiery Brand then Demon Spikes; default: Demon Spikes. Low HP: Meta.
                if low_hp and menu.def_metamorphosis:get_state() and SPELLS.METAMORPHOSIS:is_learned() and SPELLS.METAMORPHOSIS:cooldown_up() then
                    if SPELLS.METAMORPHOSIS:cast_safe(me, "Tank buster: Metamorphosis (low HP)") then return end
                end
                if tank_buster_list.is_physical_tank_buster(cast_id) then
                    if menu.def_demon_spikes:get_state() and SPELLS.DEMON_SPIKES:is_learned() and SPELLS.DEMON_SPIKES:cooldown_up() and SPELLS.DEMON_SPIKES:cast_safe(me, "Tank buster: Demon Spikes (physical)") then return end
                    if menu.def_fiery_brand:get_state() and SPELLS.FIERY_BRAND:is_learned() and SPELLS.FIERY_BRAND:cooldown_up() and SPELLS.FIERY_BRAND:cast_safe(target, "Tank buster: Fiery Brand") then return end
                elseif tank_buster_list.is_magic_tank_buster(cast_id) then
                    if menu.def_fiery_brand:get_state() and SPELLS.FIERY_BRAND:is_learned() and SPELLS.FIERY_BRAND:cooldown_up() and SPELLS.FIERY_BRAND:cast_safe(target, "Tank buster: Fiery Brand (magic)") then return end
                    if menu.def_demon_spikes:get_state() and SPELLS.DEMON_SPIKES:is_learned() and SPELLS.DEMON_SPIKES:cooldown_up() and SPELLS.DEMON_SPIKES:cast_safe(me, "Tank buster: Demon Spikes") then return end
                else
                    if menu.def_demon_spikes:get_state() and SPELLS.DEMON_SPIKES:is_learned() and SPELLS.DEMON_SPIKES:cooldown_up() and SPELLS.DEMON_SPIKES:cast_safe(me, "Tank buster: Demon Spikes") then return end
                    if menu.def_fiery_brand:get_state() and SPELLS.FIERY_BRAND:is_learned() and SPELLS.FIERY_BRAND:cooldown_up() and SPELLS.FIERY_BRAND:cast_safe(target, "Tank buster: Fiery Brand") then return end
                end
                if low_hp and menu.def_metamorphosis:get_state() and SPELLS.METAMORPHOSIS:is_learned() and SPELLS.METAMORPHOSIS:cooldown_up() then
                    if SPELLS.METAMORPHOSIS:cast_safe(me, "Tank buster: Metamorphosis") then return end
                end
            end
        end

        local threshold = (menu.potion_hp and menu.potion_hp.get and menu.potion_hp:get()) or 35
        if my_hp < threshold and izi.use_best_health_potion_safe and izi.use_best_health_potion_safe() then
            return
        end
        if my_hp < 50 and menu.def_metamorphosis:get_state() and SPELLS.METAMORPHOSIS:is_learned() and SPELLS.METAMORPHOSIS:cooldown_up() then
            if SPELLS.METAMORPHOSIS:cast_safe(me, "Defensive: Metamorphosis") then return end
        end
        if my_hp < 60 and menu.def_demon_spikes:get_state() and SPELLS.DEMON_SPIKES:is_learned() and SPELLS.DEMON_SPIKES:cooldown_up() then
            if SPELLS.DEMON_SPIKES:cast_safe(me, "Defensive: Demon Spikes") then return end
        end
    end

    -- Fel Devastation as defensive heal when below 70% (guide: "generally on CD when below 70% health")
    if menu.use_defensives:get_state() and my_hp < FEL_DEVASTATION_HP and menu.cd_fel_devastation:get_state() then
        if SPELLS.FEL_DEVASTATION:is_learned() and SPELLS.FEL_DEVASTATION:cooldown_up() and get_fury(me) >= FEL_DEVASTATION_FURY then
            if not me:is_channeling_or_casting() and SPELLS.FEL_DEVASTATION:cast_safe(me, "Defensive: Fel Devastation (heal)") then return end
        end
    end

    if not me:affecting_combat() then return end

    -- Offensive / major CDs (guide: use as available)
    if menu.use_cooldowns:get_state() and in_melee then
        -- Metamorphosis: on CD, but don't overwrite if already in Meta with >5s left (avoid overwriting duration)
        local in_meta = (me.buff_up and me:buff_up(META_BUFF_ID)) or false
        if menu.def_metamorphosis:get_state() and SPELLS.METAMORPHOSIS:is_learned() and SPELLS.METAMORPHOSIS:cooldown_up() and not in_meta then
            if SPELLS.METAMORPHOSIS:cast_safe(me, "CD: Metamorphosis") then return end
        end
        -- Darkness: on CD for group damage (guide: on cooldown as much as possible)
        if menu.def_darkness:get_state() and SPELLS.DARKNESS:is_learned() and SPELLS.DARKNESS:cooldown_up() then
            if SPELLS.DARKNESS:cast_safe(me, "CD: Darkness") then return end
        end
        -- Fiery Brand: on CD (offensive); if def_fiery_brand we already use it on tank busters / defensives
        if menu.def_fiery_brand:get_state() and SPELLS.FIERY_BRAND:is_learned() and SPELLS.FIERY_BRAND:cooldown_up() then
            if SPELLS.FIERY_BRAND:cast_safe(target, "CD: Fiery Brand") then return end
        end
        -- Soul Carver: on CD with <3 souls (guide); when we can't read souls, use on CD
        local souls = get_souls(me)
        if menu.cd_soul_carver:get_state() and SPELLS.SOUL_CARVER:is_learned() and SPELLS.SOUL_CARVER:cooldown_up() and souls < 3 then
            if SPELLS.SOUL_CARVER:cast_safe(target, "CD: Soul Carver") then return end
        end
        -- Sigil of Spite: on CD (guide: ideally synced with Fiery Brand; we use on CD)
        if menu.cd_sigil_of_spite:get_state() and SPELLS.SIGIL_OF_SPITE:is_learned() and SPELLS.SIGIL_OF_SPITE:cooldown_up() and range <= SIGIL_RANGE then
            if SPELLS.SIGIL_OF_SPITE:cast_safe(target, "CD: Sigil of Spite") then return end
        end
    end

    -- Trinkets
    local is_boss = (target.is_boss and target:is_boss()) and true or false
    for _, cfg in ipairs({
        { slot = TRINKET_SLOT_1, boss = menu.trinket1_boss, cd = menu.trinket1_cd },
        { slot = TRINKET_SLOT_2, boss = menu.trinket2_boss, cd = menu.trinket2_cd },
    }) do
        if cfg.cd:get_state() and (not cfg.boss:get_state() or is_boss) then
            local trinket = get_trinket_item(me, cfg.slot)
            if trinket and trinket:equipped() and trinket:cooldown_up() and trinket:is_usable() then
                if trinket.use_self_safe and trinket:use_self_safe("CD: Trinket", {}) then return end
            end
        end
    end

    -- Interrupt: Disrupt (kick), then Chaos Nova (stun). M+ S3 list when option on.
    if menu.interrupt:get_state() and (target:is_casting() or target:is_channeling_or_casting()) then
        local use_list = ok_mplus and mplus_s3 and menu.mplus_s3_list:get_state()
        local allow_kick = not use_list or (mplus_s3 and mplus_s3.should_kick_unit(target, true))
        local allow_stop = not use_list or (mplus_s3 and mplus_s3.should_stop_unit(target, true))
        if range <= KICK_RANGE and target.is_active_spell_interruptable and target:is_active_spell_interruptable() and allow_kick then
            if SPELLS.DISRUPT:is_learned() and SPELLS.DISRUPT:cast_safe(target, "Interrupt: Disrupt") then return end
        end
        -- Chaos Nova (stun) only on non-boss (bosses are immune to stuns)
        local is_boss = (target.is_boss and target:is_boss()) and true or false
        if allow_stop and not is_boss and range <= KICK_RANGE and SPELLS.CHAOS_NOVA:is_learned() and SPELLS.CHAOS_NOVA:cooldown_up() then
            if SPELLS.CHAOS_NOVA:cast_safe(me, "Stop: Chaos Nova") then return end
        end
    end

    -- Rotation (guide priority): Infernal Strike (near 2 charges) → Fracture (near 2) → Spirit Bomb (4+/6 souls)
    --   → Fiery Brand → Immolation Aura → Sigil of Flame → Sigil of Spite → Felblade → Fel Devastation (50+ Fury)
    --   → Soul Cleave → Fracture → Felblade → Shear → Throw Glaive
    local fury = get_fury(me)
    local souls = get_souls(me)
    local inf_charges = infernal_strike_charges()
    local frac_charges = fracture_charges()
    local fiery_brand_debuff_id = 204021   -- Fiery Brand on target (use same as spell when in doubt)

    -- 1. Infernal Strike (leap) if enabled — disable on bosses to avoid jumping into damage
    if menu.use_infernal_strike:get_state() then
        if in_melee and SPELLS.INFERNAL_STRIKE:is_learned() and inf_charges >= 2 then
            if SPELLS.INFERNAL_STRIKE:cast_safe(target, "Infernal Strike (2 charges)") then return end
        end
        if in_melee and SPELLS.INFERNAL_STRIKE:is_learned() and SPELLS.INFERNAL_STRIKE:cooldown_up() and inf_charges >= 1 then
            if SPELLS.INFERNAL_STRIKE:cast_safe(target, "Infernal Strike") then return end
        end
    end

    -- 2. Fracture at or near 2 charges (talent)
    if in_melee and SPELLS.FRACTURE:is_learned() and frac_charges >= 2 then
        if SPELLS.FRACTURE:cast_safe(target, "Fracture (2 charges)") then return end
    end

    -- 3–4. Spirit Bomb with 4+ souls if Fiery Brand about to run out, or with 6 souls
    if in_melee and SPELLS.SPIRIT_BOMB:is_learned() and souls >= 6 then
        if fury >= 30 and SPELLS.SPIRIT_BOMB:cast_safe(target, "Spirit Bomb (6 souls)") then return end
    end
    if in_melee and SPELLS.SPIRIT_BOMB:is_learned() and souls >= 4 then
        local fb_on_target = (target.debuff_up and target:debuff_up(fiery_brand_debuff_id)) or false
        if not fb_on_target and fury >= 30 and SPELLS.SPIRIT_BOMB:cast_safe(target, "Spirit Bomb (4+ souls)") then return end
    end

    -- 5. Fiery Brand if debuff not on target (offensive; defensives already use it)
    if menu.def_fiery_brand:get_state() and in_melee and SPELLS.FIERY_BRAND:is_learned() and SPELLS.FIERY_BRAND:cooldown_up() then
        local fb_on_target = (target.debuff_up and target:debuff_up(fiery_brand_debuff_id)) or false
        if not fb_on_target and SPELLS.FIERY_BRAND:cast_safe(target, "Fiery Brand") then return end
    end

    -- 6–7. Immolation Aura, Sigil of Flame
    if in_melee and SPELLS.IMMOLATION_AURA:is_learned() and SPELLS.IMMOLATION_AURA:cooldown_up() then
        if SPELLS.IMMOLATION_AURA:cast_safe(me, "Immolation Aura") then return end
    end
    if range <= SIGIL_RANGE and SPELLS.SIGIL_OF_FLAME:is_learned() and SPELLS.SIGIL_OF_FLAME:cooldown_up() then
        if SPELLS.SIGIL_OF_FLAME:cast_safe(target, "Sigil of Flame") then return end
    end

    -- 8. Sigil of Spite (if not capping souls — when souls < 5 we're safe; otherwise we already used it in CD block)
    if menu.cd_sigil_of_spite:get_state() and range <= SIGIL_RANGE and SPELLS.SIGIL_OF_SPITE:is_learned() and SPELLS.SIGIL_OF_SPITE:cooldown_up() and souls < 5 then
        if SPELLS.SIGIL_OF_SPITE:cast_safe(target, "Sigil of Spite") then return end
    end

    -- 9. Felblade if 6 souls but not enough Fury for Spirit Bomb, or if won't cap Fury
    if in_melee and SPELLS.FELBLADE:is_learned() and SPELLS.FELBLADE:cooldown_up() then
        if souls >= 6 and fury < 30 and SPELLS.FELBLADE:cast_safe(target, "Felblade (souls, need fury)") then return end
        if fury < 90 and SPELLS.FELBLADE:cast_safe(target, "Felblade") then return end
    end

    -- 10. Fel Devastation offensive (50+ Fury, guide: generally on CD)
    if menu.cd_fel_devastation:get_state() and fury >= FEL_DEVASTATION_FURY and SPELLS.FEL_DEVASTATION:is_learned() and SPELLS.FEL_DEVASTATION:cooldown_up() then
        if not me:is_channeling_or_casting() and SPELLS.FEL_DEVASTATION:cast_safe(me, "Fel Devastation (offensive)") then return end
    end

    -- 11. Soul Cleave (spend Fury and souls)
    if fury >= SOUL_CLEAVE_FURY and in_melee and SPELLS.SOUL_CLEAVE:is_learned() then
        if SPELLS.SOUL_CLEAVE:cast_safe(target, "Soul Cleave") then return end
    end

    -- 12. Fracture if won't cap souls (souls < 5; or always if we can't read souls)
    if in_melee and SPELLS.FRACTURE:is_learned() and frac_charges >= 1 and souls < 5 then
        if SPELLS.FRACTURE:cast_safe(target, "Fracture") then return end
    end

    -- 13. Felblade (already handled above when not capping fury)
    -- 14. Shear (builder when no Fracture)
    if in_melee and SPELLS.SHEAR:is_learned() then
        if SPELLS.SHEAR:cast_safe(target, "Shear") then return end
    end

    -- 15. Throw Glaive filler or when kiting
    if range <= THROW_GLAIVE_RANGE and SPELLS.THROW_GLAIVE:is_learned() then
        if SPELLS.THROW_GLAIVE:cast_safe(target, "Throw Glaive") then return end
    end
end)
