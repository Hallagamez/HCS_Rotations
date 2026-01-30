# Project Sylvanas – Examples Overview (Reference)

Practical, real-world examples for building plugins and automation with Project Sylvanas APIs and libraries. Also available on the **Project Sylvanas GitHub** repository.

---

## What you'll find

| Area | Description |
|------|-------------|
| **IZI SDK integration** | High-level IZI SDK: logging, event handling, time management, unit selection. |
| **Core API usage** | Callbacks, game object manipulation, spell casting. |
| **Graphics & rendering** | Visual overlays, ESP, custom UI via Graphics API. |
| **Event-driven programming** | Combat state, buff/debuff, spell casts via callback system. |
| **Combat automation** | Rotation helpers, target selection, combat utilities (Target Selector, etc.). |
| **UI development** | Configuration menus, control panels, custom UI via Menu API. |

---

## Prerequisites

- Basic Lua (variables, functions, tables, loops)
- Project Sylvanas **Core API** fundamentals
- Callbacks and **event-driven** programming
- The **game_object** class and its methods

---

## Example structure

Each example includes:

- **Clear documentation** – What the code does and why
- **Complete code** – Full, working implementations
- **Key concepts** – Learning points and best practices
- **Use cases** – Real-world scenarios

---

## Example categories

### Legacy API

Uses **Core API only** – low-level foundation.

- Understand fundamentals and how the system works
- Maximum control over implementation
- Learning the basics; maintaining existing scripts

**Best for:** Understanding core mechanisms, precise control, or maintaining legacy code.

---

### IZI SDK

Uses the **IZI SDK** – high-level toolkit.

- Less boilerplate, faster development
- Modern patterns, helpers, smart abstractions
- Advanced features with less effort; production plugins

**Best for:** New plugins, complex features, modern high-level APIs.

---

## Recommended learning path

1. **Start with IZI SDK examples**
   - Easier to learn, cleaner APIs
   - Fewer mistakes via built-in helpers
   - Better docs and patterns; faster results

2. **Then explore Legacy API examples** to:
   - Understand internals
   - Debug complex issues
   - Optimize performance-critical sections
   - Maintain or modify legacy code

**Mix and match:** Use IZI SDK for most logic; drop to Core API when you need fine-grained control. The IZI SDK sits on top of the Core API and works with it.

---

## Contributing

Useful examples or better implementations? Reach out on **Discord** to discuss adding yours.
