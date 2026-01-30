# HCS Monk Brewmaster Rotation Script

**Version:** 1.0.0  
**Author:** HCS  
**Build:** Shado-Pan (default) | Master of Harmony (menu toggle)

## Unlocker plugin structure

This folder is laid out for loading as an unlocker plugin zip:

```
HCS_Monk_Brew/
├── main.lua
├── header.lua
├── libraries/
│   ├── hcs_class_colors.lua
│   ├── hcs_target_priority.lua
│   ├── mplus_s3_interrupt_stun_list.lua
│   └── mplus_s3_tank_buster_list.lua
└── extra/
    └── rotation_settings_ui.lua
```

## Installation

1. **Zip and load as plugin:** Use the **plugin zip** (see below) and load it into your unlocker. The zip must contain only `.lua` files; root = `main.lua`, `header.lua`, `libraries/`, `extra/`.

2. **Or copy into scripts:** Copy the entire `HCS_Monk_Brew` folder into your Project Sylvanas `scripts/` directory. The unlocker must resolve `require("libraries/...")` and `require("extra/...")` relative to this folder.

3. Reload scripts or restart the unlocker.

### Building the plugin zip (under 6 MB)

The unlocker enforces a **6 MB** limit and accepts **only .lua and .md** in the zip (no .ps1, .txt, etc.). Use the build script:

- From the `scripts` folder:  
  `.\create_HCS_Monk_Brew_zip.ps1`
- Output: `HCS_Monk_Brew.zip` (~12 KB) in `scripts/`.

**Use only this zip** when loading the plugin. Do **not** zip the whole `HCS_Monk_Brew` folder manually—that includes `create_plugin_zip.ps1` (and other non-.lua/.md files) and will be rejected. The build script lives in `scripts/`, not inside `HCS_Monk_Brew`.

## Features

- **Dual Logic:** High Key (Survival) vs Low Key (Max DPS) — toggle via Logic mode
- **Smart Stagger:** Auto-Purify on heavy stagger; use Purifying Brew before capping charges
- **Auto Survival:** Fortifying / Celestial / Dampen Harm on dynamic HP thresholds (Survival mode)
- **Burst Sync:** Stack Bonedust Brew → Weapons of Order → Niuzao when both WoO and Niuzao ready
- **Energy anti-cap:** Expel Harm when energy above threshold to avoid wasting
- **Auto-Execute:** Touch of Death priority on low-HP targets (Smart targeting)
- **Smart AoE:** SCK priority when 5+ enemies (swap rotation)
- **Emergency Healing:** Vivify + Expel Harm when below critical HP%
- **Rotation:** Shado-Pan and Master of Harmony builds supported
- **Defensives:** M+ S3 tank buster reactions, self-healing (Expel Harm, potion, Fortifying, Celestial)
- **Interrupts/Stops:** Spear Hand Strike, Leg Sweep, Paralysis, Ring of Peace, Song of Chi-Ji (boss checks included)
- **Targeting:** Manual / Auto: Casters first / Auto: Skull first / Auto: Smart (threat + health + priority)
- **Cooldowns:** Weapons of Order, Explosive Brew, Invoke Niuzao, Celestial Brew
- **Utility:** Tiger's Lust (speed/root dispel), trinkets, right‑click attack from range

## Menu Options

- **Enable Plugin** – Master toggle  
- **Toggle Rotation** – Keybind to start/stop rotation  
- **Build:** Shado-Pan (default) or Master of Harmony  
- **Logic mode:** High Key (Survival) or Low Key (Max DPS)  
- **Use defensives + health potion** – Self-healing and mitigation  
- **Use defensives on M+ S3 tank busters** – Auto-react to known tank busters  
- **Targeting mode** – Manual / Casters first / Skull first / Smart  
- **Interrupt** – Spear Hand Strike / Leg Sweep  
- **M+ S3 list only** – Only interrupt/stop casts in the M+ S3 priority list  
- **Right‑click attack** – Optional range pull on right‑click  
- **Sliders:** Potion HP%, Expel Harm HP%, Emergency (Vivify+Expel) HP%, Vivify HP%, Fortifying HP%, Celestial HP%, Dampen Harm HP%, Energy anti-cap %

## Notes

- Stuns and pushback (Leg Sweep, etc.) skip bosses to avoid wasting GCDs.
- Self-healing works even with no target.
- Rotation follows guide-style priority based on your selected build.

## Support

For issues or questions, check the Project Sylvanas Discord or contact the author.
