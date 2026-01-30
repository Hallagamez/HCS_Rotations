# Rotation Settings UI Library Guide

This guide is for people with little or no UI experience. It explains how to use the shared library **`shared/rotation_settings_ui.lua`** to build a custom settings window (with tabs, sliders, checkboxes, and keybinds) for your own rotation.

---

## What this library does (in simple words)

- Creates a **custom window** you can show/hide.
- Renders a **tab bar** across the top.
- Inside each tab, you can render common widgets:
  - **Keybind rows** (bind a key, toggle ON/OFF, clear)
  - **Checkbox grids**
  - **Slider lists**
  - **Combobox lists**
- Saves window position/size/tab selection using “ghost” menu elements (so it **persists across injections**).

You still need to:

- Create your **menu elements** (checkboxes/sliders/combos/keybinds) in your rotation file.
- Call **`ui:on_menu_render()`** and **`ui:on_render()`** from your rotation callbacks.

---

## Quick start (minimal steps)

1. **Create menu elements** (normal `core.menu.*` elements) in your rotation.
2. **Create a window** via `rotation_settings_ui.new({ ... })`.
3. **Define tabs and content** using `ui:add_tab(...)` (recommended) or `ui:register_section(...)` (legacy).
4. **Hook it into callbacks:**
   - call `ui:on_menu_render()` in **on_menu_render**
   - call `ui:on_render()` in **on_render**

---

## Full minimal example (copy/paste template)

```lua
local my_rotation = {}
local rotation_settings_ui = require("shared/rotation_settings_ui")

-- 1) Create menu elements (these store settings + persist automatically)
local menu_elements = {
  main_tree = core.menu.tree_node(),
  enable_script_check = core.menu.checkbox(true, "my_rotation_enable_script"),
  enable_toggle = core.menu.keybind(999, true, "my_rotation_enable_toggle"),
  cooldowns_toggle = core.menu.keybind(999, true, "my_rotation_cooldowns_toggle"),
  auto_pot_enabled = core.menu.checkbox(true, "my_rotation_auto_pot"),
  auto_pot_threshold = core.menu.slider_int(0, 100, 25, "my_rotation_auto_pot_hp"),
  burst_mode = core.menu.combobox(1, "my_rotation_burst_mode")
}

-- 2) Create the custom UI window
local ui = rotation_settings_ui.new({
  id = "my_rotation",
  title = "My Rotation Settings",
  default_x = 700,
  default_y = 200,
  default_w = 520,
  default_h = 650,
  theme = "neutral"  -- "rogue", "hunter", "astro", ...
})

-- 3) Define tabs and content (recommended API)
local function auto_pot_enabled()
  return menu_elements.auto_pot_enabled:get_state() == true
end

ui:add_tab({ id = "core", label = "Core" }, function(t)
  t:keybind_grid({
    elements = { menu_elements.enable_toggle, menu_elements.cooldowns_toggle },
    labels = { "Enable Rotation", "Burst Cooldowns" }
  })
end)

ui:add_tab({ id = "survival", label = "Survival" }, function(t)
  t:checkbox_grid({
    label = "Consumables",
    columns = 2,
    elements = { { element = menu_elements.auto_pot_enabled, label = "Auto Potion" } }
  })
  t:slider_list({
    label = "Thresholds",
    elements = {
      { element = menu_elements.auto_pot_threshold, label = "Potion HP%", suffix = "%", visible_when = auto_pot_enabled }
    }
  })
  t:combo_list({
    label = "Modes",
    elements = { { element = menu_elements.burst_mode, label = "Burst Mode", options = { "Smart", "Always" } } }
  })
end)

-- 4) Hook into your rotation callbacks
function my_rotation:on_menu_render()
  ui:on_menu_render()
  menu_elements.main_tree:render("My Rotation", function()
    menu_elements.enable_script_check:render("Enable Script")
    if ui and ui.menu and ui.menu.enable then
      ui.menu.enable:render("Show Custom UI Window")
    end
  end)
end

function my_rotation:on_render()
  ui:on_render()
end

return my_rotation
```

---

## Building tabs with the Builder API (recommended)

Use **`ui:add_tab({ ... }, function(t) ... end)`**. Inside the callback, `t` is a tab builder.

| Method | Description |
|--------|-------------|
| `t:keybind_grid({ elements = {...}, labels = {...} })` | Keybind rows |
| `t:checkbox_grid({ label?, columns?, elements = { {element=checkbox, label="..."}, ... } })` | Checkbox grid |
| `t:slider_list({ label?, elements = { {element=slider, label="...", suffix?, visible_when?}, ... } })` | Slider list |
| `t:combo_list({ label?, elements = { {element=combobox, label="...", options={...}, suffix?, visible_when?}, ... } })` | Combobox list |

### Element shapes

- **Checkbox:** `{ element = menu_elements.auto_pot_enabled, label = "Auto Potion", visible_when = function() return true end }`
- **Slider:** `{ element = menu_elements.auto_pot_threshold, label = "Potion HP%", suffix = "%", visible_when = auto_pot_enabled }`
- **Combobox:** `{ element = menu_elements.burst_mode, label = "Burst Mode", options = { "Smart", "Always" } }`

---

## Conditional visibility (`visible_when`)

You can hide:

- a full **tab**: `ui:add_tab({ ..., visible_when = fn }, ...)`
- a **group**: pass `visible_when` to `checkbox_grid` / `slider_list` / …
- a single **entry** in a group (each entry can have `visible_when`)

Rules: `visible_when` must be a **function** that returns `true` or `false`. Keep it quick and safe.

Example:

```lua
local function advanced_enabled()
  return menu_elements.show_advanced:get_state() == true
end
ui:add_tab({ id = "advanced", label = "Advanced", visible_when = advanced_enabled }, function(t)
  t:slider_list({ elements = { { element = menu_elements.some_slider, label = "Extra" } } })
end)
```

---

## Themes and window identity

- **Theme:** `theme` only affects colors. Available in `shared/rotation_settings_ui.lua`: e.g. `neutral`, `rogue`, `hunter`, `astro`.
- **id (important):** Must be **unique per window**. Used for persistence (position, size, active tab, enable checkbox). If two windows share the same `id`, they will conflict over saved state.

---

## Interaction notes

### Keybind capture

- Click the key badge to start capture, then press a key.
- Supports keyboard + mouse buttons (except LMB/RMB).
- **Del** clears the bind, **Esc** cancels.

### Sliders

- Click the bar to start dragging; hold left mouse button.
- Dragging clamps at min/max.
- If a slider “jumps”, the backend may use a different coordinate space; report which slider and where the window is on screen.

---

## Legacy API (still supported)

```lua
ui:register_section({
  id = "combat",
  label = "Combat",
  type = "tab",
  groups = {
    {
      label = "Thresholds",
      type = "slider_list",
      elements = { { element = menu_elements.auto_pot_threshold, label = "Potion HP%", suffix = "%" } }
    }
  }
})
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| **Nothing shows up** | Call `ui:on_render()` in your rotation `on_render` callback. Enable the window via “Show Custom UI Window” or `ui.menu.enable:set(true)` for debugging. |
| **Tab is empty** | Add groups inside the `add_tab` callback. Check `visible_when` isn’t returning false. |
| **Widgets don’t change values** | Use real `core.menu.*` objects (checkbox/slider/combobox/keybind). For sliders, keep min ≤ max. |
