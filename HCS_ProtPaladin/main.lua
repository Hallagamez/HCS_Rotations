--[[
    HCS Protection Paladin (IZI SDK)
    Derived from BoundCore log: Avenger's Shield, Judgment, Divine Toll, Hammer of Light,
    Shield of the Righteous, Consecration, Blessed Hammer.
    Fix: Hammer of Light is suppressed for 2s after Divine Toll so the script
    doesn't hang when HoL procs from Divine Toll.
    Builds (Wowhead / Midnight Pre-Patch): Templar (Hammer of Light, Divine Toll) and
    Lightsmith (Holy Armaments instead of Divine Toll; no Hammer of Light).

    Features:
    - Dual Logic: High Key (Survival) vs Low Key (Max DPS); HP-based defensives (AD/DP) only in Survival.
    - Dynamic defensives: Ardent Defender HP%, Divine Protection HP% sliders (Survival mode).
    - Emergency critical HP: LoH/WoG/potion/AD/DP when below critical HP% (pre-target + with-target).
    - Throttle: Hammer of Light suppressed 2s after Divine Toll (avoids proc spam).
]]

local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")

local ok_ui, rotation_settings_ui = pcall(require, "shared/rotation_settings_ui")
local ok_mplus, mplus_s3 = pcall(require, "shared/mplus_s3_interrupt_stun_list")
local ok_cc, class_colors = pcall(require, "shared/hcs_class_colors")
local ok_tp, hcs_target_priority = pcall(require, "shared/hcs_target_priority")
local function hcs_header(cls, title) return (ok_cc and class_colors and class_colors.hcs_header and class_colors.hcs_header(cls, title)) or title end
local ok_tankbuster, tank_buster_list = pcall(require, "shared/mplus_s3_tank_buster_list")

-- Spell IDs from BoundCore log
local AVENGERS_SHIELD_RANGE = 30
local JUDGMENT_RANGE = 30
local DIVINE_TOLL_RANGE = 30
local HOLY_ARMAMENTS_RANGE = 40   -- Lightsmith hero talent
local HAMMER_OF_LIGHT_RANGE = 14
local HAND_OF_RECKONING_RANGE = 30  -- Taunt, pull
local MELEE_RANGE = 8
local KICK_RANGE = 10
local PULL_OPENER_WINDOW_SEC = 3   -- Use Hand of Reckoning + Ardent Defender in first N sec of combat
local AVENGING_WRATH_BUFF_ID = 31884  -- For "Holy Bulwark outside of Avenging Wrath"
local PARTY_BUFF_RANGE = 40   -- Lay on Hands, Blessing of Sacrifice, Blessing of Protection
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14
local TAG = "hcs_prot_pala_"

-- After casting Divine Toll, do not try to cast Hammer of Light for this long (procs handle it).
local DIVINE_TOLL_HOL_SUPPRESS_SEC = 2.0
local last_divine_toll_time = 0

local SPELLS = {
    AVENGERS_SHIELD   = izi.spell(31935),
    JUDGMENT          = izi.spell(275779),
    DIVINE_TOLL       = izi.spell(375576),   -- Templar build
    HOLY_ARMAMENTS    = izi.spell(432459),   -- Lightsmith (Holy Bulwark outside AW)
    HAMMER_OF_LIGHT   = izi.spell(427453),   -- Templar only
    SHIELD_OF_RIGHTEOUS = izi.spell(53600),
    CONSECRATION      = izi.spell(26573),
    BLESSED_HAMMER    = izi.spell(204019),
    HAND_OF_RECKONING = izi.spell(62124),   -- Taunt, pull (if tanking first)
    AVENGING_WRATH    = izi.spell(31884),   -- 2 min CD, use with burst
    HAMMER_OF_JUSTICE = izi.spell(853),   -- Interrupt / stun
    -- Defensives
    GUARDIAN_OF_ANCIENT_KINGS = izi.spell(86659),  -- Major CD, 50% DR
    ARDENT_DEFENDER   = izi.spell(31850),   -- 20% DR + cheat death
    DIVINE_PROTECTION = izi.spell(498),    -- 20% DR, 1 min CD
    -- Player/party saves
    LAY_ON_HANDS       = izi.spell(633),   -- Full heal self (or ally), 10 min CD
    WORD_OF_GLORY      = izi.spell(85673), -- Self-heal, 3 Holy Power, scales with missing HP
    BLESSING_OF_SACRIFICE = izi.spell(6940),  -- Redirect 30% damage to paladin, party
    BLESSING_OF_PROTECTION = izi.spell(1022), -- Physical immunity 10s, party (only helps vs physical)
    CLEANSE_TOXINS         = izi.spell(440013), -- Removes poison and disease, 40 yd, 8 s CD
}

