# HCS Rotations for Project Sylvanas

A collection of high-quality rotation scripts for World of Warcraft using the Project Sylvanas IZI SDK.

## Available Rotations

### Tanks
- **HCS_ProtPaladin** - Protection Paladin (Templar/Lightsmith/Instrument builds)
- **HCS_Monk_Brew** - Brewmaster Monk (Shado-Pan/Master of Harmony builds)
- **HCS_VengDH** - Vengeance Demon Hunter

### DPS
- **HCS_Firemage** - Fire Mage
- **HCS_FrostMage_MythicPlus** - Frost Mage (Mythic+ optimized)

## Features

All rotations include:
- ✅ **Smart Target Selection** - Threat, health, casters, and Skull priority
- ✅ **M+ S3 Interrupt/Stun Lists** - Priority interrupt handling
- ✅ **M+ S3 Tank Buster Reactions** - Auto-defensive usage
- ✅ **Boss Checks** - Stuns/pushback skip bosses (no wasted GCDs)
- ✅ **Right-click Attack/Taunt** - Optional range pulling
- ✅ **Class-colored Headers** - Visual class identification
- ✅ **Comprehensive Defensives** - Self-healing and mitigation

## Installation

1. Copy the rotation folders (`HCS_*`) to your Project Sylvanas `scripts/` directory
2. Copy the required `shared/` files:
   - `hcs_class_colors.lua`
   - `hcs_target_priority.lua`
   - `mplus_s3_interrupt_stun_list.lua`
   - `mplus_s3_tank_buster_list.lua`
3. Reload scripts or restart Project Sylvanas

## Shared Modules

The `shared/` folder contains:
- **hcs_class_colors.lua** - Class-colored menu headers
- **hcs_target_priority.lua** - Smart targeting (Manual / Casters / Skull / Smart)
- **mplus_s3_interrupt_stun_list.lua** - M+ Season 3 priority interrupt list
- **mplus_s3_tank_buster_list.lua** - M+ Season 3 tank buster reactions

## Requirements

- Project Sylvanas with IZI SDK support
- The shared modules listed above

## License

MIT License - See LICENSE file for details
