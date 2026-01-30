# HCS Rotations for Project Sylvanas

High-quality, open-source Mythic+ rotation scripts for World of Warcraft using the Project Sylvanas IZI SDK. Each rotation is **self-contained** — copy one folder and go.

## About the Project

HCS Rotations provides optimized rotation scripts designed for Mythic+ content. All rotations include smart targeting, M+ interrupt/stun lists, tank buster reactions (for tanks), defensives, and a custom settings UI. The goal is to deliver **Mythic+ rotations for all specs** — more classes and specs are planned as development continues.

---

## Quick Start

1. **Pick a rotation** from the list below  
2. **Download** the `HCS_*` folder (or clone this repo)  
3. **Copy** the folder into your Project Sylvanas `scripts/` directory  
4. **Reload** scripts or restart Project Sylvanas  

No shared folders, no extra setup. Each rotation works standalone.

---

## Rotations

### Tanks

| Rotation | Builds | Highlights |
|----------|--------|------------|
| **HCS_ProtPaladin** | Templar, Lightsmith | Avenger's Shield, Judgment, Divine Toll, Hammer of Light. Dual logic (Survival vs Max DPS). Lay on Hands, Blessing of Sacrifice/Protection. M+ S3 tank busters. |
| **HCS_Monk_Brew** | Shado-Pan, Master of Harmony | Smart Stagger (auto Purifying Brew). Dual logic, burst sync (WoO + Niuzao). Energy anti-cap, emergency Vivify. Tiger's Lust dispel. |
| **HCS_VengDH** | Vengeance | Fury/soul management. Meta, Fiery Brand, Fel Devastation. Spirit Bomb, Fracture, Sigil of Flame. M+ S3 tank busters. |

### DPS

| Rotation | Builds | Highlights |
|----------|--------|------------|
| **HCS_Firemage** | Fire | Pyroblast, Fireball, Living Bomb. Spellsteal, Remove Curse. Ice Block, Alter Time, defensives. M+ cooldowns. |
| **HCS_FrostMage** | Spellsinger (M+/AoE) | Blizzard, Frozen Orb, Icy Veins, Splinterstorm. Flurry, Ice Lance, Glacial Spike. Dispels, interrupts, defensives. |

---

## Common Features (All Rotations)

- **Smart targeting** — Manual, Casters first, Skull first, or Smart (threat + execute + priority)
- **M+ S3 interrupt/stun list** — Priority kick handling for Season 3 dungeons
- **Boss checks** — Skip stuns/pushback on bosses (no wasted GCDs)
- **Right-click attack** (tanks) — Optional ranged pull
- **Class-colored headers** — Easy visual identification
- **Defensives** — HP sliders, potions, spec-specific CDs
- **Custom settings UI** — Tabbed window for keybinds, sliders, and options

---

## Folder Structure (For Contributors & Learners)

Each rotation follows this layout:

```
HCS_YourClass/
├── header.lua          # Plugin metadata + class/spec checks (load = true/false)
├── main.lua            # Core rotation logic, menu, callbacks
├── libraries/          # Self-contained helpers (no shared folder needed)
│   ├── hcs_class_colors.lua
│   ├── hcs_target_priority.lua
│   ├── mplus_s3_interrupt_stun_list.lua   # Tanks only
│   └── mplus_s3_tank_buster_list.lua      # Tanks only
└── extra/
    └── rotation_settings_ui.lua           # Custom tabbed settings window
```

### Key patterns

- **header.lua** — Returns `plugin` table with `name`, `version`, `load`. Uses `core.object_manager` and `enums` for class/spec validation.
- **main.lua** — `core.register_on_update_callback` for the main loop; `core.register_on_render_menu_callback` for the menu; `core.register_on_render_control_panel_callback` for the control panel.
- **libraries/** — Reusable modules (target priority, M+ lists, class colors). Each rotation ships its own copy so users never need a shared folder.
- **extra/rotation_settings_ui.lua** — Optional custom UI. Uses `common/color`, `common/geometry/vector_2`, `common/enums` from the loader API.

### Other folders (development)

- **shared/** — Development-only. Source for library files; rotations embed copies in `libraries/`. End users do not need this.
- **docs/** — Project Sylvanas reference (dispels, items, UI guide). Useful for contributors.

---

## Roadmap

We plan to release Mythic+ rotations for **all specs** over time. Currently available: Prot Paladin, Brewmaster Monk, Vengeance DH, Fire Mage, Frost Mage. Stay tuned for more.

---

## Requirements

- Project Sylvanas with IZI SDK support
