--[[
    HCS Frost Mage (Mythic+) — IZI SDK
    Author: HCS
    Build: Spellsinger Mythic+/AoE (Wowhead)
    — Splintering Sorcery, Augury Abounds, Controlled Instincts, Splinterstorm.
    — Blizzard enables Splinter splash; Frozen Orb / Icy Veins / Shifting Power generate Splinters.
    M+ utilities: cooldowns, defensives, interrupt, dispel curses, auto/manual targeting.
]]

-- Import libraries
local izi = require("common/izi_sdk")
local enums = require("common/enums")
local key_helper = require("common/utility/key_helper")
local control_panel_helper = require("common/utility/control_panel_helper")
local spell_queue = require("common/modules/spell_queue")
local spell_prediction = require("common/modules/spell_prediction")
local spell_helper = require("common/utility/spell_helper")
local ok_mplus, mplus_s3 = pcall(require, "shared/mplus_s3_interrupt_stun_list")
local ok_cc, class_colors = pcall(require, "shared/hcs_class_colors")
local function hcs_header(cls, title) return (ok_cc and class_colors and class_colors.hcs_header and class_colors.hcs_header(cls, title)) or title end
local ok_tp, hcs_target_priority = pcall(require, "shared/hcs_target_priority")

local BLIZZARD_ID = 190356
local BLIZZARD_RANGE = 40
local BLIZZARD_RADIUS = 10
local BLIZZARD_CAST_TIME = 0

local buffs = enums.buff_db
local AOE_RADIUS = 8
local AOE_BLIZZARD_MIN = 2   -- Cast Blizzard at this many or more targets
local KICK_RANGE = 40        -- Counterspell range
local DISPEL_RANGE = 40      -- Remove Curse range (party/self)
local ICE_BLOCK_HP = 25      -- Use Ice Block below this HP %
local ALTER_TIME_HP = 45     -- Use Alter Time below this HP %
local POTION_HP = 35         -- Use health potion below this HP %
local TRINKET_SLOT_1 = 13   -- First trinket slot
local TRINKET_SLOT_2 = 14   -- Second trinket slot
local TAG = "hcs_frost_mage_"

-- Define Spells
local SPELLS = {
    FROSTBOLT    = izi.spell(116),
    ICE_LANCE    = izi.spell(30455),
    FLURRY       = izi.spell(44614),   -- Brain Freeze consumer, applies Winter's Chill
    FROZEN_ORB   = izi.spell(84714),   -- Major AoE / proc generator
    BLIZZARD     = izi.spell(190356),  -- AoE channel
    ICY_VEINS    = izi.spell(12472),   -- Major CD
    COMET_STORM  = izi.spell(153595),  -- AoE talent
    SHIFTING_POWER = izi.spell(382440), -- Spellsinger: channel, CDR + 8 Splinters (Shifting Shards)
    FROST_NOVA   = izi.spell(122),     -- Root (utility)
    ICE_BARRIER  = izi.spell(11426),   -- Defensive
    ICE_BLOCK    = izi.spell(45438),   -- Defensive
    ALTER_TIME   = izi.spell(108978),  -- Defensive
    COUNTERSPELL = izi.spell(2139),    -- Interrupt (M+)
    SPELLSTEAL   = izi.spell(30449),   -- Steal magic buffs (M+)
    REMOVE_CURSE = izi.spell(475),     -- Dispel curses (party/self)
}