-- Menu (same IDs used by custom UI when rotation_settings_ui is present)
local menu = {
    root             = core.menu.tree_node(),
    enabled          = core.menu.checkbox(false, TAG .. "enabled"),
    toggle_key       = core.menu.keybind(999, false, TAG .. "toggle"),
    interrupt        = core.menu.checkbox(true, TAG .. "interrupt"),
    hold_avengers_shield_for_interrupt = core.menu.checkbox(false, TAG .. "hold_avengers_shield_for_interrupt"),
    mplus_s3_list    = core.menu.checkbox(false, TAG .. "mplus_s3_list"),
    use_cooldowns    = core.menu.checkbox(true, TAG .. "use_cds"),
    use_defensives   = core.menu.checkbox(true, TAG .. "use_def"),
    mplus_s3_tank_buster = core.menu.checkbox(true, TAG .. "mplus_s3_tank_buster"),
    targeting_mode   = core.menu.combobox(1, TAG .. "targeting_mode"),  -- 1=Manual, 2=Casters first, 3=Skull first, 4=Smart
    logic_mode       = core.menu.combobox(1, TAG .. "logic_mode"),  -- 1=High Key (Survival), 2=Low Key (Max DPS)
    right_click_attack = core.menu.checkbox(false, TAG .. "right_click_attack"),  -- Right-click enemy to taunt/attack from range (optional)
    potion_hp        = core.menu.slider_int(0, 100, 35, TAG .. "potion_hp"),
    critical_hp     = core.menu.slider_int(0, 100, 35, TAG .. "critical_hp"),  -- Emergency: LoH/WoG/potion/AD/DP when below this
    lay_on_hands_hp  = core.menu.slider_int(0, 100, 20, TAG .. "lay_on_hands_hp"),
    word_of_glory_hp = core.menu.slider_int(0, 100, 60, TAG .. "word_of_glory_hp"),  -- WoG self-heal below this %
    ardent_defender_hp  = core.menu.slider_int(0, 100, 50, TAG .. "ardent_defender_hp"),   -- Survival: use AD below this %
    divine_protection_hp = core.menu.slider_int(0, 100, 50, TAG .. "divine_protection_hp"), -- Survival: use DP below this %
    blessing_of_sacrifice_hp = core.menu.slider_int(0, 100, 35, TAG .. "blessing_of_sacrifice_hp"),
    blessing_of_protection_hp = core.menu.slider_int(0, 100, 25, TAG .. "blessing_of_protection_hp"),
    bop_physical_only = core.menu.checkbox(true, TAG .. "bop_physical_only"),  -- Only use BoP when physical tank buster is being cast (avoids wasting on magic)
    heal_party       = core.menu.checkbox(false, TAG .. "heal_party"),  -- Use LoH / WoG on low-HP party members (optional, off by default)
    auto_cleanse_toxins = core.menu.checkbox(true, TAG .. "auto_cleanse_toxins"),  -- Cleanse Toxins: poison/disease, self first then party
    build_templar    = core.menu.checkbox(true, TAG .. "build_templar"),   -- Templar hero build (Hammer of Light, Divine Toll)
    build_lightsmith = core.menu.checkbox(false, TAG .. "build_lightsmith"), -- Lightsmith hero build (Holy Armaments)
    build_instrument = core.menu.checkbox(false, TAG .. "build_instrument"), -- Instrument of the Divine: Divine Toll + HoL + Holy Bulwark outside AW + SotR at 5 HP
    pre_pull         = core.menu.checkbox(false, TAG .. "pre_pull"),       -- Consecration + Blessed Hammer before pull (when you have target, not in combat)
    pull_opener      = core.menu.checkbox(false, TAG .. "pull_opener"),    -- Hand of Reckoning + Ardent Defender on pull (tanking first in Raid)
    cooldowns_node   = core.menu.tree_node(),
    trinket1_boss    = core.menu.checkbox(false, TAG .. "trinket1_boss"),
    trinket1_cd      = core.menu.checkbox(true, TAG .. "trinket1_cd"),
    trinket2_boss    = core.menu.checkbox(false, TAG .. "trinket2_boss"),
    trinket2_cd      = core.menu.checkbox(true, TAG .. "trinket2_cd"),
}

-- Custom settings window (Rotation Settings UI library)
local ui
if ok_ui and rotation_settings_ui and type(rotation_settings_ui.new) == "function" then
    ui = rotation_settings_ui.new({
        id = "hcs_prot_pala",
        title = hcs_header("PALADIN", "HCS Protection Paladin"),
        default_x = 700,
        default_y = 200,
        default_w = 520,
        default_h = 650,
        theme = "paladin",
    })
