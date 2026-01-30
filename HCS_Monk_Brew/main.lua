--[[
    HCS Monk Brewmaster (IZI SDK)
    Builds: Shado-Pan (default) | Master of Harmony (menu toggle)
    Shado-Pan: ToD → BoK → Niuzao → BoF → TP(combo) → KS → Chi Burst → RJW → EK → KS → RJW → SCK.
    Harmony:   ToD → BoK → Chi Burst → Celestial Brew (at 2 charges) → Niuzao → BoF → TP(combo) → KS → EK → KS → RJW → Tiger Palm.

    Features:
    - Dual Logic: High Key (Survival) vs Low Key (Max DPS) — toggle via Logic mode.
    - Smart Stagger: Auto-Purify on heavy stagger; use Purifying Brew before capping charges.
    - Auto Survival: Fortifying / Celestial / Dampen Harm on dynamic HP thresholds (Survival mode).
    - Burst Sync: Stack Bonedust Brew → Weapons of Order → Niuzao when both WoO and Niuzao ready.
    - Energy anti-cap: Expel Harm when energy above threshold to avoid wasting.
    - Auto-Execute: Touch of Death priority on low-HP targets (Smart targeting).
    - Smart AoE: SCK priority when 5+ enemies (swap rotation).
    - Emergency Healing: Vivify + Expel Harm when below critical HP%.
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")

local ok_ui, rotation_settings_ui = pcall(require, "shared/rotation_settings_ui")
local ok_mplus, mplus_s3 = pcall(require, "libraries/mplus_s3_interrupt_stun_list")
local ok_cc, class_colors = pcall(require, "libraries/hcs_class_colors")
local function hcs_header(cls, title) return (ok_cc and class_colors and class_colors.hcs_header and class_colors.hcs_header(cls, title)) or title end
local ok_tankbuster, tank_buster_list = pcall(require, "libraries/mplus_s3_tank_buster_list")
local ok_tp, hcs_target_priority = pcall(require, "libraries/hcs_target_priority")

-- Ranges and constants
local MELEE_RANGE = 8
local KEG_SMASH_RANGE = 8
local KICK_RANGE = 15
local AOE_RADIUS = 8
local AOE_MIN_TARGETS = 2
local AOE_HIGH_TARGETS = 5   -- Smart AoE: prioritize SCK/RJW above this count
local TOUCH_OF_DEATH_EXECUTE_PCT = 15   -- Improved ToD: use when target HP <= this
local STAGGER_HEAVY_DEBUFF_ID = 124273 -- Heavy (red) stagger: auto-Purify
local PURIFY_HEAVY_THROTTLE_SEC = 2.0  -- Min seconds between Purify when used for heavy stagger (avoid spam)
local last_purify_heavy_time = 0
local ENERGY_CAP = 100       -- Brewmaster base max energy
local VIVIFY_CHI_COST = 2
local BLACKOUT_COMBO_BUFF_ID = 228563   -- Buff from Blackout Kick (consume with Tiger Palm)
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14
local TIGERS_LUST_RANGE = 20   -- Tiger's Lust cast range (dispels roots/snares)
local TAG = "hcs_monk_brew_"

-- Core Brewmaster + talent spells (aligned with Wowhead Shado-Pan build)
local SPELLS = {
    -- Rotation
    KEG_SMASH       = izi.spell(121253),
    BLACKOUT_KICK   = izi.spell(205523),
    TIGER_PALM      = izi.spell(100780),
    BREATH_OF_FIRE  = izi.spell(115181),
    SPINNING_CRANE  = izi.spell(101546),
    TOUCH_OF_DEATH  = izi.spell(322109),   -- Execute when target HP <= 15% (Improved ToD)
    CHI_BURST       = izi.spell(123986),   -- Talent
    EXPLODING_KEG   = izi.spell(325153),   -- Talent (AoE; use after RJW when possible)
    -- Defensives / utility
    EXPEL_HARM      = izi.spell(322101),   -- Self-heal, 15s CD, 15 Energy
    IRONSKIN_BREW   = izi.spell(115308),
    PURIFYING_BREW  = izi.spell(119582),
    CELESTIAL_BREW  = izi.spell(322510),
    FORTIFYING_BREW = izi.spell(115203),
    DAMPEN_HARM     = izi.spell(122278),   -- Physical busters (talent)
    DIFFUSE_MAGIC   = izi.spell(122783),   -- Magic busters (talent)
    LEG_SWEEP       = izi.spell(119381),
    SPEAR_HAND      = izi.spell(116705),   -- Interrupt: 15s CD, 4s lockout
    PARALYSIS       = izi.spell(115078),   -- Incap, stops casts (not an interrupt)
    RING_OF_PEACE   = izi.spell(116844),   -- Knockback/disrupt, stops casts (talent, vs Song of Chi-Ji)
    SONG_OF_CHI_JI  = izi.spell(198898),   -- Disorient, stops casts (talent, 1.8s cast)
    -- Talent CDs (from Wowhead Shado-Pan build)
    WEAPONS_OF_ORDER  = izi.spell(387184),  -- Major CD
    EXPLOSIVE_BREW    = izi.spell(441518),  -- TWW talent (if in build)
    INVOKE_NIUZAO     = izi.spell(132578),  -- Celestial
    RUSHING_JADE_WIND = izi.spell(116847),  -- AoE talent; use before Exploding Keg when both ready
    TIGERS_LUST       = izi.spell(116841),  -- Speed burst on friendly (macro: cast on self)
    BONEDUST_BREW     = izi.spell(325216),  -- Covenant/signature; burst sync with WoO + Niuzao (pruned in TWW, optional)
    VIVIFY            = izi.spell(116670),  -- Emergency instant heal (costs Chi)
}

-- Menu
local menu = {
    root             = core.menu.tree_node(),
    enabled          = core.menu.checkbox(false, TAG .. "enabled"),
    toggle_key       = core.menu.keybind(999, false, TAG .. "toggle"),
    build_harmony    = core.menu.checkbox(false, TAG .. "build_harmony"),  -- Master of Harmony (else Shado-Pan)
    logic_mode       = core.menu.combobox(1, TAG .. "logic_mode"),  -- 1=High Key (Survival), 2=Low Key (Max DPS)
    interrupt        = core.menu.checkbox(true, TAG .. "interrupt"),
    mplus_s3_list    = core.menu.checkbox(false, TAG .. "mplus_s3_list"), -- Only kick/stop casts in M+ S3 list (shared/mplus_s3_interrupt_stun_list)
    use_cooldowns    = core.menu.checkbox(true, TAG .. "use_cds"),
    use_defensives   = core.menu.checkbox(true, TAG .. "use_def"),
    mplus_s3_tank_buster = core.menu.checkbox(true, TAG .. "mplus_s3_tank_buster"),  -- Use defensives when target casts M+ S3 tank busters
    targeting_mode   = core.menu.combobox(1, TAG .. "targeting_mode"),  -- 1=Manual, 2=Casters first, 3=Skull first, 4=Smart
    right_click_attack = core.menu.checkbox(false, TAG .. "right_click_attack"),  -- Right-click enemy to attack from range (optional)
    potion_hp        = core.menu.slider_int(0, 100, 35, TAG .. "potion_hp"),
    expel_harm_hp    = core.menu.slider_int(0, 100, 70, TAG .. "expel_harm_hp"),
    critical_hp      = core.menu.slider_int(0, 100, 35, TAG .. "critical_hp"),    -- Emergency Vivify + Expel below this
    vivify_hp        = core.menu.slider_int(0, 100, 40, TAG .. "vivify_hp"),       -- Vivify when below (if not critical)
    fortifying_hp    = core.menu.slider_int(0, 100, 50, TAG .. "fortifying_hp"),
    celestial_hp     = core.menu.slider_int(0, 100, 60, TAG .. "celestial_hp"),
    dampen_hp        = core.menu.slider_int(0, 100, 55, TAG .. "dampen_hp"),       -- Dampen Harm when below (auto survival)
    energy_anticap   = core.menu.slider_int(70, 100, 88, TAG .. "energy_anticap"), -- Use Expel Harm above this % energy to avoid cap
    cooldowns_node   = core.menu.tree_node(),
    trinket1_boss    = core.menu.checkbox(false, TAG .. "trinket1_boss"),
    trinket1_cd      = core.menu.checkbox(true, TAG .. "trinket1_cd"),
    trinket2_boss    = core.menu.checkbox(false, TAG .. "trinket2_boss"),
    trinket2_cd      = core.menu.checkbox(true, TAG .. "trinket2_cd"),
    -- Macros (keybinds that perform one-off or self-target actions)
    macros_node           = core.menu.tree_node(),
    macro_speed_self      = core.menu.keybind(999, false, TAG .. "macro_speed_self"),  -- Tiger's Lust on self
    tigers_lust_dispel_roots = core.menu.checkbox(true, TAG .. "tigers_lust_dispel_roots"),  -- Dispels roots: self first, then party
}

-- Custom settings window
local ui
if ok_ui and rotation_settings_ui and type(rotation_settings_ui.new) == "function" then
    ui = rotation_settings_ui.new({
        id = "hcs_monk_brew",
        title = hcs_header("MONK", "HCS Monk Brewmaster (Shado-Pan)"),
        default_x = 700,
        default_y = 200,
        default_w = 520,
        default_h = 650,
        theme = "monk",
    })
end
if ui then
    ui:add_tab({ id = "core", label = "Core" }, function(t)
        if t.keybind_grid then
            t:keybind_grid({ elements = { menu.toggle_key }, labels = { "Enable Rotation" } })
        end
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Build & Logic",
                columns = 1,
                elements = {
                    { element = menu.build_harmony, label = "Master of Harmony (else Shado-Pan)" },
                },
            })
        end
        if menu.logic_mode and t.combobox_list then
            t:combobox_list({
                label = "Dual Logic",
                elements = { { element = menu.logic_mode, label = "Mode", options = LOGIC_OPTIONS } },
            })
        end
    end)
    ui:add_tab({ id = "cooldowns", label = "Cooldowns" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Cooldowns",
                columns = 2,
                elements = {
                    { element = menu.use_cooldowns, label = "Use Celestial / CDs" },
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
                },
            })
        end
        if t.slider_list and menu.potion_hp then
            t:slider_list({
                label = "Thresholds",
                elements = {
                    { element = menu.potion_hp, label = "Potion HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.expel_harm_hp, label = "Expel Harm HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.critical_hp, label = "Emergency (Vivify + Expel) HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.vivify_hp, label = "Vivify HP% (non-critical)", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.fortifying_hp, label = "Fortifying Brew HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.celestial_hp, label = "Celestial Brew HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.dampen_hp, label = "Dampen Harm HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.energy_anticap, label = "Energy anti-cap %", suffix = "%", visible_when = defensives_enabled },
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
                    { element = menu.interrupt, label = "Interrupt (Spear Hand Strike / Leg Sweep)" },
                    { element = menu.mplus_s3_list, label = "M+ S3 list only (kick/stop listed casts)" },
                    { element = menu.right_click_attack, label = "Right-click attack (range pull)" },
                },
            })
        end
    end)
    ui:add_tab({ id = "macros", label = "Macros" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Tiger's Lust",
                columns = 1,
                elements = {
                    { element = menu.tigers_lust_dispel_roots, label = "Dispel roots (self first, then party)" },
                },
            })
        end
        if t.keybind_grid then
            t:keybind_grid({
                elements = { menu.macro_speed_self },
                labels = { "Tiger's Lust on self (speed burst)" },
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

local LOGIC_OPTIONS = { "High Key (Survival)", "Low Key (Max DPS)" }

local function get_energy(me)
    if not me or not enums or not enums.power_type then return 0 end
    local pt = enums.power_type.ENERGY
    if me.get_power and type(me.get_power) == "function" then
        local v = me:get_power(pt)
        return (type(v) == "number" and v) or 0
    end
    if me.power_current and type(me.power_current) == "function" then
        local v = me:power_current(pt)
        return (type(v) == "number" and v) or 0
    end
    return 0
end

local function get_chi(me)
    if not me or not enums or not enums.power_type then return 0 end
    local pt = enums.power_type.CHI
    if me.get_power and type(me.get_power) == "function" then
        local v = me:get_power(pt)
        return (type(v) == "number" and v) or 0
    end
    if me.power_current and type(me.power_current) == "function" then
        local v = me:power_current(pt)
        return (type(v) == "number" and v) or 0
    end
    return 0
end

local function get_max_energy(me)
    if not me or not enums or not enums.power_type then return ENERGY_CAP end
    local pt = enums.power_type.ENERGY
    if me.get_max_power and type(me.get_max_power) == "function" then
        local v = me:get_max_power(pt)
        return (type(v) == "number" and v >= 1) and v or ENERGY_CAP
    end
    return ENERGY_CAP
end

local function purifying_charges()
    if not SPELLS.PURIFYING_BREW or not SPELLS.PURIFYING_BREW.charges then return 0 end
    local c = SPELLS.PURIFYING_BREW:charges()
    return (type(c) == "number" and c) or 0
end

local function purifying_max_charges()
    if not SPELLS.PURIFYING_BREW or not SPELLS.PURIFYING_BREW.max_charges then return 1 end
    local c = SPELLS.PURIFYING_BREW:max_charges()
    return (type(c) == "number" and c >= 1) and c or 1
end

local function is_heavy_stagger(me)
    if not me or not me.debuff_up then return false end
    local v = me:debuff_up(STAGGER_HEAVY_DEBUFF_ID)
    return v == true or (type(v) == "number" and v > 0)
end

local function is_survival_mode()
    local v = (menu.logic_mode and menu.logic_mode.get) and menu.logic_mode:get() or 1
    return v == 1
end

-- Render Menu
core.register_on_render_menu_callback(function()
    if ui then ui:on_menu_render() end
    menu.root:render(hcs_header("MONK", "HCS Monk Brewmaster (Shado-Pan)"), function()
        menu.enabled:render("Enable Plugin")
        if not menu.enabled:get_state() then return end
        if ui and ui.menu and ui.menu.enable and (not rotation_settings_ui or not rotation_settings_ui.is_stub) then
            ui.menu.enable:render("Show Custom UI Window")
        end
        menu.toggle_key:render("Toggle Rotation")
        menu.build_harmony:render("Master of Harmony build (else Shado-Pan)")
        if menu.logic_mode then menu.logic_mode:render("Logic mode", LOGIC_OPTIONS, "High Key = Survival priority. Low Key = Max DPS.") end
        menu.interrupt:render("Interrupt (Spear Hand / Leg Sweep)")
        menu.mplus_s3_list:render("M+ S3 list only (kick/stop listed casts)")
        menu.cooldowns_node:render("Cooldowns", function()
            menu.use_cooldowns:render("Use Celestial Brew + cooldowns")
            menu.trinket1_boss:render("Trinket 1: Use on boss only")
            menu.trinket1_cd:render("Trinket 1: Use on cooldown")
            menu.trinket2_boss:render("Trinket 2: Use on boss only")
            menu.trinket2_cd:render("Trinket 2: Use on cooldown")
        end)
        menu.use_defensives:render("Use defensives + health potion")
        menu.mplus_s3_tank_buster:render("Use defensives on M+ S3 tank busters")
        menu.right_click_attack:render("Right-click attack (Chi Burst)")
        if menu.potion_hp then menu.potion_hp:render("Potion HP%") end
        if menu.expel_harm_hp then menu.expel_harm_hp:render("Expel Harm (self-heal) HP%") end
        if menu.critical_hp then menu.critical_hp:render("Emergency heal HP% (Vivify + Expel)") end
        if menu.vivify_hp then menu.vivify_hp:render("Vivify HP% (non-critical)") end
        if menu.fortifying_hp then menu.fortifying_hp:render("Fortifying Brew HP%") end
        if menu.celestial_hp then menu.celestial_hp:render("Celestial Brew HP%") end
        if menu.dampen_hp then menu.dampen_hp:render("Dampen Harm HP%") end
        if menu.energy_anticap then menu.energy_anticap:render("Energy anti-cap % (Expel above)") end
        if menu.targeting_mode and (ok_tp and hcs_target_priority and hcs_target_priority.TARGETING_OPTIONS) then
            menu.targeting_mode:render("Targeting mode", hcs_target_priority.TARGETING_OPTIONS, "Manual = current target only. Auto modes: Casters/Skull = simple priority. Smart = threat (tanking) > low HP (execute) > casters > Skull.")
        end
        menu.macros_node:render("Macros", function()
            menu.tigers_lust_dispel_roots:render("Dispel roots with Tiger's Lust (self first, then party)")
            menu.macro_speed_self:render("Tiger's Lust on self (speed burst)")
        end)
    end)
end)

core.register_on_render_callback(function()
    if ui then ui:on_render() end
end)

-- Control Panel
core.register_on_render_control_panel_callback(function()
    local cp_elements = {}
    if not menu.enabled:get_state() then return cp_elements end
    control_panel_helper:insert_toggle(cp_elements, {
        name = string.format("[HCS Brewmaster] Enabled (%s)", key_helper:get_key_name(menu.toggle_key:get_key_code())),
        keybind = menu.toggle_key
    })
    return cp_elements
end)

-- Main loop
core.register_on_update_callback(function()
    control_panel_helper:on_update(menu)

    local me = izi.me()
    if not me then return end

    -- Right-click attack: when right-clicking an enemy, cast ranged attack (works even when rotation off)
    if menu.right_click_attack:get_state() and menu.enabled:get_state() then
        local right_mouse = core.input.is_key_pressed and core.input.is_key_pressed(2)  -- VK_RBUTTON = 2
        if right_mouse then
            local mouse_over = core.object_manager.get_mouse_over_object and core.object_manager.get_mouse_over_object()
            if mouse_over and mouse_over.is_valid and mouse_over:is_valid() and not (mouse_over.is_dead and mouse_over:is_dead()) then
                if not mouse_over:is_damage_immune() and not mouse_over:is_cc_weak() then
                    local dist = me:distance_to(mouse_over)
                    -- Chi Burst (40 yd, talent) - ranged attack
                    if dist <= 40 and SPELLS.CHI_BURST:is_learned() and SPELLS.CHI_BURST:cooldown_up() then
                        if SPELLS.CHI_BURST:cast_safe(mouse_over, "Right-click: Chi Burst") then return end
                    end
                end
            end
        end
    end

    -- Tiger's Lust: macros and root dispel (run when plugin enabled, even if rotation off)
    if menu.enabled:get_state() and SPELLS.TIGERS_LUST:is_learned() and SPELLS.TIGERS_LUST:cooldown_up() then
        -- 1. Manual macro: cast on self when key toggled
        if menu.macro_speed_self:get_toggle_state() then
            if SPELLS.TIGERS_LUST:cast_safe(me, "Macro: Tiger's Lust (self)") then return end
        end
        -- 2. Auto-dispel roots: player always primary, then any rooted party member in range
        if menu.tigers_lust_dispel_roots:get_state() then
            if me.is_rooted and me:is_rooted() then
                if SPELLS.TIGERS_LUST:cast_safe(me, "Tiger's Lust: dispel root (self)") then return end
            else
                local party = me:get_party_members_in_range(TIGERS_LUST_RANGE, true)
                for i = 1, #party do
                    local ally = party[i]
                    if ally and ally.is_valid and ally:is_valid() and ally.is_rooted and ally:is_rooted() then
                        if SPELLS.TIGERS_LUST:cast_safe(ally, "Tiger's Lust: dispel root (party)") then return end
                        break
                    end
                end
            end
        end
    end

    if not rotation_enabled() then return end

    -- Emergency Healing: Vivify + Expel when critical (no target required)
    if menu.use_defensives:get_state() then
        local my_hp = me:get_health_percentage()
        local crit_pct = (menu.critical_hp and menu.critical_hp.get and menu.critical_hp:get()) or 35
        if my_hp < crit_pct then
            local chi = get_chi(me)
            if chi >= VIVIFY_CHI_COST and SPELLS.VIVIFY:is_learned() and SPELLS.VIVIFY:cooldown_up() then
                if SPELLS.VIVIFY:cast_safe(me, "Emergency: Vivify") then return end
            end
            if SPELLS.EXPEL_HARM:is_learned() and SPELLS.EXPEL_HARM:cooldown_up() then
                if SPELLS.EXPEL_HARM:cast_safe(me, "Emergency: Expel Harm") then return end
            end
        end
    end

    -- Auto Survival: Fortifying / Celestial / Dampen by dynamic HP (Survival mode only)
    if menu.use_defensives:get_state() and is_survival_mode() then
        local my_hp = me:get_health_percentage()
        local fh = (menu.fortifying_hp and menu.fortifying_hp.get and menu.fortifying_hp:get()) or 50
        local ch = (menu.celestial_hp and menu.celestial_hp.get and menu.celestial_hp:get()) or 60
        local dh = (menu.dampen_hp and menu.dampen_hp.get and menu.dampen_hp:get()) or 55
        if my_hp < fh and SPELLS.FORTIFYING_BREW:is_learned() and SPELLS.FORTIFYING_BREW:cooldown_up() then
            if SPELLS.FORTIFYING_BREW:cast_safe(me, "Auto Survival: Fortifying Brew") then return end
        end
        if my_hp < ch and SPELLS.CELESTIAL_BREW:is_learned() and SPELLS.CELESTIAL_BREW:cooldown_up() then
            if SPELLS.CELESTIAL_BREW:cast_safe(me, "Auto Survival: Celestial Brew") then return end
        end
        if my_hp < dh and SPELLS.DAMPEN_HARM:is_learned() and SPELLS.DAMPEN_HARM:cooldown_up() then
            if SPELLS.DAMPEN_HARM:cast_safe(me, "Auto Survival: Dampen Harm") then return end
        end
    end

    -- Self-heal / potion / Expel (non-critical): Expel at expel_harm_hp; potion at potion_hp
    if menu.use_defensives:get_state() then
        local my_hp = me:get_health_percentage()
        local crit_pct = (menu.critical_hp and menu.critical_hp.get and menu.critical_hp:get()) or 35
        local eh_pct = (menu.expel_harm_hp and menu.expel_harm_hp.get and menu.expel_harm_hp:get()) or 70
        if my_hp < eh_pct and my_hp >= crit_pct and SPELLS.EXPEL_HARM:is_learned() and SPELLS.EXPEL_HARM:cooldown_up() then
            if SPELLS.EXPEL_HARM:cast_safe(me, "Defensive: Expel Harm (self-heal)") then return end
        end
        local potion_pct = (menu.potion_hp and menu.potion_hp.get and menu.potion_hp:get()) or 35
        if my_hp < potion_pct and izi.use_best_health_potion_safe and izi.use_best_health_potion_safe() then
            return
        end
    end

    -- Energy anti-cap: Expel Harm when near cap (avoid wasting energy) — skip if critical
    if menu.use_defensives:get_state() then
        local my_hp = me:get_health_percentage()
        local crit_pct = (menu.critical_hp and menu.critical_hp.get and menu.critical_hp:get()) or 35
        if my_hp >= crit_pct and SPELLS.EXPEL_HARM:is_learned() and SPELLS.EXPEL_HARM:cooldown_up() then
            local e = get_energy(me)
            local emax = get_max_energy(me)
            local thresh = (menu.energy_anticap and menu.energy_anticap.get and menu.energy_anticap:get()) or 88
            if emax > 0 and (e / emax) * 100 >= thresh then
                if SPELLS.EXPEL_HARM:cast_safe(me, "Energy anti-cap: Expel Harm") then return end
            end
        end
    end

    -- Vivify (non-critical): when below vivify_hp, if we have chi and not critical
    if menu.use_defensives:get_state() then
        local my_hp = me:get_health_percentage()
        local crit_pct = (menu.critical_hp and menu.critical_hp.get and menu.critical_hp:get()) or 35
        local vh = (menu.vivify_hp and menu.vivify_hp.get and menu.vivify_hp:get()) or 40
        if my_hp < vh and my_hp >= crit_pct then
            local chi = get_chi(me)
            if chi >= VIVIFY_CHI_COST and SPELLS.VIVIFY:is_learned() and SPELLS.VIVIFY:cooldown_up() then
                if SPELLS.VIVIFY:cast_safe(me, "Vivify (non-critical)") then return end
            end
        end
    end

    -- Smart Stagger: Purify on heavy stagger or when charges would cap (throttle all Purify to once per 2s)
    if menu.use_defensives:get_state() and SPELLS.PURIFYING_BREW:is_learned() and SPELLS.PURIFYING_BREW:cooldown_up() then
        local pc = purifying_charges()
        local pmax = purifying_max_charges()
        local at_cap = pmax >= 1 and pc >= pmax
        local heavy = is_heavy_stagger(me)
        local now = (core and core.time and core.time()) or 0
        local throttle_ok = (now - last_purify_heavy_time) >= PURIFY_HEAVY_THROTTLE_SEC
        if not throttle_ok then
            -- skip: already Purified recently
        elseif at_cap then
            if SPELLS.PURIFYING_BREW:cast_safe(me, "Smart Stagger: Purifying Brew") then
                last_purify_heavy_time = now
                return
            end
        elseif heavy and pc >= pmax then
            if SPELLS.PURIFYING_BREW:cast_safe(me, "Smart Stagger: Purifying Brew") then
                last_purify_heavy_time = now
                return
            end
        end
    end

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

    -- Defensives: M+ S3 tank buster reaction only (self-heal / potion / Fortifying / Celestial run pre-target above)
    if menu.use_defensives:get_state() and menu.mplus_s3_tank_buster:get_state() and ok_tankbuster and tank_buster_list then
        local cast_id = tank_buster_list.get_tank_buster_cast_id and tank_buster_list.get_tank_buster_cast_id(target) or nil
        if cast_id then
            local my_hp = me:get_health_percentage()
            local low_hp = my_hp < 50  -- Fortifying when pressured / overlap
            if tank_buster_list.is_physical_tank_buster(cast_id) then
                if SPELLS.DAMPEN_HARM:is_learned() and SPELLS.DAMPEN_HARM:cooldown_up() and SPELLS.DAMPEN_HARM:cast_safe(me, "Tank buster: Dampen Harm (physical)") then return end
                if SPELLS.CELESTIAL_BREW:is_learned() and SPELLS.CELESTIAL_BREW:cooldown_up() and SPELLS.CELESTIAL_BREW:cast_safe(me, "Tank buster: Celestial Brew") then return end
                if low_hp and SPELLS.FORTIFYING_BREW:is_learned() and SPELLS.FORTIFYING_BREW:cooldown_up() and SPELLS.FORTIFYING_BREW:cast_safe(me, "Tank buster: Fortifying Brew") then return end
                if SPELLS.IRONSKIN_BREW:is_learned() and SPELLS.IRONSKIN_BREW:cooldown_up() and SPELLS.IRONSKIN_BREW:cast_safe(me, "Tank buster: Ironskin Brew") then return end
            elseif tank_buster_list.is_magic_tank_buster(cast_id) then
                if SPELLS.DIFFUSE_MAGIC:is_learned() and SPELLS.DIFFUSE_MAGIC:cooldown_up() and SPELLS.DIFFUSE_MAGIC:cast_safe(me, "Tank buster: Diffuse Magic (magic)") then return end
                if SPELLS.CELESTIAL_BREW:is_learned() and SPELLS.CELESTIAL_BREW:cooldown_up() and SPELLS.CELESTIAL_BREW:cast_safe(me, "Tank buster: Celestial Brew") then return end
                if low_hp and SPELLS.FORTIFYING_BREW:is_learned() and SPELLS.FORTIFYING_BREW:cooldown_up() and SPELLS.FORTIFYING_BREW:cast_safe(me, "Tank buster: Fortifying Brew") then return end
                if SPELLS.IRONSKIN_BREW:is_learned() and SPELLS.IRONSKIN_BREW:cooldown_up() and SPELLS.IRONSKIN_BREW:cast_safe(me, "Tank buster: Ironskin Brew") then return end
            else
                if SPELLS.CELESTIAL_BREW:is_learned() and SPELLS.CELESTIAL_BREW:cooldown_up() and SPELLS.CELESTIAL_BREW:cast_safe(me, "Tank buster: Celestial Brew") then return end
                if low_hp and SPELLS.FORTIFYING_BREW:is_learned() and SPELLS.FORTIFYING_BREW:cooldown_up() and SPELLS.FORTIFYING_BREW:cast_safe(me, "Tank buster: Fortifying Brew") then return end
                if SPELLS.IRONSKIN_BREW:is_learned() and SPELLS.IRONSKIN_BREW:cooldown_up() and SPELLS.IRONSKIN_BREW:cast_safe(me, "Tank buster: Ironskin Brew") then return end
            end
        end
    end

    if not me:affecting_combat() then return end

    -- Burst Sync: Bonedust → WoO → Niuzao when both WoO and Niuzao ready
    local woo_ready = SPELLS.WEAPONS_OF_ORDER and SPELLS.WEAPONS_OF_ORDER:is_learned() and SPELLS.WEAPONS_OF_ORDER:cooldown_up()
    local niuzao_ready = SPELLS.INVOKE_NIUZAO and SPELLS.INVOKE_NIUZAO:is_learned() and SPELLS.INVOKE_NIUZAO:cooldown_up()
    if menu.use_cooldowns:get_state() and in_melee and woo_ready and niuzao_ready then
        if SPELLS.BONEDUST_BREW and SPELLS.BONEDUST_BREW:is_learned() and SPELLS.BONEDUST_BREW:cooldown_up() then
            if SPELLS.BONEDUST_BREW:cast_safe(target, "Burst Sync: Bonedust Brew") then return end
        end
        if SPELLS.WEAPONS_OF_ORDER:cast_safe(me, "Burst Sync: Weapons of Order") then return end
        if SPELLS.INVOKE_NIUZAO:cast_safe(me, "Burst Sync: Invoke Niuzao") then return end
    end

    -- Cooldowns: Weapons of Order, Explosive Brew, Invoke Niuzao (when not stacking)
    if menu.use_cooldowns:get_state() and in_melee then
        if woo_ready and SPELLS.WEAPONS_OF_ORDER:cast_safe(me, "CD: Weapons of Order") then return end
        if SPELLS.EXPLOSIVE_BREW and SPELLS.EXPLOSIVE_BREW:is_learned() and SPELLS.EXPLOSIVE_BREW:cooldown_up() then
            if SPELLS.EXPLOSIVE_BREW:cast_safe(target, "CD: Explosive Brew") then return end
        end
        if niuzao_ready and SPELLS.INVOKE_NIUZAO:cast_safe(me, "CD: Invoke Niuzao") then return end
        if SPELLS.CELESTIAL_BREW:is_learned() and SPELLS.CELESTIAL_BREW:cooldown_up() then
            if SPELLS.CELESTIAL_BREW:cast_safe(me, "CD: Celestial Brew") then return end
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

    -- Interrupt & stop casts (optional: only casts in M+ S3 list when mplus_s3_list is on)
    -- Order: Spear Hand (interrupt) -> Leg Sweep (AoE stun) -> Paralysis (incap) -> Ring of Peace (knockback) -> Song of Chi-Ji (disorient, if talented)
    -- Ring of Peace, Paralysis, Song of Chi-Ji: only on non-boss, non-elite (avoid wasting them on immune or low-value targets)
    local function is_boss_or_elite(u)
        if not u then return true end
        if u.is_boss and u:is_boss() then return true end
        local c = u.get_classification and u:get_classification()
        if c and (c == 1 or c == 2 or c == 3) then return true end  -- 1=elite, 2=rareelite, 3=worldboss
        return false
    end
    local stop_ok_trash = not is_boss_or_elite(target)  -- true only for normal/rare/trivial mobs

    if menu.interrupt:get_state() then
        if target:is_casting() or target:is_channeling_or_casting() then
            local use_list = ok_mplus and mplus_s3 and menu.mplus_s3_list:get_state()
            local allow_kick = not use_list or (mplus_s3 and mplus_s3.should_kick_unit(target, true))
            local allow_stop = not use_list or (mplus_s3 and mplus_s3.should_stop_unit(target, true))
            -- 1. Spear Hand Strike (true interrupt, 15s CD, 4s lockout)
            if range <= KICK_RANGE and target.is_active_spell_interruptable and target:is_active_spell_interruptable() and allow_kick then
                if SPELLS.SPEAR_HAND:is_learned() and SPELLS.SPEAR_HAND:cast_safe(target, "Interrupt: Spear Hand Strike") then return end
            end
            -- 2–5. Stops (not interrupts): Leg Sweep, Paralysis, RoP, Song only on trash (not boss/elite)
            if allow_stop then
                if stop_ok_trash and range <= KICK_RANGE and SPELLS.LEG_SWEEP:is_learned() and SPELLS.LEG_SWEEP:cooldown_up() then
                    if SPELLS.LEG_SWEEP:cast_safe(target, "Stop: Leg Sweep") then return end
                end
                if stop_ok_trash and range <= 20 and SPELLS.PARALYSIS:is_learned() and SPELLS.PARALYSIS:cooldown_up() then
                    if SPELLS.PARALYSIS:cast_safe(target, "Stop: Paralysis") then return end
                end
                if stop_ok_trash and range <= 30 and SPELLS.RING_OF_PEACE:is_learned() and SPELLS.RING_OF_PEACE:cooldown_up() then
                    if SPELLS.RING_OF_PEACE:cast_safe(target, "Stop: Ring of Peace") then return end
                end
                if stop_ok_trash and range <= 40 and SPELLS.SONG_OF_CHI_JI:is_learned() and SPELLS.SONG_OF_CHI_JI:cooldown_up() then
                    if SPELLS.SONG_OF_CHI_JI:cast_safe(target, "Stop: Song of Chi-Ji") then return end
                end
            end
        end
    end

    local enemies_near = (target.get_enemies_in_splash_range_count and target:get_enemies_in_splash_range_count(AOE_RADIUS)) or 1
    local target_hp_pct = (target.get_health_percentage and target:get_health_percentage()) or 100
    local has_combo = (me.buff_up and me:buff_up(BLACKOUT_COMBO_BUFF_ID)) or false
    local keg_charges = 0
    if SPELLS.KEG_SMASH and SPELLS.KEG_SMASH.charges then
        local c = SPELLS.KEG_SMASH:charges()
        keg_charges = (type(c) == "number" and c) or 0
    end
    if keg_charges == 0 and SPELLS.KEG_SMASH:cooldown_up() then keg_charges = 1 end

    local celestial_charges = 0
    if SPELLS.CELESTIAL_BREW and SPELLS.CELESTIAL_BREW.charges then
        local c = SPELLS.CELESTIAL_BREW:charges()
        celestial_charges = (type(c) == "number" and c) or 0
    end

    local use_harmony = menu.build_harmony:get_state()

    -- 1. Touch of Death (execute when allowed) – both builds
    if in_melee and SPELLS.TOUCH_OF_DEATH:is_learned() and SPELLS.TOUCH_OF_DEATH:cooldown_up() and target_hp_pct <= TOUCH_OF_DEATH_EXECUTE_PCT then
        if SPELLS.TOUCH_OF_DEATH:cast_safe(target, "Execute: Touch of Death") then return end
    end

    -- 2. Blackout Kick (trigger Blackout Combo) – both builds
    if in_melee and SPELLS.BLACKOUT_KICK:is_learned() then
        if SPELLS.BLACKOUT_KICK:cast_safe(target, "Blackout Kick") then return end
    end

    if use_harmony then
        -- Master of Harmony mid-AoE: Chi Burst → Celestial (2 charges) → Niuzao → BoF → TP(combo) → KS → RJW → EK → KS → RJW → Tiger Palm
        -- 3. Chi Burst (higher priority in Harmony due to Manifestation)
        if SPELLS.CHI_BURST:is_learned() and SPELLS.CHI_BURST:cooldown_up() then
            if SPELLS.CHI_BURST:cast_safe(target, "Chi Burst") then return end
        end
        -- 4. Celestial Brew only if at 2 charges (Aspect of Harmony)
        if menu.use_cooldowns:get_state() and SPELLS.CELESTIAL_BREW:is_learned() and celestial_charges >= 2 then
            if SPELLS.CELESTIAL_BREW:cast_safe(me, "Harmony: Celestial Brew (2 charges)") then return end
        end
        -- 5. Invoke Niuzao
        if menu.use_cooldowns:get_state() and SPELLS.INVOKE_NIUZAO:is_learned() and SPELLS.INVOKE_NIUZAO:cooldown_up() then
            if SPELLS.INVOKE_NIUZAO:cast_safe(me, "CD: Invoke Niuzao") then return end
        end
        -- 6. Breath of Fire
        if in_melee and SPELLS.BREATH_OF_FIRE:is_learned() and SPELLS.BREATH_OF_FIRE:cooldown_up() then
            if SPELLS.BREATH_OF_FIRE:cast_safe(target, "Breath of Fire") then return end
        end
        -- 7. Tiger Palm (consume Blackout Combo)
        if in_melee and SPELLS.TIGER_PALM:is_learned() and has_combo then
            if SPELLS.TIGER_PALM:cast_safe(target, "Tiger Palm (Blackout Combo)") then return end
        end
        -- 8. Keg Smash (one charge)
        if in_melee and SPELLS.KEG_SMASH:is_learned() and keg_charges >= 1 then
            if SPELLS.KEG_SMASH:cast_safe(target, "Keg Smash") then return end
        end
        -- 9. Rushing Jade Wind (before Exploding Keg when both ready)
        if SPELLS.RUSHING_JADE_WIND:is_learned() and SPELLS.RUSHING_JADE_WIND:cooldown_up() then
            if SPELLS.RUSHING_JADE_WIND:cast_safe(me, "Rushing Jade Wind") then return end
        end
        -- 10. Exploding Keg
        if in_melee and SPELLS.EXPLODING_KEG:is_learned() and SPELLS.EXPLODING_KEG:cooldown_up() then
            if SPELLS.EXPLODING_KEG:cast_safe(target, "Exploding Keg") then return end
        end
        -- 11. Second charge of Keg Smash
        if in_melee and SPELLS.KEG_SMASH:is_learned() and keg_charges >= 1 then
            if SPELLS.KEG_SMASH:cast_safe(target, "Keg Smash (2nd)") then return end
        end
        -- 12. Rushing Jade Wind
        if SPELLS.RUSHING_JADE_WIND:is_learned() and SPELLS.RUSHING_JADE_WIND:cooldown_up() then
            if SPELLS.RUSHING_JADE_WIND:cast_safe(me, "Rushing Jade Wind") then return end
        end
        -- 13. Smart AoE: SCK when 5+ (Harmony usually TP filler)
        if enemies_near >= AOE_HIGH_TARGETS and in_melee and SPELLS.SPINNING_CRANE:is_learned() then
            if SPELLS.SPINNING_CRANE:cast_safe(target, "Smart AoE: Spinning Crane Kick") then return end
        end
        -- 14. Tiger Palm filler (Harmony: rarely/never SCK, use Tiger Palm for Harmonic Surge)
        if in_melee and SPELLS.TIGER_PALM:is_learned() then
            if SPELLS.TIGER_PALM:cast_safe(target, "Tiger Palm") then return end
        end
    else
        -- Shado-Pan mid-AoE: Niuzao → BoF → TP(combo) → KS → Chi Burst → RJW → EK → KS → RJW → SCK
        -- 3. Invoke Niuzao
        if menu.use_cooldowns:get_state() and SPELLS.INVOKE_NIUZAO:is_learned() and SPELLS.INVOKE_NIUZAO:cooldown_up() then
            if SPELLS.INVOKE_NIUZAO:cast_safe(me, "CD: Invoke Niuzao") then return end
        end
        -- 4. Breath of Fire
        if in_melee and SPELLS.BREATH_OF_FIRE:is_learned() and SPELLS.BREATH_OF_FIRE:cooldown_up() then
            if SPELLS.BREATH_OF_FIRE:cast_safe(target, "Breath of Fire") then return end
        end
        -- 5. Tiger Palm (consume Blackout Combo)
        if in_melee and SPELLS.TIGER_PALM:is_learned() and has_combo then
            if SPELLS.TIGER_PALM:cast_safe(target, "Tiger Palm (Blackout Combo)") then return end
        end
        -- 6. Keg Smash (one charge)
        if in_melee and SPELLS.KEG_SMASH:is_learned() and keg_charges >= 1 then
            if SPELLS.KEG_SMASH:cast_safe(target, "Keg Smash") then return end
        end
        -- 6b. Smart AoE: SCK when 5+ enemies (swap priority)
        if enemies_near >= AOE_HIGH_TARGETS and in_melee and SPELLS.SPINNING_CRANE:is_learned() then
            if SPELLS.SPINNING_CRANE:cast_safe(target, "Smart AoE: Spinning Crane Kick") then return end
        end
        -- 7. Chi Burst
        if SPELLS.CHI_BURST:is_learned() and SPELLS.CHI_BURST:cooldown_up() then
            if SPELLS.CHI_BURST:cast_safe(target, "Chi Burst") then return end
        end
        -- 8. Rushing Jade Wind (before Exploding Keg when both ready)
        if SPELLS.RUSHING_JADE_WIND:is_learned() and SPELLS.RUSHING_JADE_WIND:cooldown_up() then
            if SPELLS.RUSHING_JADE_WIND:cast_safe(me, "Rushing Jade Wind") then return end
        end
        -- 9. Exploding Keg
        if in_melee and SPELLS.EXPLODING_KEG:is_learned() and SPELLS.EXPLODING_KEG:cooldown_up() then
            if SPELLS.EXPLODING_KEG:cast_safe(target, "Exploding Keg") then return end
        end
        -- 10. Second charge of Keg Smash
        if in_melee and SPELLS.KEG_SMASH:is_learned() and keg_charges >= 1 then
            if SPELLS.KEG_SMASH:cast_safe(target, "Keg Smash (2nd)") then return end
        end
        -- 11. Rushing Jade Wind
        if SPELLS.RUSHING_JADE_WIND:is_learned() and SPELLS.RUSHING_JADE_WIND:cooldown_up() then
            if SPELLS.RUSHING_JADE_WIND:cast_safe(me, "Rushing Jade Wind") then return end
        end
        -- 12. Spinning Crane Kick (filler)
        if in_melee and SPELLS.SPINNING_CRANE:is_learned() then
            if SPELLS.SPINNING_CRANE:cast_safe(target, "Spinning Crane Kick") then return end
        end
        -- Fallback: Tiger Palm without combo
        if in_melee and SPELLS.TIGER_PALM:is_learned() then
            if SPELLS.TIGER_PALM:cast_safe(target, "Tiger Palm") then return end
        end
    end
end)
