# Project Sylvanas – Universal Items (Reference)

Optional sub-plugin of **Universal Utility**. Install from Marketplace, then:

**Main Menu → Universal Utility → Universal Items**

Automated handling for **Trinkets**, **Elixirs**, **Potions**, and **Stones** (plus **Dynamic Slots**) based on custom rules, combat context, and prediction.

---

## Supported Items

| Item | Notes |
|------|--------|
| **Trinkets** | Slot (Top/Bot/Both), GCD usage, cast type (self/target/skillshot), logic (offensive/defensive). |
| **Dynamic Slot** | Any equipment slot (head, gloves, wrist, cloak, weapon, etc.). Multiple configs, loadout-based switching. Good for belt gadgets, on-use cloaks, weapon actives. |
| **Damage Elixir / Healthstone / Health Potion / Mana Potion** | Health thresholds, distance checks, combat-length filters, **Forecast mode** for upcoming damage. |

Advanced options: Prediction Mode, Spell Data Overrides, Buff Pairing, Cooldown Syncing.

---

## Trinkets

**Menu:** Main Menu → Universal Utility → Universal Items → Trinkets

Configure once per item; when you swap gear, set up the new trinket.

### 1. Configuration workflow

1. **Item Slot** – `Top` | `Bot` | `Both` (separate logic per slot if Both).
2. **Global Cooldown** – `Skips Global` (e.g. Gladiator's Badge) vs `Has Global`.
3. **Logic Type** – `Offensive` (burst) vs `Defensive` (e.g. shields).
4. **Cast Type** – `Self` | `Target` | `Skillshot`.

If **Skillshot**:
- **Prediction Settings** (see below).
- **Spell Data Settings** (Time to Hit Override, Cast Delay, conditionals like “don’t cast while immune”, LOS, min enemies clumped).

### 2. Skillshot prediction

| Setting | Options |
|--------|---------|
| **Prediction Type** | Most Hits, Accuracy |
| **Prediction Mode** | No prediction, Center, Intersection, Custom (interception % slider) |

### 3. Spell data

- **Time to Hit Override** – Trinket travel time for prediction.
- **Cast Delay** – Delay before casting (e.g. after stun).
- **Conditionals** – Immune check, LOS, min enemies, etc.

### 4. Presets & advanced

- Presets for popular PvP/PvE trinkets.
- **Spell Pairing** – Use trinket when a specific ability is cast.
- **Buff Pairing** – Use only with specific buff (e.g. Combustion, Wings).

---

## Summary (Trinkets)

| Setting | Description |
|--------|-------------|
| Item Slot | Top, Bot, or Both |
| Global Cooldown | Skips vs uses GCD |
| Logic Type | Offensive or Defensive |
| Cast Type | Self, Target, or Skillshot |
| Prediction Mode | Aiming for skillshots |
| Spell Data | Cast time, impact, conditionals |
| Advanced Pairing | Sync with spells or buffs |

---

*Reference for HCS rotations: when using Universal Items for trinkets/potions, rotation scripts can avoid duplicating trinket logic or can document that users should configure items there.*