end
if ui then
    -- Core tab: enable keybind + logic mode + build choice
    ui:add_tab({ id = "core", label = "Core" }, function(t)
        if t.keybind_grid then
            t:keybind_grid({
                elements = { menu.toggle_key },
                labels = { "Enable Rotation" },
            })
        end
        if menu.logic_mode and t.combobox_list then
            t:combobox_list({
                label = "Dual Logic",
                elements = { { element = menu.logic_mode, label = "Mode", options = LOGIC_OPTIONS } },
            })
        end
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Hero talent build (pick one)",
                columns = 1,
                elements = {
                    { element = menu.build_templar, label = "Templar (Hammer of Light, Divine Toll)" },
                    { element = menu.build_lightsmith, label = "Lightsmith (Holy Armaments)" },
                    { element = menu.build_instrument, label = "Instrument of the Divine (Divine Toll + HoL + Holy Bulwark outside AW + SotR at 5 HP)" },
                },
            })
        end
    end)
    -- Cooldowns tab
    ui:add_tab({ id = "cooldowns", label = "Cooldowns" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Cooldowns",
                columns = 2,
                elements = {
                    { element = menu.use_cooldowns, label = "Use cooldowns (Divine Toll / Holy Armaments by build)" },
                    { element = menu.trinket1_boss, label = "Trinket 1: Boss only" },
                    { element = menu.trinket1_cd, label = "Trinket 1: On CD" },
                    { element = menu.trinket2_boss, label = "Trinket 2: Boss only" },
                    { element = menu.trinket2_cd, label = "Trinket 2: On CD" },
                },
            })
        end
    end)
    -- Survival tab: defensives + potion HP%
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
                    { element = menu.heal_party, label = "Use LoH / WoG on party (heal low-HP allies)" },
                    { element = menu.auto_cleanse_toxins, label = "Auto Cleanse Toxins (poison/disease, self first then party)" },
                },
            })
        end
        if t.slider_list and menu.potion_hp then
            t:slider_list({
                label = "Thresholds",
                elements = {
                    { element = menu.potion_hp, label = "Potion HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.critical_hp, label = "Emergency HP% (LoH/WoG/potion/AD/DP)", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.lay_on_hands_hp, label = "Lay on Hands (self) HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.word_of_glory_hp, label = "Word of Glory (self-heal) HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.ardent_defender_hp, label = "Ardent Defender HP% (Survival)", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.divine_protection_hp, label = "Divine Protection HP% (Survival)", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.blessing_of_sacrifice_hp, label = "Blessing of Sacrifice (party) HP%", suffix = "%", visible_when = defensives_enabled },
                    { element = menu.blessing_of_protection_hp, label = "Blessing of Protection (party) HP%", suffix = "%", visible_when = defensives_enabled },
                },
            })
        end
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Blessing of Protection",
                columns = 1,
                elements = {
                    { element = menu.bop_physical_only, label = "Only during physical danger (target casting physical buster)" },
                },
            })
        end
    end)
    -- Targeting + Combat tab
    ui:add_tab({ id = "targeting", label = "Targeting" }, function(t)
        if t.checkbox_grid then
            t:checkbox_grid({
                label = "Targeting",
                columns = 1,
                elements = {
                    { element = menu.interrupt, label = "Interrupt (Hammer of Justice)" },
                    { element = menu.hold_avengers_shield_for_interrupt, label = "Hold Avenger's Shield for Interrupts (use only on M+ S3 priority casts)" },
                    { element = menu.mplus_s3_list, label = "M+ S3 list only (kick/stop listed casts)" },
                    { element = menu.right_click_attack, label = "Right-click attack/taunt (range pull)" },
                    { element = menu.pre_pull, label = "Pre-pull: Consecration + Blessed Hammer" },
                    { element = menu.pull_opener, label = "Pull opener: Hand of Reckoning + Ardent Defender (tanking first)" },
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

local LOGIC_OPTIONS = { "High Key (Survival)", "Low Key (Max DPS)" }

local function is_survival_mode()
    local v = (menu.logic_mode and menu.logic_mode.get) and menu.logic_mode:get() or 1
    return v == 1
end

-- True if the unit has poison or disease we can dispel with Cleanse Toxins (uses engine API when available).
local function unit_has_dispelable_toxins(unit)
    if not (unit and unit.is_valid and unit:is_valid()) then return false end
    if unit.dispels_poison and type(unit.dispels_poison) == "function" and unit:dispels_poison() then return true end
    if unit.dispels_disease and type(unit.dispels_disease) == "function" and unit:dispels_disease() then return true end
    return false
end

-- Record when we attempt Divine Toll so Hammer of Light is suppressed during proc spam.
if core and core.register_on_legit_spell_cast_callback and type(core.register_on_legit_spell_cast_callback) == "function" then
    core.register_on_legit_spell_cast_callback(function(data)
        if not data or type(data) ~= "table" then return end
        local sid = data and data.spell_id
        if sid == 375576 then
            if core and core.time and type(core.time) == "function" then
                last_divine_toll_time = core.time()
            end
        end
    end)
end

-- Render Menu
core.register_on_render_menu_callback(function()
    if ui then ui:on_menu_render() end
    menu.root:render(hcs_header("PALADIN", "HCS Protection Paladin"), function()
        menu.enabled:render("Enable Plugin")
        if not menu.enabled:get_state() then return end
        if ui and ui.menu and ui.menu.enable and (not rotation_settings_ui or not rotation_settings_ui.is_stub) then
            ui.menu.enable:render("Show Custom UI Window")
        end
        menu.toggle_key:render("Toggle Rotation")
        if menu.logic_mode then menu.logic_mode:render("Logic mode", LOGIC_OPTIONS, "High Key = Survival priority. Low Key = Max DPS.") end
        menu.build_templar:render("Build: Templar (Hammer of Light, Divine Toll)")
        menu.build_lightsmith:render("Build: Lightsmith (Holy Armaments)")
        menu.build_instrument:render("Build: Instrument of the Divine (Divine Toll + HoL + Holy Bulwark outside AW + SotR at 5 HP)")
        menu.pre_pull:render("Pre-pull: Consecration + Blessed Hammer (when you have target, not in combat)")
        menu.pull_opener:render("Pull opener: Hand of Reckoning + Ardent Defender (tanking first in Raid)")
        menu.interrupt:render("Interrupt (Hammer of Justice)")
        menu.hold_avengers_shield_for_interrupt:render("Hold Avenger's Shield for Interrupts (M+ S3 list)")
        menu.mplus_s3_list:render("M+ S3 list only (kick/stop listed casts)")
        menu.right_click_attack:render("Right-click attack/taunt (Hand of Reckoning / Avenger's Shield / Judgment)")
        menu.cooldowns_node:render("Cooldowns", function()
            menu.use_cooldowns:render("Use Divine Toll + cooldowns")
            menu.trinket1_boss:render("Trinket 1: Use on boss only")
            menu.trinket1_cd:render("Trinket 1: Use on cooldown")
            menu.trinket2_boss:render("Trinket 2: Use on boss only")
            menu.trinket2_cd:render("Trinket 2: Use on cooldown")
        end)
        menu.use_defensives:render("Use defensives + health potion")
        menu.mplus_s3_tank_buster:render("Use defensives on M+ S3 tank busters")
        menu.heal_party:render("Use LoH / WoG on party (heal low-HP allies)")
        if menu.potion_hp then menu.potion_hp:render("Potion HP%") end
        if menu.critical_hp then menu.critical_hp:render("Emergency HP% (LoH/WoG/potion/AD/DP)") end
        if menu.lay_on_hands_hp then menu.lay_on_hands_hp:render("Lay on Hands (self) HP%") end
        if menu.word_of_glory_hp then menu.word_of_glory_hp:render("Word of Glory (self-heal) HP%") end
        if menu.ardent_defender_hp then menu.ardent_defender_hp:render("Ardent Defender HP% (Survival)") end
        if menu.divine_protection_hp then menu.divine_protection_hp:render("Divine Protection HP% (Survival)") end
        if menu.blessing_of_sacrifice_hp then menu.blessing_of_sacrifice_hp:render("Blessing of Sacrifice (party) HP%") end
        if menu.blessing_of_protection_hp then menu.blessing_of_protection_hp:render("Blessing of Protection (party) HP%") end
        menu.bop_physical_only:render("BoP only during physical danger")
        menu.auto_cleanse_toxins:render("Auto Cleanse Toxins (poison/disease, self first then party)")
        if menu.targeting_mode and (ok_tp and hcs_target_priority and hcs_target_priority.TARGETING_OPTIONS) then
            menu.targeting_mode:render("Targeting mode", hcs_target_priority.TARGETING_OPTIONS, "Manual = current target only. Auto modes: Casters/Skull = simple priority. Smart = threat (tanking) > low HP (execute) > casters > Skull.")
        end
    end)
end)

-- Draw custom settings window when enabled (Rotation Settings UI)
core.register_on_render_callback(function()
    if ui then ui:on_render() end
end)

-- Control Panel
core.register_on_render_control_panel_callback(function()
    local cp_elements = {}
    if not menu.enabled:get_state() then return cp_elements end
    control_panel_helper:insert_toggle(cp_elements, {
        name = string.format("[HCS Prot Paladin] Enabled (%s)", key_helper:get_key_name(menu.toggle_key:get_key_code())),
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
                    -- Priority: Hand of Reckoning (taunt, 30 yd) > Avenger's Shield (30 yd) > Judgment (30 yd)
                    if dist <= HAND_OF_RECKONING_RANGE and SPELLS.HAND_OF_RECKONING:is_learned() and SPELLS.HAND_OF_RECKONING:cooldown_up() then
                        if SPELLS.HAND_OF_RECKONING:cast_safe(mouse_over, "Right-click: Hand of Reckoning (taunt)") then return end
                    elseif dist <= AVENGERS_SHIELD_RANGE and SPELLS.AVENGERS_SHIELD:is_learned() and SPELLS.AVENGERS_SHIELD:cooldown_up() then
                        if SPELLS.AVENGERS_SHIELD:cast_safe(mouse_over, "Right-click: Avenger's Shield") then return end
                    elseif dist <= JUDGMENT_RANGE and SPELLS.JUDGMENT:is_learned() then
                        if SPELLS.JUDGMENT:cast_safe(mouse_over, "Right-click: Judgment") then return end
                    end
                end
            end
        end
    end

    if not rotation_enabled() then return end

    -- Self-heals and optional party heals (LoH / WoG) when below sliders (work with no target, e.g. between pulls)
    if menu.use_defensives:get_state() then
        local my_hp = me:get_health_percentage()
        local crit_pct = (menu.critical_hp and menu.critical_hp.get and menu.critical_hp:get()) or 35
        local loh_pct = (menu.lay_on_hands_hp and menu.lay_on_hands_hp.get and menu.lay_on_hands_hp:get()) or 20
        local wog_pct = (menu.word_of_glory_hp and menu.word_of_glory_hp.get and menu.word_of_glory_hp:get()) or 60

        -- Emergency (critical HP): LoH first, then WoG, then potion
        if my_hp < crit_pct then
            if SPELLS.LAY_ON_HANDS:is_learned() and SPELLS.LAY_ON_HANDS:cooldown_up() then
                if SPELLS.LAY_ON_HANDS:cast_safe(me, "Emergency: Lay on Hands (self)") then return end
            end
            if SPELLS.WORD_OF_GLORY:is_learned() then
                local hp = (me.holy_power_current and me:holy_power_current()) or 0
                if hp >= 3 and SPELLS.WORD_OF_GLORY:cast_safe(me, "Emergency: Word of Glory (self)") then return end
            end
            if izi.use_best_health_potion_safe and izi.use_best_health_potion_safe() then return end
        end

        -- Self: Lay on Hands (when below slider, not already handled by emergency)
        if my_hp < loh_pct and my_hp >= crit_pct and SPELLS.LAY_ON_HANDS:is_learned() and SPELLS.LAY_ON_HANDS:cooldown_up() then
            if SPELLS.LAY_ON_HANDS:cast_safe(me, "Save: Lay on Hands (self)") then return end
        end
        -- Self: Word of Glory (when below slider, not already handled by emergency)
        if my_hp < wog_pct and my_hp >= crit_pct and SPELLS.WORD_OF_GLORY:is_learned() then
            local hp = (me.holy_power_current and me:holy_power_current()) or 0
            if hp >= 3 and SPELLS.WORD_OF_GLORY:cast_safe(me, "Defensive: Word of Glory (self-heal)") then
                return
            end
        end

        -- Optional: LoH / WoG on low-HP party members (same sliders; excludes self)
        if menu.heal_party:get_state() and me.get_party_members_in_range then
            local party = me:get_party_members_in_range(PARTY_BUFF_RANGE, true)
            local lowest_loh, lowest_loh_hp = nil, 101
            local lowest_wog, lowest_wog_hp = nil, 101
            for i = 1, #party do
                local ally = party[i]
                if ally and ally ~= me and ally.is_valid and ally:is_valid() and not (ally.is_dead and ally:is_dead()) then
                    local ahp = (ally.get_health_percentage and ally:get_health_percentage()) or 100
                    if ahp < loh_pct and ahp < lowest_loh_hp then lowest_loh_hp = ahp; lowest_loh = ally end
                    if ahp < wog_pct and ahp < lowest_wog_hp then lowest_wog_hp = ahp; lowest_wog = ally end
                end
            end
            if lowest_loh and SPELLS.LAY_ON_HANDS:is_learned() and SPELLS.LAY_ON_HANDS:cooldown_up() then
                if SPELLS.LAY_ON_HANDS:cast_safe(lowest_loh, "Save: Lay on Hands (party)") then return end
            end
            if lowest_wog and SPELLS.WORD_OF_GLORY:is_learned() then
                local hp = (me.holy_power_current and me:holy_power_current()) or 0
                if hp >= 3 and SPELLS.WORD_OF_GLORY:cast_safe(lowest_wog, "Defensive: Word of Glory (party)") then
                    return
                end
            end
        end
    end

    -- Auto Cleanse Toxins: poison/disease, self first then party in range (works with no target)
    if menu.auto_cleanse_toxins:get_state() and SPELLS.CLEANSE_TOXINS:is_learned() and SPELLS.CLEANSE_TOXINS:cooldown_up() then
        if unit_has_dispelable_toxins(me) then
            if SPELLS.CLEANSE_TOXINS:cast_safe(me, "Dispel: Cleanse Toxins (self)") then return end
        end
        if me.get_party_members_in_range then
            local party = me:get_party_members_in_range(PARTY_BUFF_RANGE, true)
            for p = 1, #party do
                local ally = party[p]
                if unit_has_dispelable_toxins(ally) then
                    if SPELLS.CLEANSE_TOXINS:cast_safe(ally, "Dispel: Cleanse Toxins (party)") then return end
                end
            end
        end
    end

    local targets
    local tm = (menu.targeting_mode and menu.targeting_mode.get) and menu.targeting_mode:get() or 1
    if tm == 1 then
        -- Manual: current target only
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

    -- Pre-pull: Consecration + Blessed Hammer before pull (when you have target, not in combat)
    if not me:affecting_combat() and menu.pre_pull:get_state() then
        if SPELLS.CONSECRATION:is_learned() and SPELLS.CONSECRATION:cooldown_up() then
            if SPELLS.CONSECRATION:cast_safe(target, "Pre-pull: Consecration") then return end
        end
        if in_melee and SPELLS.BLESSED_HAMMER:is_learned() and SPELLS.BLESSED_HAMMER:cooldown_up() then
            if SPELLS.BLESSED_HAMMER:cast_safe(target, "Pre-pull: Blessed Hammer") then return end
        end
        return
    end

    -- Defensives: M+ S3 tank buster reaction first, then potion, then low-HP CDs
    if menu.use_defensives:get_state() then
        local my_hp = me:get_health_percentage()

        -- M+ S3 tank busters: use a CD when current target is casting a known huge hit (GoAK > Ardent Defender > Divine Protection)
        if menu.mplus_s3_tank_buster:get_state() and ok_tankbuster and tank_buster_list and tank_buster_list.is_casting_tank_buster(target) then
            if SPELLS.GUARDIAN_OF_ANCIENT_KINGS:is_learned() and SPELLS.GUARDIAN_OF_ANCIENT_KINGS:cooldown_up() then
                if SPELLS.GUARDIAN_OF_ANCIENT_KINGS:cast_safe(me, "Tank buster: Guardian of Ancient Kings") then return end
            end
            if SPELLS.ARDENT_DEFENDER:is_learned() and SPELLS.ARDENT_DEFENDER:cooldown_up() then
                if SPELLS.ARDENT_DEFENDER:cast_safe(me, "Tank buster: Ardent Defender") then return end
            end
            if SPELLS.DIVINE_PROTECTION:is_learned() and SPELLS.DIVINE_PROTECTION:cooldown_up() then
                if SPELLS.DIVINE_PROTECTION:cast_safe(me, "Tank buster: Divine Protection") then return end
            end
        end

        -- Blessing of Sacrifice on lowest-HP party member below slider (excludes self)
        local bos_pct = (menu.blessing_of_sacrifice_hp and menu.blessing_of_sacrifice_hp.get and menu.blessing_of_sacrifice_hp:get()) or 35
        if SPELLS.BLESSING_OF_SACRIFICE:is_learned() and SPELLS.BLESSING_OF_SACRIFICE:cooldown_up() and me.get_party_members_in_range then
            local party = me:get_party_members_in_range(PARTY_BUFF_RANGE, true)
            local lowest, lowest_hp = nil, 101
            for i = 1, #party do
                local ally = party[i]
                if ally and ally.is_valid and ally:is_valid() and ally ~= me then
                    local hp = (ally.get_health_percentage and ally:get_health_percentage()) or 100
                    if hp < bos_pct and hp < lowest_hp then lowest_hp = hp; lowest = ally end
                end
            end
            if lowest and SPELLS.BLESSING_OF_SACRIFICE:cast_safe(lowest, "Save: Blessing of Sacrifice") then return end
        end

        -- Blessing of Protection on lowest-HP party member below slider; only when it helps (physical danger) if option on
        local bop_pct = (menu.blessing_of_protection_hp and menu.blessing_of_protection_hp.get and menu.blessing_of_protection_hp:get()) or 25
        local bop_ok = true
        if menu.bop_physical_only:get_state() and ok_tankbuster and tank_buster_list and target and target.get_active_cast_or_channel_id then
            local cast_id = target:get_active_cast_or_channel_id()
            bop_ok = tank_buster_list.is_physical_tank_buster and tank_buster_list.is_physical_tank_buster(cast_id)
        end
        if bop_ok and SPELLS.BLESSING_OF_PROTECTION:is_learned() and SPELLS.BLESSING_OF_PROTECTION:cooldown_up() and me.get_party_members_in_range then
            local party = me:get_party_members_in_range(PARTY_BUFF_RANGE, true)
            local lowest, lowest_hp = nil, 101
            for i = 1, #party do
                local ally = party[i]
                if ally and ally.is_valid and ally:is_valid() and ally ~= me then
                    local hp = (ally.get_health_percentage and ally:get_health_percentage()) or 100
                    if hp < bop_pct and hp < lowest_hp then lowest_hp = hp; lowest = ally end
                end
            end
            if lowest and SPELLS.BLESSING_OF_PROTECTION:cast_safe(lowest, "Save: Blessing of Protection") then return end
        end

        local threshold = (menu.potion_hp and menu.potion_hp.get and menu.potion_hp:get()) or 35
        if my_hp < threshold and izi.use_best_health_potion_safe and izi.use_best_health_potion_safe() then
            return
        end
        -- Dynamic defensives (Survival mode only): emergency (critical HP) then by slider
        if is_survival_mode() then
            local crit_pct = (menu.critical_hp and menu.critical_hp.get and menu.critical_hp:get()) or 35
            local ad_hp = (menu.ardent_defender_hp and menu.ardent_defender_hp.get and menu.ardent_defender_hp:get()) or 50
            local dp_hp = (menu.divine_protection_hp and menu.divine_protection_hp.get and menu.divine_protection_hp:get()) or 50
            -- Emergency: below critical use both AD and DP
            if my_hp < crit_pct then
                if SPELLS.ARDENT_DEFENDER:is_learned() and SPELLS.ARDENT_DEFENDER:cooldown_up() then
                    if SPELLS.ARDENT_DEFENDER:cast_safe(me, "Emergency: Ardent Defender") then return end
                end
                if SPELLS.DIVINE_PROTECTION:is_learned() and SPELLS.DIVINE_PROTECTION:cooldown_up() then
                    if SPELLS.DIVINE_PROTECTION:cast_safe(me, "Emergency: Divine Protection") then return end
                end
            end
            -- By slider: Ardent Defender, Divine Protection
            if my_hp < ad_hp and SPELLS.ARDENT_DEFENDER:is_learned() and SPELLS.ARDENT_DEFENDER:cooldown_up() then
                if SPELLS.ARDENT_DEFENDER:cast_safe(me, "Defensive: Ardent Defender") then return end
            end
            if my_hp < dp_hp and SPELLS.DIVINE_PROTECTION:is_learned() and SPELLS.DIVINE_PROTECTION:cooldown_up() then
                if SPELLS.DIVINE_PROTECTION:cast_safe(me, "Defensive: Divine Protection") then return end
            end
        end
    end

    if not me:affecting_combat() then return end

    local is_lightsmith = menu.build_lightsmith:get_state()
    local is_templar = menu.build_templar:get_state()
    local is_instrument = menu.build_instrument:get_state()
    -- Instrument of the Divine > Lightsmith > Templar. Default to Templar when none chosen.
    local use_instrument = is_instrument
    local use_lightsmith = not use_instrument and is_lightsmith
    local use_templar = not use_instrument and (is_templar or (not is_lightsmith and not is_templar))

    local time_in_combat = (me.time_in_combat and me:time_in_combat()) or 0
    -- Pull opener (if tanking first in Raid): Hand of Reckoning, then Ardent Defender
    if menu.pull_opener:get_state() and time_in_combat < PULL_OPENER_WINDOW_SEC then
        if range <= HAND_OF_RECKONING_RANGE and SPELLS.HAND_OF_RECKONING:is_learned() and SPELLS.HAND_OF_RECKONING:cooldown_up() then
            if SPELLS.HAND_OF_RECKONING:cast_safe(target, "Pull: Hand of Reckoning") then return end
        end
        if SPELLS.ARDENT_DEFENDER:is_learned() and SPELLS.ARDENT_DEFENDER:cooldown_up() then
            if SPELLS.ARDENT_DEFENDER:cast_safe(me, "Pull: Ardent Defender") then return end
        end
    end

    -- Rotation order: Avenger's Shield -> Avenging Wrath -> Divine Toll / Holy Armaments -> HoL -> SotR -> Judgment -> Blessed Hammer -> Consecration (filler)
    -- When "Hold Avenger's Shield for Interrupts" is on, skip AS here; it is used only in the interrupt section for M+ S3 priority casts.

    local hold_as_for_interrupt = menu.hold_avengers_shield_for_interrupt:get_state()
    if not hold_as_for_interrupt and range <= AVENGERS_SHIELD_RANGE and SPELLS.AVENGERS_SHIELD:is_learned() and SPELLS.AVENGERS_SHIELD:cooldown_up() then
        if SPELLS.AVENGERS_SHIELD:cast_safe(target, "Avenger's Shield") then return end
    end

    if menu.use_cooldowns:get_state() then
        if SPELLS.AVENGING_WRATH:is_learned() and SPELLS.AVENGING_WRATH:cooldown_up() then
            if SPELLS.AVENGING_WRATH:cast_safe(me, "CD: Avenging Wrath") then return end
        end
        if (use_templar or use_instrument) and SPELLS.DIVINE_TOLL:is_learned() and SPELLS.DIVINE_TOLL:cooldown_up() and range <= DIVINE_TOLL_RANGE then
            if SPELLS.DIVINE_TOLL:cast_safe(target, "CD: Divine Toll") then
                if core and core.time and type(core.time) == "function" then
                    last_divine_toll_time = core.time()
                end
                return
            end
        end
        -- Lightsmith / Instrument of the Divine: Holy Bulwark outside of Avenging Wrath
        local has_aw = (me.buff_up and me:buff_up(AVENGING_WRATH_BUFF_ID)) or false
        if (use_lightsmith or use_instrument) and not has_aw and SPELLS.HOLY_ARMAMENTS:is_learned() and SPELLS.HOLY_ARMAMENTS:cooldown_up() then
            if SPELLS.HOLY_ARMAMENTS:cast_safe(me, "CD: Holy Armaments / Holy Bulwark (outside AW)") then
                return
            end
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

    -- Interrupt: when "Hold Avenger's Shield for Interrupts" is on, use AS only for M+ S3 priority casts (30 yd); HoJ follows "M+ S3 list only" separately.
    if menu.interrupt:get_state() and (target:is_casting() or target:is_channeling_or_casting()) and target.is_active_spell_interruptable and target:is_active_spell_interruptable() then
        local use_list_for_kick = ok_mplus and mplus_s3 and menu.mplus_s3_list:get_state()
        local should_kick_this = not use_list_for_kick or (mplus_s3 and mplus_s3.should_kick_unit(target, true))
        if not should_kick_this then goto after_interrupt end
        -- Avenger's Shield only when holding for interrupts AND this cast is on the M+ S3 priority list (range 30).
        if hold_as_for_interrupt and ok_mplus and mplus_s3 and mplus_s3.should_kick_unit(target, true) then
            if range <= AVENGERS_SHIELD_RANGE and SPELLS.AVENGERS_SHIELD:is_learned() and SPELLS.AVENGERS_SHIELD:cooldown_up() then
                if SPELLS.AVENGERS_SHIELD:cast_safe(target, "Interrupt: Avenger's Shield (M+ S3 priority)") then return end
            end
        end
        -- Hammer of Justice (melee range, stun/interrupt) - only on non-boss (bosses are immune to stuns)
        local is_boss = (target.is_boss and target:is_boss()) and true or false
        if not is_boss and SPELLS.HAMMER_OF_JUSTICE:is_learned() and range <= KICK_RANGE then
            if SPELLS.HAMMER_OF_JUSTICE:cast_safe(target, "Interrupt: Hammer of Justice") then return end
        end
        ::after_interrupt::
    end

    -- Consecration: use whenever off CD and in melee (maintain ground for threat/damage)
    if in_melee and SPELLS.CONSECRATION:is_learned() and SPELLS.CONSECRATION:cooldown_up() then
        if SPELLS.CONSECRATION:cast_safe(target, "Consecration") then return end
    end

    -- Rotation (continued): Hammer of Light -> SotR at 5 HP (Instrument of the Divine) -> SotR -> Judgment -> Blessed Hammer
    if (use_templar or use_instrument) and range <= HAMMER_OF_LIGHT_RANGE and SPELLS.HAMMER_OF_LIGHT:is_learned() then
        local now_ok = core and core.time and type(core.time) == "function"
        if (not now_ok) or (core.time() - last_divine_toll_time >= DIVINE_TOLL_HOL_SUPPRESS_SEC) then
            if SPELLS.HAMMER_OF_LIGHT:cast_safe(target, "Hammer of Light") then return end
        end
    end

    -- Instrument of the Divine: Shield of the Righteous at 5 Holy Power
    local holy_power = (me.holy_power_current and me:holy_power_current()) or 0
    if use_instrument and holy_power >= 5 and in_melee and SPELLS.SHIELD_OF_RIGHTEOUS:is_learned() then
        if SPELLS.SHIELD_OF_RIGHTEOUS:cast_safe(target, "Shield of the Righteous (5 HP, Instrument of the Divine)") then return end
    end

    if in_melee and SPELLS.SHIELD_OF_RIGHTEOUS:is_learned() then
        if SPELLS.SHIELD_OF_RIGHTEOUS:cast_safe(target, "Shield of the Righteous") then return end
    end

    if range <= JUDGMENT_RANGE and SPELLS.JUDGMENT:is_learned() then
        if SPELLS.JUDGMENT:cast_safe(target, "Judgment") then return end
    end

    if in_melee and SPELLS.BLESSED_HAMMER:is_learned() then
        if SPELLS.BLESSED_HAMMER:cast_safe(target, "Blessed Hammer") then return end
    end
end)
