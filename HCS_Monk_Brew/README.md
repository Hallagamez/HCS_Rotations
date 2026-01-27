# HCS Monk Brewmaster Rotation Script

**Version:** 1.0.0  
**Author:** HCS  
**Build:** Shado-Pan (default) | Master of Harmony (menu toggle)

## Installation

1. Copy the `HCS_Monk_Brew` folder to your Project Sylvanas scripts directory:
   ```
   scripts/HCS_Monk_Brew/
   ├── header.lua
   └── main.lua
   ```

2. The script requires these shared modules (should already exist in your scripts folder):
   - `shared/mplus_s3_interrupt_stun_list.lua`
   - `shared/mplus_s3_tank_buster_list.lua`
   - `shared/hcs_class_colors.lua` (optional, for colored menu header)
   - `shared/hcs_target_priority.lua` (for targeting modes)
   - `shared/rotation_settings_ui.lua` (optional, for custom UI window)

3. Reload your scripts or restart Project Sylvanas.

## Features

- **Rotation:** Shado-Pan and Master of Harmony builds supported
- **Defensives:** M+ S3 tank buster reactions, self-healing (Expel Harm, potion, Fortifying, Celestial)
- **Interrupts/Stops:** Spear Hand Strike, Leg Sweep, Paralysis, Ring of Peace, Song of Chi-Ji (boss checks included)
- **Targeting:** Manual / Auto: Casters first / Auto: Skull first
- **Cooldowns:** Weapons of Order, Explosive Brew, Invoke Niuzao, Celestial Brew
- **Utility:** Tiger's Lust (speed/root dispel), trinkets, party healing support

## Menu Options

- **Enable Plugin** - Master toggle
- **Toggle Rotation** - Keybind to start/stop rotation
- **Build:** Shado-Pan (default) or Master of Harmony
- **Use defensives + health potion** - Self-healing and mitigation
- **Use defensives on M+ S3 tank busters** - Auto-react to known tank busters
- **Targeting mode** - Manual / Auto: Casters first / Auto: Skull first
- **Interrupt** - Spear Hand Strike / Leg Sweep
- **M+ S3 list only** - Only interrupt/stop casts in the M+ S3 priority list

## Notes

- Stuns and pushback effects (Leg Sweep, Paralysis, Ring of Peace, Song of Chi-Ji) automatically skip bosses to avoid wasting GCDs
- Self-healing (Expel Harm, potion, Fortifying, Celestial) works even with no target
- Rotation follows guide-style priority based on your selected build

## Support

For issues or questions, check the Project Sylvanas Discord or contact the author.