-- Menu System
local menu = {
    root              = core.menu.tree_node(),
    enabled           = core.menu.checkbox(false, TAG .. "enabled"),
    toggle_key        = core.menu.keybind(999, false, TAG .. "toggle"),
    interrupt         = core.menu.checkbox(true, TAG .. "interrupt"),
    mplus_s3_list     = core.menu.checkbox(false, TAG .. "mplus_s3_list"),
    use_cooldowns     = core.menu.checkbox(true, TAG .. "use_cds"),     -- Icy Veins + Shifting Power
    use_defensives    = core.menu.checkbox(true, TAG .. "use_def"),     -- Ice Block, Alter Time, health potion
    use_spellsteal    = core.menu.checkbox(true, TAG .. "spellsteal"),
    targeting_mode    = core.menu.combobox(1, TAG .. "targeting_mode"),  -- 1=Manual, 2=Casters first, 3=Skull first
    use_dispel_curse  = core.menu.checkbox(true, TAG .. "dispel_curse"),
    cooldowns_node    = core.menu.tree_node(),
    trinket1_boss     = core.menu.checkbox(false, TAG .. "trinket1_boss"),
    trinket1_cd       = core.menu.checkbox(true, TAG .. "trinket1_cd"),
    trinket2_boss     = core.menu.checkbox(false, TAG .. "trinket2_boss"),
    trinket2_cd       = core.menu.checkbox(true, TAG .. "trinket2_cd"),
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
    menu.root:render(hcs_header("MAGE", "HCS Frost Mage (M+)"), function()
        menu.enabled:render("Enable Plugin")

        if not menu.enabled:get_state() then return end

        menu.toggle_key:render("Toggle Rotation")
        menu.interrupt:render("Interrupt (Counterspell)")
        menu.mplus_s3_list:render("M+ S3 list only (kick/stop listed casts)")
        menu.cooldowns_node:render("Cooldowns", function()
            menu.use_cooldowns:render("Use Icy Veins + Shifting Power")
            menu.trinket1_boss:render("Trinket 1: Use on boss only")
            menu.trinket1_cd:render("Trinket 1: Use on cooldown")
            menu.trinket2_boss:render("Trinket 2: Use on boss only")
            menu.trinket2_cd:render("Trinket 2: Use on cooldown")
        end)
        menu.use_defensives:render("Use defensives + health potion")
        menu.use_spellsteal:render("Spellsteal stealable buffs")
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
        name = string.format("[HCS Frost Mage] Enabled (%s)", key_helper:get_key_name(menu.toggle_key:get_key_code())),
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

    -- Cooldowns (M+): Icy Veins (Augury Abounds = 8 Splinters), then Shifting Power when in AoE (Shifting Shards = 8 Splinters + CDR)
    if menu.use_cooldowns:get_state() and #targets > 0 then
        if SPELLS.ICY_VEINS:is_learned() and SPELLS.ICY_VEINS:cooldown_up() and not me:buff_up(buffs.ICY_VEINS) then
            if SPELLS.ICY_VEINS:cast_safe(me, "CD: Icy Veins") then return end
        end
        -- Shifting Power: use when 2+ targets, not channeling, and no procs to dump (avoid wasting Brain Freeze/FoF during channel)
        if #targets >= AOE_BLIZZARD_MIN and not me:is_channeling_or_casting() then
            local has_procs = me:buff_up(buffs.BRAIN_FREEZE) or me:buff_up(buffs.FINGERS_OF_FROST)
            if SPELLS.SHIFTING_POWER:is_learned() and SPELLS.SHIFTING_POWER:cooldown_up() and not has_procs then
                if SPELLS.SHIFTING_POWER:cast_safe(me, "CD: Shifting Power (Spellsinger)", { skip_moving = true }) then return end
            end
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

    -- Interrupt phase (M+): only kick enemies already in combat
    if menu.interrupt:get_state() and SPELLS.COUNTERSPELL:is_learned() then
        local use_list = ok_mplus and mplus_s3 and menu.mplus_s3_list:get_state()
        local function should_kick(enemy)
            if not (enemy and enemy.is_valid and enemy:is_valid()) then return false end
            if not enemy:is_in_combat() then return false end
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

        -- Basic Validations
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

        -- AoE Logic (Spellsinger: Blizzard first so Controlled Instincts can splash Frost Splinters onto Blizzard-affected targets)
        local enemies_near = target:get_enemies_in_splash_range_count(AOE_RADIUS)
        if enemies_near >= AOE_BLIZZARD_MIN then
            -- Blizzard at target's feet: try New IziSDK cast_position, then raw, then queue (don't return after queue so rotation continues).
            if SPELLS.BLIZZARD:is_learned() and SPELLS.BLIZZARD:cooldown_up() and not me:is_channeling_or_casting() then
                local blizz_pos = target:get_position()
                if blizz_pos then
                    local ok = false
                    if SPELLS.BLIZZARD.cast_position then
                        ok = SPELLS.BLIZZARD:cast_position(blizz_pos, "AoE: Blizzard (Spellsinger splash)", { use_prediction = false })
                    end
                    if not ok and core.input.cast_position_spell then
                        ok = core.input.cast_position_spell(BLIZZARD_ID, blizz_pos)
                    end
                    if ok then return end
                    spell_queue:queue_spell_position(BLIZZARD_ID, blizz_pos, 1, "AoE: Blizzard (Spellsinger splash)")
                end
            end
            -- Frozen Orb (Splintering Orbs = 8 Splinters)
            if SPELLS.FROZEN_ORB:is_learned() and SPELLS.FROZEN_ORB:cooldown_up() then
                if SPELLS.FROZEN_ORB:cast_safe(target, "AoE: Frozen Orb") then return end
            end
            -- Comet Storm (talented)
            if SPELLS.COMET_STORM:is_learned() and SPELLS.COMET_STORM:cooldown_up() then
                if SPELLS.COMET_STORM:cast_safe(target, "AoE: Comet Storm") then return end
            end
        end

        -- Single Target / Cleave priority

        -- 1. Flurry (Brain Freeze) — applies Winter's Chill, then dump Ice Lances
        if me:buff_up(buffs.BRAIN_FREEZE) and SPELLS.FLURRY:is_learned() then
            if SPELLS.FLURRY:cast_safe(target, "Brain Freeze: Flurry", { skip_moving = true }) then
                return
            end
        end

        -- 2. Ice Lance with Fingers of Frost or when target has Winter's Chill
        if SPELLS.ICE_LANCE:is_learned() then
            local use_ice_lance = me:buff_up(buffs.FINGERS_OF_FROST) or target:debuff_up(buffs.WINTERS_CHILL)
            if use_ice_lance then
                if SPELLS.ICE_LANCE:cast_safe(target, "Ice Lance (FoF/Winters Chill)", { skip_moving = true }) then
                    return
                end
            end
        end

        -- 3. Frozen Orb on CD (ST too, for procs)
        if SPELLS.FROZEN_ORB:is_learned() and SPELLS.FROZEN_ORB:cooldown_up() then
            if SPELLS.FROZEN_ORB:cast_safe(target, "Frozen Orb") then return end
        end

        -- 4. Comet Storm on CD (single or cleave)
        if SPELLS.COMET_STORM:is_learned() and SPELLS.COMET_STORM:cooldown_up() then
            if SPELLS.COMET_STORM:cast_safe(target, "Comet Storm") then return end
        end

        -- 5. Filler: Frostbolt
        if SPELLS.FROSTBOLT:is_learned() then
            if SPELLS.FROSTBOLT:cast_safe(target, "Filler: Frostbolt") then
                return
            end
        end

        ::continue::
    end
end)
